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
use Carbon\Carbon;
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
            'type' => ['nullable', 'string', 'in:time_in,time_out'],
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

        $event = Event::findOrFail($validated['event_id']);

        if (!$event->is_active) {
            return response()->json([
                'success' => false,
                'code' => 'EVENT_INACTIVE',
                'message' => 'Attendance check-in for this event is currently closed.',
            ], 422);
        }

        // 1. Strict Time Slot Window Alignment (Supports both Time-In and Time-Out)
        $appTimezone = config('app.timezone', 'Asia/Manila');
        $now = Carbon::now($appTimezone);
        $today = $now->toDateString();

        $eventDay = $event->days()->whereDate('event_date', $today)->first();

        if (!$eventDay) {
            return response()->json([
                'success' => false,
                'code' => 'NO_SCHEDULE_TODAY',
                'message' => 'No active schedule configured for today.',
            ], 422);
        }

        $slots = is_string($eventDay->slots) ? json_decode($eventDay->slots, true) : $eventDay->slots;

        if (empty($slots)) {
            return response()->json([
                'success' => false,
                'code' => 'NO_SLOTS_TODAY',
                'message' => 'No active schedule slots configured for today.',
            ], 422);
        }

        $checkType = $validated['type'] ?? 'time_in';
        $allowedTimeWindow = false;

        foreach ($slots as $slot) {
            if ($checkType === 'time_out') {
                $startStr = $slot['time_out_start'] ?? $slot['time_in_start'] ?? null;
                $endStr = $slot['time_out_end'] ?? $slot['time_in_end'] ?? null;
            } else {
                $startStr = $slot['time_in_start'] ?? null;
                $endStr = $slot['time_in_end'] ?? null;
            }

            if (!empty($startStr)) {
                $start = Carbon::parse($today . ' ' . $startStr, $appTimezone);
                $cutoff = !empty($endStr) ? Carbon::parse($today . ' ' . $endStr, $appTimezone) : null;

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
            return response()->json([
                'success' => false,
                'code' => 'TIME_WINDOW_CLOSED',
                'message' => 'Attendance is currently closed for ' . str_replace('_', ' ', $checkType) . '.',
            ], 422);
        }

        // 2. Geofence Check
        if ($event->is_geofenced && $event->latitude && $event->longitude) {
            $distance = $this->calculateDistance(
                (float) $validated['latitude'],
                (float) $validated['longitude'],
                (float) $event->latitude,
                (float) $event->longitude
            );

            if ($distance > $event->radius_meters) {
                $remaining = round($distance - $event->radius_meters);
                return response()->json([
                    'success' => false,
                    'code' => 'OUTSIDE_GEOFENCE',
                    'message' => "You are outside the event area. Move about {$remaining}m closer to check in.",
                ], 422);
            }
        }

        // 3. Challenge Consumption
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

        // 4. Biometric Liveness Verification
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

        // 5. Save Attendance Record
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

        $this->notify($request, $event, true, 'Attendance recorded successfully.', $attendance->status);

        return response()->json([
            'success' => true,
            'code' => 'ATTENDANCE_RECORDED',
            'message' => 'Attendance recorded successfully.',
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
        } catch (AttendanceException $e) {
            return response()->json([
                'success' => false,
                'code' => $e->errorCode,
                'message' => $e->getMessage(),
                'data' => $e->data,
            ], $e->httpStatus);
        }

        $this->notify($request, $event, true, 'Offline attendance synchronized successfully.', $attendance->status);

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

    private function calculateDistance(float $lat1, float $lon1, float $lat2, float $lon2): float
    {
        $earthRadius = 6371000;

        $dLat = deg2rad($lat2 - $lat1);
        $dLon = deg2rad($lon2 - $lon1);

        $a = sin($dLat / 2) * sin($dLat / 2) +
            cos(deg2rad($lat1)) * cos(deg2rad($lat2)) *
            sin($dLon / 2) * sin($dLon / 2);

        $c = 2 * atan2(sqrt($a), sqrt(1 - $a));

        return $earthRadius * $c;
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