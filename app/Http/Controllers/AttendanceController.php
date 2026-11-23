<?php

namespace App\Http\Controllers;

use App\Exceptions\AttendanceException;
use App\Models\Attendance;
use App\Models\Event;
use App\Models\StudentNotification;
use App\Services\BiometricService;
use App\Services\SlotResolver;
use Carbon\Carbon;
use Carbon\CarbonInterface;
use Illuminate\Database\QueryException;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class AttendanceController extends Controller
{
    /**
     * Mark web attendance for a specific slot window (Time-In or Time-Out) 
     * using the full multi-frame tri-color flash and head-turn liveness protocol.
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

        // 1. Validate request payload including challenge nonce, flash frames, and turn peak frame
        $validated = $request->validate([
            'challenge_nonce'   => ['required', 'string'],
            'event_id'          => ['required', 'integer', 'exists:events,event_id'],
            'slot_index'        => ['required', 'integer', 'min:0', 'max:99'],
            'type'              => ['required', 'in:in,out'],
            'checkpoint_key'    => ['nullable', 'string', 'max:50'],
            'live_camera_frame' => ['required', 'image', 'mimes:jpeg,png,jpg', 'max:5048'],
            'flash_frames'      => ['required', 'array', 'min:3', 'max:3'], // Must contain exactly 3 flash frames (Red, Green, Blue)
            'flash_frames.*'    => ['image', 'mimes:jpeg,png,jpg', 'max:5048'],
            'turn_peak_frame'   => ['required', 'image', 'mimes:jpeg,png,jpg', 'max:5048'],
            'direction'         => ['required', 'in:left,right'],
            'latitude'          => ['required', 'numeric', 'between:-90,90'],
            'longitude'         => ['required', 'numeric', 'between:-180,180'],
        ]);

        $event = Event::findOrFail($validated['event_id']);

        if (!$event->is_active) {
            return back()->withErrors([
                'attendance' => 'Attendance for this event is currently closed.',
            ]);
        }

        $now = Carbon::now(config('app.timezone', 'UTC'));

        // 2. Slot & window validation using the server as the authority
        try {
            $resolved = $slots->resolve(
                $event,
                $now,
                (int) $validated['slot_index'],
                $validated['checkpoint_key'] ?? null,
                $validated['type']
            );

            // Cheap slot-aware duplicate check before expensive AI processing
            $slots->guard($student->student_id, $event->event_id, $resolved);
        } catch (AttendanceException $e) {
            return back()->withErrors(['attendance' => $e->getMessage()]);
        }

        // 3. Geofence verification
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

        // 4. Biometric & Tri-Color Flash Liveness Verification & Embedding Extraction
        try {
            // Define the expected flash colors matching the challenge session
            $flashColors = ['red', 'green', 'blue'];

            $liveEmbedding = $bio->verifyLivenessAndExtractEmbedding(
                frontal: $validated['live_camera_frame'],
                flashFrames: $validated['flash_frames'],
                turnPeak: $validated['turn_peak_frame'],
                direction: $validated['direction'],
                flashColors: $flashColors,
                cameraLabel: $request->input('camera_label')
            );
        } catch (\App\Exceptions\BiometricServiceException $e) {
            return back()->withErrors([
                'attendance' => $e->getMessage(),
            ]);
        } catch (\Throwable $e) {
            return back()->withErrors([
                'attendance' => 'Unable to complete biometric liveness verification. Please try again.',
            ]);
        }

        if (!is_array($liveEmbedding) || !$liveEmbedding) {
            return back()->withErrors([
                'attendance' => 'The camera could not produce a usable face embedding. Please try again.',
            ]);
        }

        // 5. Compare the live embedding with the student's registered account embedding
        $similarity = BiometricService::cosineSimilarity($liveEmbedding, $student->face_embedding);
        $threshold = (float) config('face_verification.profile_match_threshold', 0.50);

        if ($similarity < $threshold) {
            return back()->withErrors([
                'attendance' => 'Face verification failed. Please face the camera clearly and try again.',
            ]);
        }

        $checkpointKey = $validated['checkpoint_key'] 
            ?? $resolved['checkpoint_key'] 
            ?? $this->inferCheckpointKey($resolved['type'], $now);

        // 6. Save the attendance record and dispatch notification within a transaction
        try {
            DB::transaction(function () use ($slots, $student, $event, $resolved, $similarity, $validated, $now, $checkpointKey) {
                $slots->guard($student->student_id, $event->event_id, $resolved, true);

                Attendance::create([
                    'attendance_uuid'      => (string) Str::uuid(),
                    'student_id'           => $student->student_id,
                    'event_id'             => $event->event_id,
                    'event_date'           => $resolved['date'],
                    'slot_index'           => $resolved['index'],
                    'type'                 => $resolved['type'],
                    'checkpoint_key'       => $checkpointKey,
                    'logged_at'            => now(),
                    'attendance_time'      => $now,
                    'sync_time'            => now(),
                    'status'               => $resolved['status'],
                    'sync_status'          => 'synced',
                    'source'               => 'web_online',
                    'confidence_score'     => round($similarity, 4),
                    'liveness_passed'      => true,
                    'liveness_method'      => 'tri_color_flash_pose_rotation',
                    'latitude'             => $validated['latitude'],
                    'longitude'            => $validated['longitude'],
                ]);

                // Create a notification for the student's notification center
                $checkpointTitle = match ($checkpointKey) {
                    Attendance::MORNING_TIME_IN => 'Morning Time-In Recorded',
                    Attendance::MORNING_TIME_OUT => 'Morning Time-Out Recorded',
                    Attendance::AFTERNOON_TIME_IN => 'Afternoon Time-In Recorded',
                    Attendance::AFTERNOON_TIME_OUT => 'Afternoon Time-Out Recorded',
                    default => $resolved['type'] === 'out' ? 'Checked Out Successfully' : 'Checked In Successfully',
                };

                StudentNotification::create([
                    'student_id' => $student->student_id,
                    'title'      => $checkpointTitle,
                    'message'    => "You have successfully logged {$checkpointKey} for {$event->title} on Slot " . ($resolved['index'] + 1) . ".",
                    'type'       => 'attendance',
                    'is_read'    => false,
                ]);
            });
        } catch (AttendanceException $e) {
            return back()->withErrors(['attendance' => $e->getMessage()]);
        } catch (QueryException $e) {
            // Handle unique constraint violation (concurrent duplicate check-ins)
            if (str_starts_with((string) $e->getCode(), '23')) {
                $errorMessage = match ($checkpointKey) {
                    Attendance::MORNING_TIME_IN => 'You have already logged your morning time-in for this time slot.',
                    Attendance::MORNING_TIME_OUT => 'You have already logged your morning time-out for this time slot.',
                    Attendance::AFTERNOON_TIME_IN => 'You have already logged your afternoon time-in for this time slot.',
                    Attendance::AFTERNOON_TIME_OUT => 'You have already logged your afternoon time-out for this time slot.',
                    default => $resolved['type'] === 'out'
                        ? 'You have already checked out for this time slot.'
                        : 'You have already checked in for this time slot.',
                };

                return back()->withErrors([
                    'attendance' => $errorMessage,
                ]);
            }

            throw $e;
        }

        return back()->with(
            'success',
            'Attendance checkpoint logged successfully!'
        );
    }

    /**
     * Infer checkpoint key based on type and timestamp if not explicitly provided.
     */
    private function inferCheckpointKey(string $type, CarbonInterface $at): string
    {
        $hour = (int) $at->format('G');

        if ($type === 'in') {
            return $hour < 12 ? Attendance::MORNING_TIME_IN : Attendance::AFTERNOON_TIME_IN;
        }

        return $hour < 12 ? Attendance::MORNING_TIME_OUT : Attendance::AFTERNOON_TIME_OUT;
    }

    /**
     * Calculate distance in meters between two lat/lng coordinates (Haversine formula).
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