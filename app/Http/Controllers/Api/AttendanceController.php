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
    public function analyzeLivenessFrame(
        Request $request,
        BiometricService $bio
    ): JsonResponse {
        $request->validate([
            'frame' => ['required', 'image', 'mimes:jpeg,jpg,png', 'max:5048'],
        ]);

        try {
            return response()->json([
                'success' => true,
                'code' => 'LIVENESS_FRAME_ANALYZED',
                'message' => 'Attendance liveness frame analyzed.',
                'data' => $bio->analyzeLivenessFrame($request->file('frame')),
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
     * Mobile attendance uses exactly two biometric frames:
     * 1. straight/frontal frame
     * 2. requested left/right turn frame
     *
     * No blink, smile, or return-to-center frame is accepted or required.
     */
    public function mobileCheckIn(
        Request $request,
        AttendanceService $service,
        BiometricService $bio,
        FaceChallengeService $challenges
    ): JsonResponse {
        $validated = $request->validate([
            'event_id' => ['required', 'integer', 'exists:events,event_id'],
            'challenge_nonce' => ['required', 'string', 'max:100'],
            'session_id' => ['required', 'string', 'min:16', 'max:100'],
            'latitude' => ['required', 'numeric', 'between:-90,90'],
            'longitude' => ['required', 'numeric', 'between:-180,180'],
            'location_accuracy' => ['nullable', 'numeric', 'min:0', 'max:10000'],
            'center_frame' => ['required', 'image', 'mimes:jpeg,jpg,png', 'max:5048'],
            'turned_frame' => ['required', 'image', 'mimes:jpeg,jpg,png', 'max:5048'],
        ]);

        $user = $request->user();
        $student = $user?->student;

        // 1. Verify student record and face biometrics registration status (matches web controller)
        if (!$student || $student->verification_status !== 'verified' || !$student->face_embedding) {
            return response()->json([
                'success' => false,
                'code' => 'STUDENT_NOT_VERIFIED',
                'message' => 'Your face biometrics are not registered or verified yet.',
            ], 403);
        }

        $event = Event::findOrFail($validated['event_id']);

        // 2. Ensure event is active (matches web controller)
        if (!($event->is_active ?? true)) {
            return response()->json([
                'success' => false,
                'code' => 'EVENT_INACTIVE',
                'message' => 'Attendance check-in for this event is currently closed.',
            ], 422);
        }

        // 3. Prevent duplicate check-ins (matches web controller)
        $alreadyCheckedIn = Attendance::where('student_id', $student->student_id)
            ->where('event_id', $event->event_id)
            ->exists();

        if ($alreadyCheckedIn) {
            return response()->json([
                'success' => false,
                'code' => 'ALREADY_CHECKED_IN',
                'message' => 'You have already checked in for this event.',
            ], 422);
        }

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
                'code' => 'LIVENESS_CHALLENGE_INVALID',
                'message' => 'Your liveness challenge is invalid or expired. Please start again.',
            ], 422);
        }

        $direction = $challenge['direction'];

        try {
            $liveness = $bio->verifyLiveness(
                $direction,
                $request->file('center_frame'),
                $request->file('turned_frame')
            );
        } catch (\Throwable $e) {
            $this->notify($request, $event, false, $e->getMessage());

            return response()->json([
                'success' => false,
                'code' => 'LIVENESS_FAILED',
                'message' => $e->getMessage(),
            ], 422);
        }

        if (!($liveness['passed'] ?? false)) {
            $message = $liveness['detail'] ?? 'Liveness verification failed.';
            $this->notify($request, $event, false, $message);

            return response()->json([
                'success' => false,
                'code' => 'LIVENESS_FAILED',
                'message' => $message,
                'data' => ['direction' => $direction],
            ], 422);
        }

        // 4. Extract live frontal embedding and perform Cosine Similarity check against profile embedding (matches web controller)
        $liveEmbedding = $liveness['frontal_embedding'] ?? null;

        if (!is_array($liveEmbedding) || !$liveEmbedding) {
            return response()->json([
                'success' => false,
                'code' => 'EMBEDDING_EXTRACTION_FAILED',
                'message' => 'The camera could not produce a usable face embedding. Please try again.',
            ], 422);
        }

        $similarity = BiometricService::cosineSimilarity(
            $liveEmbedding,
            $student->face_embedding
        );

        $threshold = (float) config('face_verification.profile_match_threshold', 0.50);

        if ($similarity < $threshold) {
            $this->notify($request, $event, false, 'Face verification failed.');

            return response()->json([
                'success' => false,
                'code' => 'FACE_MISMATCH',
                'message' => 'Face verification failed. Please face the camera clearly and try again.',
            ], 422);
        }

        try {
            $attendance = $service->record(
                user: $user,
                event: $event,
                liveCameraFrame: $request->file('center_frame'),
                latitude: (float) $validated['latitude'],
                longitude: (float) $validated['longitude'],
                locationAccuracy: isset($validated['location_accuracy'])
                    ? (float) $validated['location_accuracy']
                    : null,
                livenessPassed: true,
                source: 'mobile_online',
                isOfflineSync: false
            );

            // Update attendance confidence score with the computed cosine similarity
            $attendance->update(['confidence_score' => round($similarity, 4)]);

        } catch (AttendanceException $e) {
            $this->notify($request, $event, false, $e->getMessage());

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
            'message' => 'Attendance recorded successfully.',
            'data' => [
                'attendance' => $attendance->load('event'),
                'liveness' => $liveness,
                'similarity_score' => round($similarity, 4),
                'geofence' => [
                    'passed' => true,
                    'distance_meters' => $attendance->distance_from_event,
                    'allowed_radius_meters' => $event->radius_meters,
                ],
            ],
        ]);
    }

    /**
     * Synchronize an offline center + turn attendance record.
     */
    public function sync(
        Request $request,
        AttendanceService $service,
        BiometricService $bio
    ): JsonResponse {
        $validated = $request->validate([
            'event_id' => ['required', 'integer', 'exists:events,event_id'],
            'liveness_direction' => ['required', 'in:left,right'],
            'attendance_uuid' => ['required', 'uuid'],
            'attendance_time' => ['required', 'date'],
            'latitude' => ['required', 'numeric', 'between:-90,90'],
            'longitude' => ['required', 'numeric', 'between:-180,180'],
            'location_accuracy' => ['nullable', 'numeric', 'min:0', 'max:10000'],
            'center_frame' => ['required', 'image', 'mimes:jpeg,jpg,png', 'max:5048'],
            'turned_frame' => ['required', 'image', 'mimes:jpeg,jpg,png', 'max:5048'],
        ]);

        $user = $request->user();
        $student = $user?->student;

        if (!$student || $student->verification_status !== 'verified' || !$student->face_embedding) {
            return response()->json([
                'success' => false,
                'code' => 'STUDENT_NOT_VERIFIED',
                'message' => 'Your face biometrics are not registered or verified yet.',
            ], 403);
        }

        $event = Event::findOrFail($validated['event_id']);
        $direction = $validated['liveness_direction'];

        try {
            $liveness = $bio->verifyLiveness(
                $direction,
                $request->file('center_frame'),
                $request->file('turned_frame')
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
                'message' => $liveness['detail'] ?? 'Liveness verification failed.',
            ], 422);
        }

        $liveEmbedding = $liveness['frontal_embedding'] ?? null;
        if (is_array($liveEmbedding) && $liveEmbedding) {
            $similarity = BiometricService::cosineSimilarity($liveEmbedding, $student->face_embedding);
            $threshold = (float) config('face_verification.profile_match_threshold', 0.50);

            if ($similarity < $threshold) {
                return response()->json([
                    'success' => false,
                    'code' => 'FACE_MISMATCH',
                    'message' => 'Face verification failed. Please face the camera clearly and try again.',
                ], 422);
            }
        }

        try {
            $attendance = $service->record(
                user: $user,
                event: $event,
                liveCameraFrame: $request->file('center_frame'),
                latitude: (float) $validated['latitude'],
                longitude: (float) $validated['longitude'],
                locationAccuracy: isset($validated['location_accuracy'])
                    ? (float) $validated['location_accuracy']
                    : null,
                livenessPassed: true,
                attendanceUuid: $validated['attendance_uuid'],
                attendanceTime: $validated['attendance_time'],
                source: 'mobile_offline',
                isOfflineSync: true
            );

            if (isset($similarity)) {
                $attendance->update(['confidence_score' => round($similarity, 4)]);
            }

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
            'code' => 'OFFLINE_ATTENDANCE_SYNCED',
            'message' => 'Offline attendance synchronized successfully.',
            'data' => [
                'attendance' => $attendance->load('event'),
                'liveness' => $liveness,
                'geofence' => [
                    'passed' => true,
                    'distance_meters' => $attendance->distance_from_event,
                    'allowed_radius_meters' => $event->radius_meters,
                ],
            ],
        ]);
    }

    public function history(Request $request): JsonResponse
    {
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
                'message' => 'Student record not found.',
                'data' => [],
            ], 404);
        }

        $limit = min(max((int) $request->input('limit', 50), 1), 100);

        $records = Attendance::with('event')
            ->where('student_id', $student->student_id)
            ->orderByDesc('attendance_time')
            ->orderByDesc('logged_at')
            ->limit($limit)
            ->get();

        return response()->json([
            'success' => true,
            'code' => 'ATTENDANCE_HISTORY_RETRIEVED',
            'message' => 'Attendance history retrieved successfully.',
            'data' => $records,
        ]);
    }

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

    private function notify(
        Request $request,
        Event $event,
        bool $success,
        string $message,
        ?string $status = null
    ): void {
        $studentId = $request->user()?->student_id;

        if (!$studentId) {
            return;
        }

        rescue(function () use ($studentId, $success, $message, $status) {
            StudentNotification::create([
                'student_id' => $studentId,
                'type' => $success ? 'attendance_success' : 'attendance_error',
                'title' => $success ? 'Attendance recorded' : 'Attendance update',
                'message' => $status
                    ? "{$message} Status: {$status}."
                    : $message,
            ]);
        });
    }
}