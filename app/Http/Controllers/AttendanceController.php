<?php

namespace App\Http\Controllers;

use App\Exceptions\AttendanceException;
use App\Models\Attendance;
use App\Models\Event;
use App\Services\BiometricService;
use App\Services\SlotResolver;
use Carbon\Carbon;
use Illuminate\Database\QueryException;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class AttendanceController extends Controller
{
    /**
     * Mark web attendance for ONE slot window (Time-In or Time-Out) with two
     * frames: straight-on + requested left/right turn.
     */
    public function markAttendance(Request $request, BiometricService $bio, SlotResolver $slots)
    {
        $user = Auth::user();
        $student = $user?->student;

        if (!$student || $student->verification_status !== 'verified' || !$student->face_embedding) {
            return back()->withErrors([
                'attendance' => 'Your face biometrics are not registered or verified yet.',
            ]);
        }

        // 1. Validate request (now includes WHICH slot and WHICH window)
        $validated = $request->validate([
            'event_id' => ['required', 'integer', 'exists:events,event_id'],
            'slot_index' => ['required', 'integer', 'min:0', 'max:99'],
            'type' => ['required', 'in:in,out'],
            'live_camera_frame' => ['required', 'image', 'mimes:jpeg,png,jpg', 'max:5048'],
            'turn_peak_frame' => ['required', 'image', 'mimes:jpeg,png,jpg', 'max:5048'],
            'direction' => ['required', 'in:left,right'],
            'latitude' => ['required', 'numeric', 'between:-90,90'],
            'longitude' => ['required', 'numeric', 'between:-180,180'],
        ]);

        $event = Event::findOrFail($validated['event_id']);

        if (!$event->is_active) {
            return back()->withErrors([
                'attendance' => 'Attendance for this event is currently closed.',
            ]);
        }

        $now = Carbon::now(config('app.timezone', 'UTC'));

        // 2. Slot + window validation. The server is the authority: it looks up the
        //    requested slot for today and checks that its Time-In / Time-Out window
        //    is open right now. Unlimited slots are supported.
        try {
            $resolved = $slots->resolve(
                $event,
                $now,
                (int) $validated['slot_index'],
                $validated['type']
            );

            // 3. Cheap slot-aware duplicate check BEFORE the expensive AI work.
            $slots->guard($student->student_id, $event->event_id, $resolved);
        } catch (AttendanceException $e) {
            return back()->withErrors(['attendance' => $e->getMessage()]);
        }

        // 4. Geofence (validated before AI face verification) - applies to every submission
        if ($event->is_geofenced && $event->latitude && $event->longitude) {
            $distance = $this->calculateDistance(
                (float) $validated['latitude'],
                (float) $validated['longitude'],
                (float) $event->latitude,
                (float) $event->longitude
            );

            if ($distance > $event->radius_meters) {
                $remaining = round($distance - $event->radius_meters);

                return back()->withErrors([
                    'attendance' => "You are outside the event area. Move about {$remaining}m closer to check in.",
                ]);
            }
        }

        // 5. Biometric & liveness verification - runs for every Time-In AND Time-Out
        try {
            $liveness = $bio->verifyLiveness(
                $validated['direction'],
                $validated['live_camera_frame'],
                $validated['turn_peak_frame'],
            );
        } catch (\Throwable $e) {
            return back()->withErrors([
                'attendance' => 'Unable to complete biometric liveness verification. Please try again.',
            ]);
        }

        if (!($liveness['passed'] ?? false)) {
            return back()->withErrors([
                'attendance' => $liveness['detail'] ?? 'Liveness verification failed. Please try again.',
            ]);
        }

        $liveEmbedding = $liveness['frontal_embedding'] ?? null;

        if (!is_array($liveEmbedding) || !$liveEmbedding) {
            return back()->withErrors([
                'attendance' => 'The camera could not produce a usable face embedding. Please try again.',
            ]);
        }

        $similarity = BiometricService::cosineSimilarity($liveEmbedding, $student->face_embedding);
        $threshold = (float) config('face_verification.profile_match_threshold', 0.50);

        if ($similarity < $threshold) {
            return back()->withErrors([
                'attendance' => 'Face verification failed. Please face the camera clearly and try again.',
            ]);
        }

        // 6. Save the record. Re-check inside a transaction (race between two taps);
        //    the unique index is the final safety net.
        try {
            DB::transaction(function () use ($slots, $student, $event, $resolved, $similarity, $validated, $now) {
                $slots->guard($student->student_id, $event->event_id, $resolved, true);

                Attendance::create([
                    'attendance_uuid' => (string) Str::uuid(),
                    'student_id' => $student->student_id,
                    'event_id' => $event->event_id,
                    'event_date' => $resolved['date'],
                    'slot_index' => $resolved['index'],
                    'type' => $resolved['type'],
                    'logged_at' => now(),
                    'attendance_time' => $now,
                    'sync_time' => now(),
                    'status' => $resolved['status'],
                    'sync_status' => 'synced',
                    'source' => 'web_online',
                    'confidence_score' => round($similarity, 4),
                    'liveness_passed' => true,
                    'liveness_method' => 'insightface_pose_rotation',
                    'latitude' => $validated['latitude'],
                    'longitude' => $validated['longitude'],
                ]);
            });
        } catch (AttendanceException $e) {
            return back()->withErrors(['attendance' => $e->getMessage()]);
        } catch (QueryException $e) {
            // SQLSTATE 23xxx = integrity constraint (unique index hit by a concurrent request)
            if (str_starts_with((string) $e->getCode(), '23')) {
                return back()->withErrors([
                    'attendance' => $resolved['type'] === 'out'
                        ? 'You have already checked out for this time slot.'
                        : 'You have already checked in for this time slot.',
                ]);
            }

            throw $e;
        }

        return back()->with(
            'success',
            $resolved['type'] === 'out' ? 'Checked out successfully!' : 'Checked in successfully!'
        );
    }

    /**
     * Distance in meters between two lat/lng points (Haversine).
     */
    private function calculateDistance(float $lat1, float $lon1, float $lat2, float $lon2): float
    {
        $earthRadius = 6371000;

        $dLat = deg2rad($lat2 - $lat1);
        $dLon = deg2rad($lon2 - $lon1);

        $a = sin($dLat / 2) * sin($dLat / 2) +
            cos(deg2rad($lat1)) * cos(deg2rad($lat2)) *
            sin($dLon / 2) * sin($dLon / 2);

        return $earthRadius * 2 * atan2(sqrt($a), sqrt(1 - $a));
    }
}