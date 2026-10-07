<?php

namespace App\Http\Controllers;

use App\Models\Attendance;
use App\Models\Event;
use App\Services\BiometricService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Str;
use Carbon\Carbon;

class AttendanceController extends Controller
{
    /**
     * Mark web attendance with exactly two frames:
     * straight-on + requested left/right turn.
     */
    public function markAttendance(Request $request, BiometricService $bio)
    {
        $user = Auth::user();
        $student = $user?->student;

        if (!$student || $student->verification_status !== 'verified' || !$student->face_embedding) {
            return back()->withErrors([
                'attendance' => 'Your face biometrics are not registered or verified yet.',
            ]);
        }

        // 1. Validate request including GPS coordinates from the browser
        $validated = $request->validate([
            'event_id' => ['required', 'integer', 'exists:events,event_id'],
            'live_camera_frame' => ['required', 'image', 'mimes:jpeg,png,jpg', 'max:5048'],
            'turn_peak_frame' => ['required', 'image', 'mimes:jpeg,png,jpg', 'max:5048'],
            'direction' => ['required', 'in:left,right'],
            'latitude' => ['required', 'numeric', 'between:-90,90'],
            'longitude' => ['required', 'numeric', 'between:-180,180'],
        ]);

        $event = Event::findOrFail($validated['event_id']);

        if (!$event->is_active) {
            return back()->withErrors([
                'attendance' => 'Attendance check-in for this event is currently closed.',
            ]);
        }

        // 1.5. Strict Time Slot Window Validation with application timezone alignment
        $appTimezone = config('app.timezone', 'UTC');
        $now = Carbon::now($appTimezone);
        $today = $now->toDateString();
        
        $eventDay = $event->days()->whereDate('event_date', $today)->first();

        if (!$eventDay || empty($eventDay->slots)) {
            return back()->withErrors([
                'attendance' => 'No active schedule or time slots configured for today.',
            ]);
        }

        $allowedTimeWindow = false;
        foreach ($eventDay->slots as $slot) {
            // Check Time-In Window (supports start and optional cutoff/end time)
            if (!empty($slot['time_in_start'])) {
                $start = Carbon::parse($today . ' ' . $slot['time_in_start'], $appTimezone);
                $cutoff = !empty($slot['time_in_end']) ? Carbon::parse($today . ' ' . $slot['time_in_end'], $appTimezone) : null;

                if ($cutoff) {
                    if ($now->between($start, $cutoff)) {
                        $allowedTimeWindow = true;
                        break;
                    }
                } else {
                    if ($now->greaterThanOrEqualTo($start)) {
                        $allowedTimeWindow = true;
                        break;
                    }
                }
            }
        }

        if (!$allowedTimeWindow) {
            return back()->withErrors([
                'attendance' => 'Attendance is currently closed. You can only check in during the designated time slot windows.',
            ]);
        }

        // 2. Strict Geofence Pre-Check (Validates location BEFORE running AI face verification)
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

        $alreadyCheckedIn = Attendance::where('student_id', $student->student_id)
            ->where('event_id', $event->event_id)
            ->exists();

        if ($alreadyCheckedIn) {
            return back()->withErrors([
                'attendance' => 'You have already checked in for this event.',
            ]);
        }

        // 3. Perform Biometric & Liveness Verification
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

        $similarity = BiometricService::cosineSimilarity(
            $liveEmbedding,
            $student->face_embedding,
        );

        $threshold = (float) config('face_verification.profile_match_threshold', 0.50);

        if ($similarity < $threshold) {
            return back()->withErrors([
                'attendance' => 'Face verification failed. Please face the camera clearly and try again.',
            ]);
        }

        // 4. Save Attendance Record
        Attendance::create([
            'attendance_uuid' => (string) Str::uuid(),
            'student_id' => $student->student_id,
            'event_id' => $event->event_id,
            'logged_at' => now(),
            'attendance_time' => now(),
            'sync_time' => now(),
            'status' => 'present',
            'sync_status' => 'synced',
            'source' => 'web_online',
            'confidence_score' => round($similarity, 4),
            'liveness_passed' => true,
            'liveness_method' => 'insightface_pose_rotation',
        ]);

        return back()->with('success', 'Attendance marked successfully!');
    }

    /**
     * Helper to calculate distance in meters between two lat/lng coordinates (Haversine formula).
     */
    private function calculateDistance(float $lat1, float $lon1, float $lat2, float $lon2): float
    {
        $earthRadius = 6371000; // meters

        $dLat = deg2rad($lat2 - $lat1);
        $dLon = deg2rad($lon2 - $lon1);

        $a = sin($dLat / 2) * sin($dLat / 2) +
            cos(deg2rad($lat1)) * cos(deg2rad($lat2)) *
            sin($dLon / 2) * sin($dLon / 2);

        $c = 2 * atan2(sqrt($a), sqrt(1 - $a));

        return $earthRadius * $c;
    }
}