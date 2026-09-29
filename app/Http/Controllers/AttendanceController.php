<?php

namespace App\Http\Controllers;

use App\Models\Attendance;
use App\Models\Event;
use App\Services\BiometricService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Str;

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

        $validated = $request->validate([
            'event_id' => ['required', 'integer', 'exists:events,event_id'],
            'live_camera_frame' => ['required', 'image', 'mimes:jpeg,png,jpg', 'max:5048'],
            'turn_peak_frame' => ['required', 'image', 'mimes:jpeg,png,jpg', 'max:5048'],
            'direction' => ['required', 'in:left,right'],
        ]);

        $event = Event::findOrFail($validated['event_id']);

        if (!$event->is_active) {
            return back()->withErrors([
                'attendance' => 'Attendance check-in for this event is currently closed.',
            ]);
        }

        $alreadyCheckedIn = Attendance::where('student_id', $student->student_id)
            ->where('event_id', $event->event_id)
            ->exists();

        if ($alreadyCheckedIn) {
            return back()->withErrors([
                'attendance' => 'You have already checked in for this event.',
            ]);
        }

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
}
