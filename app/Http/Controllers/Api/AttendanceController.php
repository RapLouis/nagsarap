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
use App\Services\SlotResolver;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\UploadedFile;
use ReflectionMethod;

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

    public function mobileCheckIn(
        Request $request,
        AttendanceService $service,
        BiometricService $bio,
        FaceChallengeService $challenges,
        SlotResolver $slots
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
            'flash_frames' => ['nullable', 'array'],
            'flash_frames.*' => ['image', 'mimes:jpeg,jpg,png', 'max:5048'],
            'flash_colors' => ['nullable', 'array'],
            'slot_index' => ['nullable', 'integer', 'min:0', 'max:99'],
            'checkpoint_key' => ['nullable', 'string', 'in:morning_time_in,morning_time_out,afternoon_time_in,afternoon_time_out'],
            'type' => ['nullable', 'string', 'in:in,out,time_in,time_out'],
        ]);

        $user = $request->user();
        $student = $user?->student;

        if (!$student) {
            return response()->json([
                'success' => false,
                'code' => 'STUDENT_REQUIRED',
                'message' => 'Student record not found.',
            ], 403);
        }

        $event = Event::with('days')->findOrFail($validated['event_id']);

        if (!$event->is_active) {
            return response()->json([
                'success' => false,
                'code' => 'EVENT_INACTIVE',
                'message' => 'Attendance check-in for this event is currently closed.',
            ], 422);
        }

        $appTimezone = config('app.timezone', 'Asia/Manila');
        $now = Carbon::now($appTimezone);

        $slotIndex = isset($validated['slot_index']) ? (int) $validated['slot_index'] : null;
        $checkpointKey = $validated['checkpoint_key'] ?? null;
        $type = $this->normalizeType($validated['type'] ?? null);

        // 1. Pre-validate slot/checkpoint window & duplicate guard before consuming challenge nonce
        try {
            $resolved = $this->resolveSlotSafely(
                slots: $slots,
                event: $event,
                at: $now,
                slotIndex: $slotIndex,
                checkpointKey: $checkpointKey,
                type: $type
            );
            $slots->guard($student->student_id, $event->event_id, $resolved);
        } catch (AttendanceException $e) {
            return response()->json([
                'success' => false,
                'code' => $e->errorCode,
                'message' => $e->getMessage(),
                'data' => $e->data,
            ], $e->httpStatus);
        }

        // 2. Consume Liveness Challenge Nonce
        $challenge = $challenges->consume(
            $student->student_id,
            $validated['challenge_nonce'],
            $validated['session_id'],
            'attendance',
            (int) $event->event_id
        );

        if (!($challenge['valid'] ?? false)) {
            $this->notify($request, $event, false, 'Liveness challenge invalid or expired.');

            return response()->json([
                'success' => false,
                'code' => 'LIVENESS_CHALLENGE_INVALID',
                'message' => 'Your liveness challenge is invalid or expired. Please start again.',
            ], 422);
        }

        $direction = $challenge['direction'];
        $flashFrames = $request->file('flash_frames', []);
        if (!is_array($flashFrames)) {
            $flashFrames = [];
        }

        $flashColors = !empty($challenge['flash_colors']) && is_array($challenge['flash_colors'])
            ? $challenge['flash_colors']
            : ($validated['flash_colors'] ?? []);
        if (!is_array($flashColors)) {
            $flashColors = [];
        }

        // 3. Biometric Liveness Verification
        try {
            $liveness = !empty($flashFrames)
                ? $bio->verifyLiveness(
                    $direction,
                    $request->file('center_frame'),
                    $request->file('turned_frame'),
                    $flashFrames,
                    $flashColors
                )
                : $bio->verifyLiveness(
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

        // 4. Record Attendance via Teammate's AttendanceService (parameter-order safe)
        try {
            $attendance = $this->invokeRecordSafely(
                service: $service,
                user: $user,
                event: $event,
                liveCameraFrame: $request->file('center_frame'),
                latitude: (float) $validated['latitude'],
                longitude: (float) $validated['longitude'],
                locationAccuracy: isset($validated['location_accuracy'])
                    ? (float) $validated['location_accuracy']
                    : null,
                livenessPassed: true,
                attendanceUuid: null,
                attendanceTime: $now,
                source: 'mobile_online',
                isOfflineSync: false,
                slotIndex: $resolved['index'],
                type: $resolved['type'],
                checkpointKey: $resolved['checkpoint_key']
            );
        } catch (AttendanceException $e) {
            $this->notify($request, $event, false, $e->getMessage());

            return response()->json([
                'success' => false,
                'code' => $e->errorCode,
                'message' => $e->getMessage(),
                'data' => $e->data,
            ], $e->httpStatus);
        } catch (\Throwable $e) {
            return response()->json([
                'success' => false,
                'code' => 'ATTENDANCE_RECORD_ERROR',
                'message' => $e->getMessage(),
            ], 500);
        }

        $effectiveCheckpoint = $attendance->checkpoint_key ?: $resolved['checkpoint_key'];
        $checkpointLabel = $this->checkpointLabel($effectiveCheckpoint);
        $this->notify($request, $event, true, "{$checkpointLabel} recorded successfully.", $attendance->status);

        return response()->json([
            'success' => true,
            'code' => 'ATTENDANCE_RECORDED',
            'message' => "{$checkpointLabel} recorded successfully.",
            'data' => [
                'attendance' => $attendance->load('event'),
                'liveness' => $liveness,
                'geofence' => [
                    'passed' => true,
                    'distance_meters' => $attendance->distance_from_event,
                    'allowed_radius_meters' => $event->radius_meters,
                ],
                'server_time' => $now->toIso8601String(),
            ],
        ]);
    }

    public function sync(
        Request $request,
        AttendanceService $service,
        BiometricService $bio,
        SlotResolver $slots
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
            'flash_frames' => ['nullable', 'array'],
            'flash_frames.*' => ['image', 'mimes:jpeg,jpg,png', 'max:5048'],
            'flash_colors' => ['nullable', 'array'],
            'slot_index' => ['nullable', 'integer', 'min:0', 'max:99'],
            'checkpoint_key' => ['nullable', 'string', 'in:morning_time_in,morning_time_out,afternoon_time_in,afternoon_time_out'],
            'type' => ['nullable', 'string', 'in:in,out,time_in,time_out'],
            'session_type' => ['nullable', 'string', 'in:in,out,time_in,time_out'],
        ]);

        $appTimezone = config('app.timezone', 'Asia/Manila');
        $serverNow = Carbon::now($appTimezone);
        $submittedTime = Carbon::parse($validated['attendance_time'], $appTimezone);

        // Anti-spoofing: cap future timestamps back to server time
        if ($submittedTime->greaterThan($serverNow->copy()->addMinutes(5))) {
            $submittedTime = $serverNow->copy();
            $validated['attendance_time'] = $serverNow->toDateTimeString();
        }

        $user = $request->user();
        $event = Event::with('days')->findOrFail($validated['event_id']);
        $direction = $validated['liveness_direction'];

        $flashFrames = $request->file('flash_frames', []);
        if (!is_array($flashFrames)) {
            $flashFrames = [];
        }
        $flashColors = is_array($validated['flash_colors'] ?? null) ? $validated['flash_colors'] : [];

        try {
            $liveness = !empty($flashFrames)
                ? $bio->verifyLiveness(
                    $direction,
                    $request->file('center_frame'),
                    $request->file('turned_frame'),
                    $flashFrames,
                    $flashColors
                )
                : $bio->verifyLiveness(
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

        $slotIndex = isset($validated['slot_index']) ? (int) $validated['slot_index'] : null;
        $checkpointKey = $validated['checkpoint_key'] ?? null;
        $type = $this->normalizeType($validated['type'] ?? $validated['session_type'] ?? null);

        try {
            $resolved = $this->resolveSlotSafely(
                slots: $slots,
                event: $event,
                at: $submittedTime,
                slotIndex: $slotIndex,
                checkpointKey: $checkpointKey,
                type: $type
            );

            $attendance = $this->invokeRecordSafely(
                service: $service,
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
                isOfflineSync: true,
                slotIndex: $resolved['index'],
                type: $resolved['type'],
                checkpointKey: $resolved['checkpoint_key']
            );
        } catch (AttendanceException $e) {
            return response()->json([
                'success' => false,
                'code' => $e->errorCode,
                'message' => $e->getMessage(),
                'data' => $e->data,
            ], $e->httpStatus);
        }

        $effectiveCheckpoint = $attendance->checkpoint_key ?: $resolved['checkpoint_key'];
        $checkpointLabel = $this->checkpointLabel($effectiveCheckpoint);
        $this->notify($request, $event, true, "Offline {$checkpointLabel} synchronized successfully.", $attendance->status);

        return response()->json([
            'success' => true,
            'code' => 'OFFLINE_ATTENDANCE_SYNCED',
            'message' => "Offline {$checkpointLabel} synchronized successfully.",
            'data' => [
                'attendance' => $attendance->load('event'),
                'liveness' => $liveness,
                'geofence' => [
                    'passed' => true,
                    'distance_meters' => $attendance->distance_from_event,
                    'allowed_radius_meters' => $event->radius_meters,
                ],
                'server_time' => $serverNow->toIso8601String(),
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
            app(FaceChallengeService::class),
            app(SlotResolver::class)
        );
    }

    /**
     * Resolves the 4-checkpoint slot safely against the teammate's SlotResolver.
     */
    private function resolveSlotSafely(
        SlotResolver $slots,
        Event $event,
        Carbon $at,
        ?int $slotIndex,
        ?string $checkpointKey,
        ?string $type
    ): array {
        if (method_exists($slots, 'resolveOrInfer')) {
            return $slots->resolveOrInfer(
                event: $event,
                at: $at,
                slotIndex: $slotIndex,
                checkpointKey: $checkpointKey,
                type: $type
            );
        }

        $effectiveKey = $checkpointKey;
        if (!$effectiveKey) {
            $hour = (int) $at->format('G');
            if ($type === 'out') {
                $effectiveKey = $hour < 12 ? 'morning_time_out' : 'afternoon_time_out';
            } else {
                $effectiveKey = $hour < 12 ? 'morning_time_in' : 'afternoon_time_in';
            }
        }

        if ($slotIndex !== null && method_exists($slots, 'resolve')) {
            return $slots->resolve($event, $at, $slotIndex, $effectiveKey);
        }

        // Fallback scan across all 4 checkpoints on matching event days
        $event->loadMissing('days');
        $candidates = $checkpointKey
            ? [$checkpointKey]
            : ($type === 'out'
                ? ['morning_time_out', 'afternoon_time_out']
                : ($type === 'in'
                    ? ['morning_time_in', 'afternoon_time_in']
                    : ['morning_time_in', 'morning_time_out', 'afternoon_time_in', 'afternoon_time_out']));

        foreach ([$at->toDateString(), $at->copy()->subDay()->toDateString()] as $dateStr) {
            $day = $event->days->first(
                fn ($d) => Carbon::parse($d->event_date)->toDateString() === $dateStr
            );
            if (!$day) {
                continue;
            }

            foreach (array_values($day->slots ?? []) as $idx => $slot) {
                if (!is_array($slot)) {
                    continue;
                }
                if ($slotIndex !== null && $idx !== $slotIndex) {
                    continue;
                }

                foreach ($candidates as $candidateKey) {
                    if (method_exists($slots, 'resolve')) {
                        try {
                            return $slots->resolve($event, $at, $idx, $candidateKey);
                        } catch (AttendanceException) {
                            continue;
                        }
                    }
                }
            }
        }

        throw new AttendanceException(
            'EVENT_OUTSIDE_WINDOW',
            'Attendance is not open for this event at the supplied time.',
            422,
            ['attendance_time' => $at->toIso8601String()]
        );
    }

    /**
     * Invokes teammate's AttendanceService::record() using parameter reflection so
     * positional/named argument order differences never cause a mismatch, and ensures
     * checkpoint_key and slot_index are persisted on the created record.
     */
    private function invokeRecordSafely(
        AttendanceService $service,
        $user,
        Event $event,
        UploadedFile $liveCameraFrame,
        float $latitude,
        float $longitude,
        ?float $locationAccuracy,
        bool $livenessPassed,
        ?string $attendanceUuid,
        mixed $attendanceTime,
        string $source,
        bool $isOfflineSync,
        ?int $slotIndex,
        ?string $type,
        ?string $checkpointKey
    ): Attendance {
        $availableArgs = [
            'user' => $user,
            'event' => $event,
            'liveCameraFrame' => $liveCameraFrame,
            'latitude' => $latitude,
            'longitude' => $longitude,
            'locationAccuracy' => $locationAccuracy,
            'livenessPassed' => $livenessPassed,
            'attendanceUuid' => $attendanceUuid,
            'attendanceTime' => $attendanceTime,
            'source' => $source,
            'isOfflineSync' => $isOfflineSync,
            'slotIndex' => $slotIndex,
            'type' => $type,
            'checkpointKey' => $checkpointKey,
        ];

        $ref = new ReflectionMethod($service, 'record');
        $callArgs = [];

        foreach ($ref->getParameters() as $param) {
            $name = $param->getName();
            if (array_key_exists($name, $availableArgs)) {
                $callArgs[$name] = $availableArgs[$name];
            }
        }

        /** @var Attendance $attendance */
        $attendance = $service->record(...$callArgs);

        $dirty = false;
        if ($checkpointKey && empty($attendance->checkpoint_key)) {
            $attendance->checkpoint_key = $checkpointKey;
            $dirty = true;
        }
        if ($slotIndex !== null && $attendance->slot_index === null) {
            $attendance->slot_index = $slotIndex;
            $dirty = true;
        }
        if ($dirty) {
            $attendance->save();
        }

        return $attendance;
    }

    private function normalizeType(?string $type): ?string
    {
        if ($type === null || trim($type) === '') {
            return null;
        }

        return match (strtolower(trim($type))) {
            'in', 'time_in', 'checkin', 'check_in' => 'in',
            'out', 'time_out', 'checkout', 'check_out' => 'out',
            default => null,
        };
    }

    private function checkpointLabel(?string $checkpointKey): string
    {
        return match ($checkpointKey) {
            'morning_time_in' => 'Morning Time-In',
            'morning_time_out' => 'Morning Time-Out',
            'afternoon_time_in' => 'Afternoon Time-In',
            'afternoon_time_out' => 'Afternoon Time-Out',
            default => 'Attendance',
        };
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