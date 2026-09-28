<?php

namespace App\Http\Controllers;

use App\Exceptions\AttendanceException;
use App\Models\Event;
use App\Services\AttendanceService;
use App\Services\BiometricService;
use App\Services\FaceChallengeService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;

class AttendanceController extends Controller
{
    /**
     * Mark attendance from the web application.
     *
     * Uses the same two-step liveness flow:
     * CENTER -> TURN LEFT or TURN RIGHT.
     */
    public function markAttendance(
        Request $request,
        AttendanceService $service,
        BiometricService $bio,
        FaceChallengeService $challenges
    ) {
        $user = Auth::user();

        if (!$user) {
            return back()->withErrors([
                'attendance' => 'You must be logged in.',
            ]);
        }

        $student = $user->student;

        if (
            !$student
            || $student->verification_status !== 'verified'
            || empty($student->face_embedding)
        ) {
            return back()->withErrors([
                'attendance' =>
                    'Your face biometrics are not registered or verified yet.',
            ]);
        }

        $validated = $request->validate([
            'event_id' => [
                'required',
                'integer',
                'exists:events,event_id',
            ],

            'challenge_nonce' => [
                'required',
                'string',
                'max:100',
            ],

            'session_id' => [
                'required',
                'string',
                'min:16',
                'max:100',
            ],

            'latitude' => [
                'required',
                'numeric',
                'between:-90,90',
            ],

            'longitude' => [
                'required',
                'numeric',
                'between:-180,180',
            ],

            'location_accuracy' => [
                'nullable',
                'numeric',
                'min:0',
                'max:10000',
            ],

            'center_frame' => [
                'required',
                'image',
                'mimes:jpeg,jpg,png',
                'max:5048',
            ],

            'turned_frame' => [
                'required',
                'image',
                'mimes:jpeg,jpg,png',
                'max:5048',
            ],
        ]);

        $event = Event::findOrFail(
            $validated['event_id']
        );

        /*
         * Consume the liveness challenge.
         *
         * The server determines whether the student
         * must turn LEFT or RIGHT.
         */
        $challenge = $challenges->consume(
            $student->student_id,
            $validated['challenge_nonce'],
            $validated['session_id'],
            'attendance',
            (int) $event->event_id
        );

        if (!($challenge['valid'] ?? false)) {
            return back()->withErrors([
                'attendance' =>
                    'Your liveness challenge is invalid or expired. Please start again.',
            ]);
        }

        $direction = $challenge['direction'];

        /*
         * Verify:
         *
         * CENTER -> requested TURN LEFT/RIGHT
         *
         * BiometricService currently expects a third
         * frame argument, so the center frame is reused
         * for that legacy parameter. No returned, blink,
         * or smile frame is required or uploaded.
         */
        try {
            $liveness = $bio->verifyLiveness(
                $direction,
                $request->file('center_frame'),
                $request->file('turned_frame'),
                $request->file('center_frame')
            );
        } catch (\Throwable $e) {
            return back()->withErrors([
                'attendance' => $e->getMessage(),
            ]);
        }

        if (!($liveness['passed'] ?? false)) {
            return back()->withErrors([
                'attendance' =>
                    $liveness['detail']
                    ?? 'Liveness verification failed.',
            ]);
        }

        /*
         * Record attendance.
         *
         * The turned frame is used as the final camera
         * evidence instead of a returned frame.
         */
        try {
            $service->record(
                user: $user,
                event: $event,
                liveCameraFrame: $request->file('turned_frame'),
                latitude: (float) $validated['latitude'],
                longitude: (float) $validated['longitude'],
                locationAccuracy:
                    isset($validated['location_accuracy'])
                        ? (float) $validated['location_accuracy']
                        : null,
                livenessPassed: true,
                source: 'web_online',
                isOfflineSync: false
            );
        } catch (AttendanceException $e) {
            return back()->withErrors([
                'attendance' => $e->getMessage(),
            ]);
        }

        return back()->with(
            'success',
            'Attendance recorded successfully.'
        );
    }
}