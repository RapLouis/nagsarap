<?php

namespace App\Http\Controllers\Api;

use App\Exceptions\AttendanceException;
use App\Http\Controllers\Controller;
use App\Models\Attendance;
use App\Models\Event;
use App\Models\StudentNotification;
use App\Services\AttendanceService;
use App\Services\BiometricService;
use App\Services\FaceChallengeService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class AttendanceController extends Controller
{
    /**
     * Analyze one liveness frame.
     */
    public function analyzeLivenessFrame(
        Request $request,
        BiometricService $bio
    ): JsonResponse {
        $request->validate([
            'frame' => [
                'required',
                'image',
                'mimes:jpeg,jpg,png',
                'max:5048',
            ],
        ]);

        try {
            $data = $bio->analyzeLivenessFrame(
                $request->file('frame')
            );

            return response()->json([
                'success' => true,
                'code' => 'LIVENESS_FRAME_ANALYZED',
                'message' =>
                    'Attendance liveness frame analyzed.',
                'data' => $data,
            ]);
        } catch (\Throwable $e) {
            return response()->json([
                'success' => false,
                'code' => 'LIVENESS_FRAME_FAILED',
                'message' => $e->getMessage(),
            ], 422);
        }
    }

    /**
     * Online mobile attendance.
     */
    public function mobileCheckIn(
        Request $request,
        AttendanceService $service,
        BiometricService $bio,
        FaceChallengeService $challenges
    ): JsonResponse {
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

            'returned_frame' => [
                'required',
                'image',
                'mimes:jpeg,jpg,png',
                'max:5048',
            ],

            'blink_frame' => [
                'nullable',
                'image',
                'mimes:jpeg,jpg,png',
                'max:5048',
            ],

            'smile_frame' => [
                'nullable',
                'image',
                'mimes:jpeg,jpg,png',
                'max:5048',
            ],
        ]);

        $user = $request->user();

        $student = $user?->student;

        if (!$student) {
            return response()->json([
                'success' => false,
                'code' => 'STUDENT_REQUIRED',
                'message' =>
                    'Student record not found.',
            ], 403);
        }

        $event = Event::findOrFail(
            $validated['event_id']
        );

        /*
         * Consume the challenge.
         *
         * The server determines whether the user must turn
         * LEFT or RIGHT. The mobile application must follow
         * this direction.
         */
        $challenge = $challenges->consume(
            $student->student_id,
            $validated['challenge_nonce'],
            $validated['session_id'],
            'attendance',
            (int) $event->event_id
        );

        if (!($challenge['valid'] ?? false)) {
            $this->notify(
                $request,
                $event,
                false,
                'Liveness challenge invalid or expired.'
            );

            return response()->json([
                'success' => false,
                'code' =>
                    'LIVENESS_CHALLENGE_INVALID',
                'message' =>
                    'Your liveness challenge is invalid or expired. Please start again.',
            ], 422);
        }

        $direction = $challenge['direction'];

        /*
         * Verify the requested direction.
         */
        try {
            $liveness = $bio->verifyLiveness(
                $direction,
                $request->file('center_frame'),
                $request->file('turned_frame'),
                $request->file('returned_frame')
            );
        } catch (\Throwable $e) {
            $this->notify(
                $request,
                $event,
                false,
                $e->getMessage()
            );

            return response()->json([
                'success' => false,
                'code' => 'LIVENESS_FAILED',
                'message' => $e->getMessage(),
            ], 422);
        }

        if (!($liveness['passed'] ?? false)) {
            $message =
                $liveness['detail']
                ?? 'Liveness verification failed.';

            $this->notify(
                $request,
                $event,
                false,
                $message
            );

            return response()->json([
                'success' => false,
                'code' => 'LIVENESS_FAILED',
                'message' => $message,
                'data' => [
                    'direction' => $direction,
                ],
            ], 422);
        }

        /*
         * Record attendance.
         */
        try {
            $attendance = $service->record(
                user: $user,
                event: $event,
                liveCameraFrame:
                    $request->file('returned_frame'),
                latitude:
                    (float) $validated['latitude'],
                longitude:
                    (float) $validated['longitude'],
                locationAccuracy:
                    isset(
                        $validated['location_accuracy']
                    )
                        ? (float) $validated[
                            'location_accuracy'
                        ]
                        : null,
                livenessPassed: true,
                source: 'mobile_online',
                isOfflineSync: false
            );
        } catch (AttendanceException $e) {
            $this->notify(
                $request,
                $event,
                false,
                $e->getMessage()
            );

            return response()->json([
                'success' => false,
                'code' => $e->errorCode,
                'message' => $e->getMessage(),
                'data' => $e->data,
            ], $e->httpStatus);
        }

        $this->notify(
            $request,
            $event,
            true,
            'Attendance recorded successfully.',
            $attendance->status
        );

        return response()->json([
            'success' => true,
            'code' => 'ATTENDANCE_RECORDED',
            'message' =>
                'Attendance recorded successfully.',
            'data' => [
                'attendance' =>
                    $attendance->load('event'),

                'liveness' => $liveness,

                'geofence' => [
                    'passed' => true,
                    'distance_meters' =>
                        $attendance->distance_from_event,
                    'allowed_radius_meters' =>
                        $event->radius_meters,
                ],
            ],
        ]);
    }

    /**
     * Synchronize an offline attendance record.
     */
    public function sync(
        Request $request,
        AttendanceService $service,
        BiometricService $bio
    ): JsonResponse {
        $validated = $request->validate([
            'event_id' => [
                'required',
                'integer',
                'exists:events,event_id',
            ],

            'liveness_direction' => [
                'required',
                'in:left,right',
            ],

            'attendance_uuid' => [
                'required',
                'uuid',
            ],

            'attendance_time' => [
                'required',
                'date',
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

            'returned_frame' => [
                'required',
                'image',
                'mimes:jpeg,jpg,png',
                'max:5048',
            ],

            'blink_frame' => [
                'nullable',
                'image',
                'mimes:jpeg,jpg,png',
                'max:5048',
            ],

            'smile_frame' => [
                'nullable',
                'image',
                'mimes:jpeg,jpg,png',
                'max:5048',
            ],
        ]);

        $user = $request->user();

        $event = Event::findOrFail(
            $validated['event_id']
        );

        $direction =
            $validated['liveness_direction'];

        /*
         * Offline attendance still performs server-side
         * liveness verification when synchronization occurs.
         */
        try {
            $liveness = $bio->verifyLiveness(
                $direction,
                $request->file('center_frame'),
                $request->file('turned_frame'),
                $request->file('returned_frame')
            );
        } catch (\Throwable $e) {
            return response()->json([
                'success' => false,
                'code' => 'LIVENESS_FAILED',
                'message' => $e->getMessage(),
            ], 422);
        }

        if (!($liveness['passed'] ?? false)) {
            return response()->json([
                'success' => false,
                'code' => 'LIVENESS_FAILED',
                'message' =>
                    $liveness['detail']
                    ?? 'Liveness verification failed.',
            ], 422);
        }

        /*
         * Record the offline attendance using the original
         * attendance timestamp and UUID.
         */
        try {
            $attendance = $service->record(
                user: $user,
                event: $event,
                liveCameraFrame:
                    $request->file('returned_frame'),
                latitude:
                    (float) $validated['latitude'],
                longitude:
                    (float) $validated['longitude'],
                locationAccuracy:
                    isset(
                        $validated['location_accuracy']
                    )
                        ? (float) $validated[
                            'location_accuracy'
                        ]
                        : null,
                livenessPassed: true,
                attendanceUuid:
                    $validated['attendance_uuid'],
                attendanceTime:
                    $validated['attendance_time'],
                source: 'mobile_offline',
                isOfflineSync: true
            );
        } catch (AttendanceException $e) {
            return response()->json([
                'success' => false,
                'code' => $e->errorCode,
                'message' => $e->getMessage(),
                'data' => $e->data,
            ], $e->httpStatus);
        }

        $this->notify(
            $request,
            $event,
            true,
            'Offline attendance synchronized successfully.',
            $attendance->status
        );

        return response()->json([
            'success' => true,
            'code' =>
                'OFFLINE_ATTENDANCE_SYNCED',
            'message' =>
                'Offline attendance synchronized successfully.',
            'data' => [
                'attendance' =>
                    $attendance->load('event'),

                'liveness' => $liveness,

                'geofence' => [
                    'passed' => true,
                    'distance_meters' =>
                        $attendance->distance_from_event,
                    'allowed_radius_meters' =>
                        $event->radius_meters,
                ],
            ],
        ]);
    }

    /**
     * Get attendance history for the authenticated student.
     */
    public function history(
        Request $request
    ): JsonResponse {
        $user = $request->user();

        if (!$user) {
            return response()->json([
                'success' => false,
                'code' => 'UNAUTHENTICATED',
                'message' => 'Authentication required.',
                'data' => [],
            ], 401);
        }

        $student = $user->student;

        if (!$student) {
            return response()->json([
                'success' => false,
                'code' => 'STUDENT_NOT_FOUND',
                'message' =>
                    'Student record not found.',
                'data' => [],
            ], 404);
        }

        $limit = min(
            max(
                (int) $request->input(
                    'limit',
                    50
                ),
                1
            ),
            100
        );

        $records = Attendance::with('event')
            ->where(
                'student_id',
                $student->student_id
            )
            ->orderByDesc('attendance_time')
            ->orderByDesc('logged_at')
            ->limit($limit)
            ->get();

        return response()->json([
            'success' => true,
            'code' =>
                'ATTENDANCE_HISTORY_RETRIEVED',
            'message' =>
                'Attendance history retrieved successfully.',
            'data' => $records,
        ]);
    }

    /**
     * Compatibility endpoint.
     *
     * Uses the same implementation as mobileCheckIn.
     */
    public function checkIn(
        Request $request,
        AttendanceService $service
    ): JsonResponse {
        return $this->mobileCheckIn(
            $request,
            $service,
            app(BiometricService::class),
            app(FaceChallengeService::class)
        );
    }

    /**
     * Create a notification after attendance activity.
     */
    private function notify(
        Request $request,
        Event $event,
        bool $success,
        string $message,
        ?string $status = null
    ): void {
        $studentId =
            $request->user()?->student_id;

        if (!$studentId) {
            return;
        }

        rescue(
            function () use (
                $studentId,
                $success,
                $message,
                $status
            ) {
                StudentNotification::create([
                    'student_id' => $studentId,

                    'type' =>
                        $success
                            ? 'attendance_success'
                            : 'attendance_error',

                    'title' =>
                        $success
                            ? 'Attendance recorded'
                            : 'Attendance update',

                    'message' => $status
                        ? "{$message} Status: {$status}."
                        : $message,
                ]);
            }
        );
    }
}