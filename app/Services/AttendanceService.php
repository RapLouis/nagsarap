<?php

namespace App\Services;

use App\Exceptions\AttendanceException;
use App\Models\Attendance;
use App\Models\Event;
use App\Models\User;
use Carbon\Carbon;
use Carbon\CarbonInterface;
use Illuminate\Database\QueryException;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class AttendanceService
{
    public function __construct(
        private readonly GeofenceService $geofenceService,
        private readonly BiometricService $biometrics,
        private readonly SlotResolver $slots
    ) {
    }

    /**
     * Record attendance after all required verification has passed.
     */
    public function record(
        User $user,
        Event $event,
        UploadedFile $liveCameraFrame,
        float $latitude,
        float $longitude,
        ?float $locationAccuracy,
        bool $livenessPassed,
        ?string $attendanceUuid = null,
        mixed $attendanceTime = null,
        string $source = 'mobile_online',
        bool $isOfflineSync = false,
        ?int $slotIndex = null,
        ?string $type = null
    ): Attendance {
        $student = $user->student;

        if (!$student) {
            throw new AttendanceException(
                'STUDENT_REQUIRED',
                'A student account is required to record attendance.',
                403
            );
        }

        if (
            $student->verification_status !== 'verified'
            || empty($student->face_embedding)
        ) {
            throw new AttendanceException(
                'BIOMETRIC_NOT_VERIFIED',
                'Complete biometric registration before recording attendance.',
                403
            );
        }

        if (!$livenessPassed) {
            throw new AttendanceException(
                'LIVENESS_REQUIRED',
                'Liveness verification is required.',
                422
            );
        }

        $attendanceAt = $attendanceTime !== null
            ? Carbon::parse(
                $attendanceTime,
                config('app.timezone')
            )
            : now();

        if (!$isOfflineSync && !$event->is_active) {
            throw new AttendanceException(
                'EVENT_NOT_ACTIVE',
                'This event is not currently active.',
                422
            );
        }

        /*
         * Work out WHICH slot and WHICH window (in/out) this submission is
         * for. Newer clients send slot_index + type; older clients omit them
         * and the window is inferred from the timestamp.
         */
        $resolved = $this->slots->resolveOrInfer(
            $event,
            $attendanceAt,
            $slotIndex,
            $type
        );

        /*
         * Verify the phone's actual location.
         */
        $geo = $this->verifyGeofence(
            $event,
            $latitude,
            $longitude,
            $locationAccuracy
        );

        /*
         * Offline synchronization may retry the same UUID.
         */
        if ($attendanceUuid) {
            $existing = Attendance::where(
                'attendance_uuid',
                $attendanceUuid
            )->first();

            if ($existing) {
                return $existing->load('event');
            }
        }

        /*
         * Cheap slot-aware duplicate check before the expensive face work.
         */
        $this->slots->guard(
            $student->student_id,
            $event->event_id,
            $resolved
        );

        /*
         * Extract the face embedding from the final camera frame.
         */
        try {
            $liveEmbedding = $this->extractEmbedding(
                $liveCameraFrame
            );
        } catch (\Throwable $e) {
            throw new AttendanceException(
                'FACE_EXTRACTION_FAILED',
                $e->getMessage(),
                422
            );
        }

        $storedEmbedding = $student->face_embedding;

        if (
            !is_array($storedEmbedding)
            || empty($storedEmbedding)
        ) {
            throw new AttendanceException(
                'REFERENCE_FACE_MISSING',
                'The registered face data is unavailable.',
                422
            );
        }

        /*
         * Compare the live face with the registered face.
         */
        $similarity = BiometricService::cosineSimilarity(
            $storedEmbedding,
            $liveEmbedding
        );

        $threshold = (float) config(
            'face_verification.profile_match_threshold',
            0.50
        );

        if ($similarity < $threshold) {
            throw new AttendanceException(
                'FACE_MISMATCH',
                'The live face does not match the registered student.',
                422,
                [
                    'confidence_score' => round($similarity, 4),
                    'required_score' => $threshold,
                ]
            );
        }

        $status = $resolved['status'] ?? $this->statusFor($event, $attendanceAt);

        /*
         * Slot-aware persistence. The record is identified by
         * (event_date, slot_index, type), so a Time-In never blocks a
         * Time-Out and one slot never blocks another. The transaction
         * re-checks under a lock; the unique index is the final safety net
         * against two requests arriving at the same moment.
         */
        try {
            return DB::transaction(
                function () use (
                    $student,
                    $event,
                    $attendanceUuid,
                    $attendanceAt,
                    $status,
                    $source,
                    $similarity,
                    $latitude,
                    $longitude,
                    $locationAccuracy,
                    $geo,
                    $resolved
                ) {
                    $this->slots->guard(
                        $student->student_id,
                        $event->event_id,
                        $resolved,
                        true
                    );

                    $now = now();

                    return Attendance::create([
                        'attendance_uuid' => $attendanceUuid
                            ?: (string) Str::uuid(),
                        'student_id' => $student->student_id,
                        'event_id' => $event->event_id,
                        'event_date' => $resolved['date'],
                        'slot_index' => $resolved['index'],
                        'type' => $resolved['type'],
                        'logged_at' => $now,
                        'attendance_time' => $attendanceAt,
                        'sync_time' => $now,
                        'status' => $status,
                        'sync_status' => 'synced',
                        'source' => $source,
                        'confidence_score' => round($similarity, 4),
                        'liveness_passed' => true,
                        'liveness_method' => 'insightface_pose_rotation',
                        'latitude' => $latitude,
                        'longitude' => $longitude,
                        'location_accuracy' => $locationAccuracy,
                        'distance_from_event' => $geo['distance'],
                        'location_verified_at' => $now,
                    ]);
                }
            );
        } catch (QueryException $e) {
            // SQLSTATE 23xxx: unique index hit by a concurrent duplicate request.
            if (str_starts_with((string) $e->getCode(), '23')) {
                throw new AttendanceException(
                    'ALREADY_CHECKED_IN',
                    $resolved['type'] === 'out'
                        ? 'You have already checked out for this time slot.'
                        : 'You have already checked in for this time slot.',
                    409
                );
            }

            throw $e;
        }
    }

    /**
     * Extract a face embedding from the submitted image.
     */
    private function extractEmbedding(
        UploadedFile $frame
    ): array {
        $embedding =
            $this->biometrics->profileEmbeddingFromFile(
                $frame
            );

        if (
            !is_array($embedding)
            || count($embedding) < 100
        ) {
            throw new \RuntimeException(
                'Unable to extract a usable face from the camera frame.'
            );
        }

        return $embedding;
    }

    /**
     * Verify event geofence.
     */
    private function verifyGeofence(
        Event $event,
        float $latitude,
        float $longitude,
        ?float $accuracy
    ): array {
        if (!$event->is_geofenced) {
            return [
                'inside' => true,
                'distance' => 0.0,
                'radius' => (float) $event->radius_meters,
            ];
        }

        if (
            $event->latitude === null
            || $event->longitude === null
        ) {
            throw new AttendanceException(
                'EVENT_LOCATION_MISSING',
                'The event does not have a valid geofence location.',
                422
            );
        }

        $maximumAccuracy = (float) config(
            'services.geofence.max_accuracy_meters',
            100
        );

        if (
            $accuracy !== null
            && $accuracy > $maximumAccuracy
        ) {
            throw new AttendanceException(
                'GPS_ACCURACY_TOO_LOW',
                'Your GPS location is not accurate enough.',
                422,
                [
                    'accuracy_meters' => round(
                        $accuracy,
                        2
                    ),
                    'maximum_accuracy_meters' =>
                        $maximumAccuracy,
                ]
            );
        }

        if (
            $event->geofence_type === 'polygon'
            && is_array($event->geofence_polygon)
            && count($event->geofence_polygon) >= 3
        ) {
            if (
                !$event->isWithinGeofence(
                    $latitude,
                    $longitude
                )
            ) {
                throw new AttendanceException(
                    'OUTSIDE_GEOFENCE',
                    'You are outside the allowed attendance area.',
                    422,
                    [
                        'distance_meters' => null,
                        'allowed_radius_meters' =>
                            (int) $event->radius_meters,
                    ]
                );
            }

            return [
                'inside' => true,
                'distance' => 0.0,
                'radius' => (float) $event->radius_meters,
            ];
        }

        $result = $this->geofenceService->check(
            $latitude,
            $longitude,
            (float) $event->latitude,
            (float) $event->longitude,
            (float) $event->radius_meters
        );

        if (!$result['inside']) {
            throw new AttendanceException(
                'OUTSIDE_GEOFENCE',
                'You are outside the allowed attendance area.',
                422,
                [
                    'distance_meters' =>
                        $result['distance'],

                    'allowed_radius_meters' =>
                        $result['radius'],
                ]
            );
        }

        return $result;
    }

    /**
     * Determine present/late status across multiple time slots.
     */
    private function statusFor(
        Event $event,
        CarbonInterface $at
    ): string {
        $event->loadMissing('days');
        $appTz = config('app.timezone');

        foreach ($event->days as $day) {
            $date = Carbon::parse(
                $day->event_date,
                $appTz
            )->format('Y-m-d');

            foreach (($day->slots ?? []) as $slot) {
                if (
                    empty(
                        $slot['time_in_start']
                    )
                ) {
                    continue;
                }

                $start = Carbon::parse(
                    "{$date} {$slot['time_in_start']}",
                    $appTz
                );

                $endTime =
                    $slot['time_in_end']
                    ?? $slot['time_in_start'];

                $end = Carbon::parse(
                    "{$date} {$endTime}",
                    $appTz
                );

                if (
                    $end->lessThanOrEqualTo($start)
                ) {
                    $end->addDay();
                }

                if (
                    $at->betweenIncluded(
                        $start,
                        $end
                    )
                ) {
                    $lateAfter = (int) (
                        $slot['late_after_minutes']
                        ?? 15
                    );

                    return $at->gt(
                        $start->copy()->addMinutes(
                            $lateAfter
                        )
                    )
                        ? 'late'
                        : 'present';
                }
            }
        }

        return 'present';
    }
}