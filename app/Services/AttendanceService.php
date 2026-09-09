<?php

namespace App\Services;

use App\Models\Attendance;
use App\Models\Event;
use App\Models\User;
use Carbon\Carbon;
use Carbon\CarbonInterface;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class AttendanceService
{
    public function __construct(
        private readonly GeofenceService $geofenceService,
        private readonly FaceService $faceService,
    ) {
    }

    /**
     * Record an attendance.
     *
     * This method is shared by the existing Laravel attendance flow
     * and the Flutter mobile attendance flow.
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
    ): Attendance {
        /*
        |--------------------------------------------------------------------------
        | 1. REQUIRE STUDENT ACCOUNT
        |--------------------------------------------------------------------------
        */

        $student = $user->student;

        if (!$student) {
            throw new AttendanceException(
                'STUDENT_REQUIRED',
                'A student account is required to record attendance.',
                403
            );
        }

        /*
        |--------------------------------------------------------------------------
        | 2. REQUIRE COMPLETED BIOMETRIC REGISTRATION
        |--------------------------------------------------------------------------
        |
        | This does NOT mean registration is performed again.
        |
        | It simply makes sure the logged-in student already has a verified
        | reference face stored in their credentials.
        |
        */

        if (
            $student->verification_status !== 'verified' ||
            empty($student->face_embedding)
        ) {
            throw new AttendanceException(
                'BIOMETRIC_NOT_VERIFIED',
                'Complete biometric registration before recording attendance.',
                403
            );
        }

        /*
        |--------------------------------------------------------------------------
        | 3. REQUIRE SERVER-VERIFIED LIVENESS
        |--------------------------------------------------------------------------
        */

        if (!$livenessPassed) {
            throw new AttendanceException(
                'LIVENESS_REQUIRED',
                'Liveness verification is required.',
                422
            );
        }

        /*
        |--------------------------------------------------------------------------
        | 4. ATTENDANCE TIME
        |--------------------------------------------------------------------------
        |
        | Online:
        |     current server time
        |
        | Offline:
        |     original verified attendance_time
        |
        | CarbonInterface is used throughout this service so both Carbon and
        | CarbonImmutable are supported.
        |
        */

        $attendanceAt = $attendanceTime !== null
            ? Carbon::parse($attendanceTime)
            : now();

        /*
        |--------------------------------------------------------------------------
        | 5. EVENT WINDOW
        |--------------------------------------------------------------------------
        */

        $this->assertEventWindow(
            $event,
            $attendanceAt,
            $isOfflineSync
        );

        /*
        |--------------------------------------------------------------------------
        | 6. GEOFENCE
        |--------------------------------------------------------------------------
        */

        $geofence = $this->verifyGeofence(
            event: $event,
            latitude: $latitude,
            longitude: $longitude,
            locationAccuracy: $locationAccuracy
        );

        /*
        |--------------------------------------------------------------------------
        | 7. OFFLINE UUID IDEMPOTENCY
        |--------------------------------------------------------------------------
        |
        | If an offline attendance was already synchronized, return the
        | existing record rather than inserting another one.
        |
        */

        if ($attendanceUuid !== null) {
            $existingByUuid = Attendance::query()
                ->where(
                    'attendance_uuid',
                    $attendanceUuid
                )
                ->first();

            if ($existingByUuid) {
                return $existingByUuid;
            }
        }

        /*
        |--------------------------------------------------------------------------
        | 8. DUPLICATE STUDENT/EVENT ATTENDANCE
        |--------------------------------------------------------------------------
        */

        $existingAttendance = Attendance::query()
            ->where(
                'student_id',
                $student->student_id
            )
            ->where(
                'event_id',
                $event->event_id
            )
            ->first();

        if ($existingAttendance) {
            throw new AttendanceException(
                'ALREADY_CHECKED_IN',
                'Attendance has already been recorded for this event.',
                409,
                [
                    'attendance' =>
                        $existingAttendance,
                ]
            );
        }

        /*
        |--------------------------------------------------------------------------
        | 9. EXTRACT LIVE FACE EMBEDDING
        |--------------------------------------------------------------------------
        |
        | Laravel
        |     ↓
        | FaceService
        |     ↓
        | Python service
        |     ↓
        | OpenCV + InsightFace
        |
        */

        try {
            $liveEmbedding =
                $this->faceService
                    ->extractEmbeddingFromUploadedFile(
                        $liveCameraFrame
                    );
        } catch (\RuntimeException $e) {
            throw new AttendanceException(
                'FACE_EXTRACTION_FAILED',
                $e->getMessage(),
                422
            );
        }

        /*
        |--------------------------------------------------------------------------
        | 10. READ REGISTERED FACE EMBEDDING
        |--------------------------------------------------------------------------
        */

        $storedEmbedding =
            $student->face_embedding;

        if (is_string($storedEmbedding)) {
            $decoded = json_decode(
                $storedEmbedding,
                true
            );

            if (is_array($decoded)) {
                $storedEmbedding = $decoded;
            }
        }

        if (
            !is_array($storedEmbedding) ||
            empty($storedEmbedding)
        ) {
            throw new AttendanceException(
                'REFERENCE_FACE_MISSING',
                'The registered face data is unavailable.',
                422
            );
        }

        /*
        |--------------------------------------------------------------------------
        | 11. FACE RECOGNITION
        |--------------------------------------------------------------------------
        |
        | Compare:
        |
        | LIVE ATTENDANCE FACE
        |           vs
        | REGISTERED STUDENT FACE
        |
        | This is the proxy-attendance protection.
        |
        */

        $similarity =
            $this->faceService
                ->cosineSimilarity(
                    $storedEmbedding,
                    $liveEmbedding
                );

        $matchThreshold = (float) config(
            'services.face.match_threshold',
            0.60
        );

        if ($similarity < $matchThreshold) {
            throw new AttendanceException(
                'FACE_MISMATCH',
                'The live face does not match the registered student.',
                422,
                [
                    'confidence_score' =>
                        round($similarity, 4),

                    'required_score' =>
                        $matchThreshold,
                ]
            );
        }

        /*
        |--------------------------------------------------------------------------
        | 12. PRESENT / LATE
        |--------------------------------------------------------------------------
        */

        $status = $this->statusFor(
            $event,
            $attendanceAt
        );

        /*
        |--------------------------------------------------------------------------
        | 13. CREATE ATTENDANCE
        |--------------------------------------------------------------------------
        */

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
                $geofence,
                $isOfflineSync
            ) {
                /*
                 * Recheck inside the transaction to reduce the chance of
                 * duplicate records from simultaneous requests.
                 */
                $duplicate = Attendance::query()
                    ->where(
                        'student_id',
                        $student->student_id
                    )
                    ->where(
                        'event_id',
                        $event->event_id
                    )
                    ->lockForUpdate()
                    ->first();

                if ($duplicate) {
                    throw new AttendanceException(
                        'ALREADY_CHECKED_IN',
                        'Attendance has already been recorded for this event.',
                        409,
                        [
                            'attendance' =>
                                $duplicate,
                        ]
                    );
                }

                $now = now();

                return Attendance::create([
                    'attendance_uuid' =>
                        $attendanceUuid ??
                        (string) Str::uuid(),

                    'student_id' =>
                        $student->student_id,

                    'event_id' =>
                        $event->event_id,

                    'logged_at' =>
                        $attendanceAt,

                    /*
                     * Critical offline rule:
                     *
                     * This is the actual verified attendance time,
                     * NOT the later synchronization time.
                     */
                    'attendance_time' =>
                        $attendanceAt,

                    'sync_time' =>
                        $now,

                    'status' =>
                        $status,

                    'sync_status' =>
                        $isOfflineSync
                            ? 'synced'
                            : 'synced',

                    'source' =>
                        $source,

                    'confidence_score' =>
                        round($similarity, 4),

                    'liveness_passed' =>
                        true,

                    'liveness_method' =>
                        'mediapipe_blink_turn_smile',

                    'latitude' =>
                        $latitude,

                    'longitude' =>
                        $longitude,

                    'location_accuracy' =>
                        $locationAccuracy,

                    'distance_from_event' =>
                        $geofence['distance'],

                    'location_verified_at' =>
                        $now,
                ]);
            }
        );
    }

    /**
     * Verify that the student is physically inside the event geofence.
     */
    private function verifyGeofence(
        Event $event,
        float $latitude,
        float $longitude,
        ?float $locationAccuracy
    ): array {
        /*
        |--------------------------------------------------------------------------
        | GEOFENCE DISABLED
        |--------------------------------------------------------------------------
        */

        if (!$event->geofence_enabled) {
            return [
                'inside' => true,
                'distance' => 0.0,
                'radius' =>
                    (float) (
                        $event->geofence_radius ??
                        0
                    ),
            ];
        }

        /*
        |--------------------------------------------------------------------------
        | EVENT LOCATION REQUIRED
        |--------------------------------------------------------------------------
        */

        if (
            $event->latitude === null ||
            $event->longitude === null
        ) {
            throw new AttendanceException(
                'EVENT_LOCATION_MISSING',
                'The event does not have a valid geofence location.',
                422
            );
        }

        /*
        |--------------------------------------------------------------------------
        | GPS ACCURACY
        |--------------------------------------------------------------------------
        */

        $maxAccuracy = (float) config(
            'services.geofence.max_accuracy_meters',
            100
        );

        if (
            $locationAccuracy !== null &&
            $locationAccuracy > $maxAccuracy
        ) {
            throw new AttendanceException(
                'GPS_ACCURACY_TOO_LOW',
                'Your GPS location is not accurate enough. Move to an open area and try again.',
                422,
                [
                    'accuracy_meters' =>
                        round(
                            $locationAccuracy,
                            2
                        ),

                    'maximum_accuracy_meters' =>
                        $maxAccuracy,
                ]
            );
        }

        $radius = (float) (
            $event->geofence_radius ??
            0
        );

        if ($radius <= 0) {
            throw new AttendanceException(
                'INVALID_GEOFENCE_RADIUS',
                'The event geofence radius is invalid.',
                422
            );
        }

        /*
        |--------------------------------------------------------------------------
        | HAVERSINE DISTANCE
        |--------------------------------------------------------------------------
        */

        $result = $this->geofenceService->check(
            $latitude,
            $longitude,
            (float) $event->latitude,
            (float) $event->longitude,
            $radius
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
     * Validate that the attendance timestamp falls inside the event window.
     *
     * CarbonInterface is IMPORTANT here.
     *
     * Laravel may provide either:
     * - Carbon\Carbon
     * - Carbon\CarbonImmutable
     *
     * Both implement CarbonInterface.
     */
    private function assertEventWindow(
        Event $event,
        CarbonInterface $attendanceAt,
        bool $isOfflineSync
    ): void {
        /*
        |--------------------------------------------------------------------------
        | ACTIVE EVENT
        |--------------------------------------------------------------------------
        |
        | Online attendance must use an active event.
        |
        | An offline record may synchronize later after the event has already
        | been marked inactive, because its original attendance_time is what
        | determines validity.
        |
        */

        if (
            !$isOfflineSync &&
            !$event->is_active
        ) {
            throw new AttendanceException(
                'EVENT_NOT_ACTIVE',
                'This event is not currently active.',
                422
            );
        }

        /*
        |--------------------------------------------------------------------------
        | BUILD EVENT START/END
        |--------------------------------------------------------------------------
        */

        $eventDate =
            $event->event_date instanceof CarbonInterface
                ? $event->event_date->format('Y-m-d')
                : Carbon::parse(
                    $event->event_date
                )->format('Y-m-d');

        $startTime =
            $this->normalizeTime(
                $event->start_time
            );

        $endTime =
            $this->normalizeTime(
                $event->end_time
            );

        $start = Carbon::parse(
            $eventDate . ' ' . $startTime,
            config('app.timezone')
        );

        $end = Carbon::parse(
            $eventDate . ' ' . $endTime,
            config('app.timezone')
        );

        /*
         * Support an event that intentionally crosses midnight.
         *
         * Example:
         *
         * 11:00 PM -> 1:00 AM
         */
        if (
            $end->lessThanOrEqualTo($start)
        ) {
            $end->addDay();
        }

        /*
        |--------------------------------------------------------------------------
        | BEFORE START
        |--------------------------------------------------------------------------
        */

        if (
            $attendanceAt->lessThan($start)
        ) {
            throw new AttendanceException(
                'EVENT_NOT_STARTED',
                'Attendance is not open yet.',
                422,
                [
                    'event_start' =>
                        $start->toIso8601String(),

                    'attendance_time' =>
                        $attendanceAt
                            ->toIso8601String(),
                ]
            );
        }

        /*
        |--------------------------------------------------------------------------
        | AFTER END
        |--------------------------------------------------------------------------
        */

        if (
            $attendanceAt->greaterThan($end)
        ) {
            throw new AttendanceException(
                'EVENT_ENDED',
                'The attendance period for this event has already ended.',
                422,
                [
                    'event_end' =>
                        $end->toIso8601String(),

                    'attendance_time' =>
                        $attendanceAt
                            ->toIso8601String(),
                ]
            );
        }
    }

    /**
     * Determine Present or Late using attendance_time.
     *
     * sync_time is intentionally NOT used.
     */
    private function statusFor(
        Event $event,
        CarbonInterface $attendanceAt
    ): string {
        $eventDate =
            $event->event_date instanceof CarbonInterface
                ? $event->event_date->format('Y-m-d')
                : Carbon::parse(
                    $event->event_date
                )->format('Y-m-d');

        $startTime =
            $this->normalizeTime(
                $event->start_time
            );

        $start = Carbon::parse(
            $eventDate . ' ' . $startTime,
            config('app.timezone')
        );

        $lateAfterMinutes =
            (int) (
                $event->late_after_minutes ??
                15
            );

        $lateAt =
            $start
                ->copy()
                ->addMinutes(
                    $lateAfterMinutes
                );

        return $attendanceAt
                ->greaterThan($lateAt)
            ? 'late'
            : 'present';
    }

    /**
     * Normalize event time regardless of whether Laravel gives us:
     *
     * - string
     * - Carbon
     * - CarbonImmutable
     * - DateTimeInterface
     */
    private function normalizeTime(
        mixed $value
    ): string {
        if ($value instanceof CarbonInterface) {
            return $value->format('H:i:s');
        }

        if ($value instanceof \DateTimeInterface) {
            return $value->format('H:i:s');
        }

        return Carbon::parse(
            (string) $value
        )->format('H:i:s');
    }
}