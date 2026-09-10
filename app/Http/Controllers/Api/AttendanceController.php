<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Event;
use App\Services\AttendanceException;
use App\Services\AttendanceService;
use App\Services\FaceService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use RuntimeException;

class AttendanceController extends Controller
{
    /**
     * Existing online check-in.
     * Kept unchanged for compatibility with the existing web system.
     */
    public function checkIn(
        Request $request,
        AttendanceService $attendanceService
    ): JsonResponse {
        return $this->process(
            $request,
            $attendanceService,
            false
        );
    }

    /**
     * Offline synchronization.
     *
     * New Flutter offline records send all five
     * liveness challenge frames.
     *
     * Legacy callers that do not send the five
     * challenge frames continue using the old
     * process() path for compatibility.
     */
    public function sync(
        Request $request,
        AttendanceService $attendanceService,
        FaceService $faceService
    ): JsonResponse {
        $hasSecureMobileFrames =
            $request->hasFile('center_frame') ||
            $request->hasFile('blink_frame') ||
            $request->hasFile('turned_frame') ||
            $request->hasFile('smile_frame') ||
            $request->hasFile('returned_frame');

        if ($hasSecureMobileFrames) {
            return $this->syncSecureMobileAttendance(
                $request,
                $attendanceService,
                $faceService
            );
        }

        /*
         * Preserve the existing Laravel/web
         * offline contract.
         */
        return $this->process(
            $request,
            $attendanceService,
            true
        );
    }

    /**
     * Analyze one attendance liveness frame.
     */
    public function analyzeLivenessFrame(
        Request $request,
        FaceService $faceService
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
            $analysis =
                $faceService->analyzeLivenessFrame(
                    $request->file('frame')
                );
        } catch (RuntimeException $e) {
            return response()->json([
                'success' => false,
                'code' =>
                    'LIVENESS_FRAME_FAILED',
                'message' =>
                    $e->getMessage(),
            ], 422);
        }

        return response()->json([
            'success' => true,
            'code' =>
                'LIVENESS_FRAME_ANALYZED',
            'message' =>
                'Attendance liveness frame analyzed.',
            'data' =>
                $analysis,
        ]);
    }

    /**
     * Secure Flutter online attendance check-in.
     */
    public function mobileCheckIn(
        Request $request,
        AttendanceService $attendanceService,
        FaceService $faceService
    ): JsonResponse {
        $validated =
            $request->validate([
                'event_id' => [
                    'required',
                    'integer',
                    'exists:events,event_id',
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

                'blink_frame' => [
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

                'smile_frame' => [
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
            ]);

        $event =
            Event::findOrFail(
                $validated['event_id']
            );

        /*
         * Never trust Flutter to state that
         * liveness passed.
         */
        try {
            $liveness =
                $faceService->verifyLiveness(
                    $request->file(
                        'center_frame'
                    ),
                    $request->file(
                        'blink_frame'
                    ),
                    $request->file(
                        'turned_frame'
                    ),
                    $request->file(
                        'smile_frame'
                    ),
                    $request->file(
                        'returned_frame'
                    )
                );
        } catch (RuntimeException $e) {
            return response()->json([
                'success' => false,
                'code' =>
                    'LIVENESS_FAILED',
                'message' =>
                    $e->getMessage(),
            ], 422);
        }

        try {
            $attendance =
                $attendanceService->record(
                    user:
                        $request->user(),

                    event:
                        $event,

                    liveCameraFrame:
                        $request->file(
                            'returned_frame'
                        ),

                    latitude:
                        (float)
                        $validated['latitude'],

                    longitude:
                        (float)
                        $validated['longitude'],

                    locationAccuracy:
                        isset(
                            $validated[
                                'location_accuracy'
                            ]
                        )
                            ? (float)
                                $validated[
                                    'location_accuracy'
                                ]
                            : null,

                    livenessPassed:
                        true,

                    source:
                        'mobile_online',

                    isOfflineSync:
                        false
                );
        } catch (AttendanceException $e) {
            return response()->json([
                'success' => false,
                'code' =>
                    $e->errorCode,
                'message' =>
                    $e->getMessage(),
                'data' =>
                    $e->data,
            ], $e->httpStatus);
        } catch (RuntimeException $e) {
            return response()->json([
                'success' => false,
                'code' =>
                    'FACE_VERIFICATION_FAILED',
                'message' =>
                    $e->getMessage(),
            ], 422);
        }

        return response()->json([
            'success' => true,
            'code' =>
                'ATTENDANCE_RECORDED',
            'message' =>
                'Attendance recorded successfully.',

            'data' => [
                'attendance' =>
                    $attendance->load('event'),

                'liveness' =>
                    $liveness,

                'geofence' => [
                    'passed' =>
                        true,

                    'distance_meters' =>
                        $attendance
                            ->distance_from_event,

                    'allowed_radius_meters' =>
                        $attendance
                            ->event
                            ->geofence_radius,
                ],
            ],
        ], 201);
    }

    /**
     * Secure synchronization for a Flutter
     * attendance recorded while offline.
     *
     * The stored five frames are verified now,
     * but Present/Late is calculated from the
     * original attendance_time.
     */
    private function syncSecureMobileAttendance(
        Request $request,
        AttendanceService $attendanceService,
        FaceService $faceService
    ): JsonResponse {
        $validated =
            $request->validate([
                'event_id' => [
                    'required',
                    'integer',
                    'exists:events,event_id',
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

                'blink_frame' => [
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

                'smile_frame' => [
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
            ]);

        $event =
            Event::findOrFail(
                $validated['event_id']
            );

        /*
         * The device does not decide whether
         * liveness succeeded.
         *
         * Laravel/Python performs the same
         * five-frame verification used online.
         */
        try {
            $liveness =
                $faceService->verifyLiveness(
                    $request->file(
                        'center_frame'
                    ),
                    $request->file(
                        'blink_frame'
                    ),
                    $request->file(
                        'turned_frame'
                    ),
                    $request->file(
                        'smile_frame'
                    ),
                    $request->file(
                        'returned_frame'
                    )
                );
        } catch (RuntimeException $e) {
            return response()->json([
                'success' => false,
                'code' =>
                    'LIVENESS_FAILED',
                'message' =>
                    $e->getMessage(),
            ], 422);
        }

        try {
            $attendance =
                $attendanceService->record(
                    user:
                        $request->user(),

                    event:
                        $event,

                    /*
                     * Final centered image is
                     * the live identity frame.
                     */
                    liveCameraFrame:
                        $request->file(
                            'returned_frame'
                        ),

                    latitude:
                        (float)
                        $validated['latitude'],

                    longitude:
                        (float)
                        $validated['longitude'],

                    locationAccuracy:
                        isset(
                            $validated[
                                'location_accuracy'
                            ]
                        )
                            ? (float)
                                $validated[
                                    'location_accuracy'
                                ]
                            : null,

                    livenessPassed:
                        true,

                    attendanceUuid:
                        $validated[
                            'attendance_uuid'
                        ],

                    attendanceTime:
                        $validated[
                            'attendance_time'
                        ],

                    source:
                        'mobile_offline',

                    isOfflineSync:
                        true
                );
        } catch (AttendanceException $e) {
            return response()->json([
                'success' => false,
                'code' =>
                    $e->errorCode,
                'message' =>
                    $e->getMessage(),
                'data' =>
                    $e->data,
            ], $e->httpStatus);
        } catch (RuntimeException $e) {
            return response()->json([
                'success' => false,
                'code' =>
                    'FACE_VERIFICATION_FAILED',
                'message' =>
                    $e->getMessage(),
            ], 422);
        }

        return response()->json([
            'success' => true,

            'code' =>
                'OFFLINE_ATTENDANCE_SYNCED',

            'message' =>
                'Offline attendance verified and synchronized successfully.',

            'data' => [
                'attendance' =>
                    $attendance->load('event'),

                'liveness' =>
                    $liveness,

                'geofence' => [
                    'passed' =>
                        true,

                    'distance_meters' =>
                        $attendance
                            ->distance_from_event,

                    'allowed_radius_meters' =>
                        $attendance
                            ->event
                            ->geofence_radius,
                ],
            ],
        ]);
    }

    /**
     * Student attendance history.
     */
    public function history(
        Request $request
    ): JsonResponse {
        $student =
            $request->user()->student;

        if (!$student) {
            return response()->json([
                'success' => false,
                'code' =>
                    'STUDENT_REQUIRED',
                'message' =>
                    'A student account is required.',
            ], 403);
        }

        $records =
            $student
                ->attendances()
                ->with('event')
                ->orderByDesc(
                    'attendance_time'
                )
                ->paginate(30);

        return response()->json([
            'success' => true,
            'data' =>
                $records,
        ]);
    }

    /**
     * Existing web attendance processor.
     *
     * Kept for compatibility with the
     * existing Laravel/web application.
     */
    private function process(
        Request $request,
        AttendanceService $attendanceService,
        bool $offline
    ): JsonResponse {
        $rules = [
            'event_id' => [
                'required',
                'exists:events,event_id',
            ],

            'attendance_uuid' => [
                $offline
                    ? 'required'
                    : 'nullable',
                'uuid',
            ],

            'attendance_time' => [
                $offline
                    ? 'required'
                    : 'nullable',
                'date',
            ],

            'live_camera_frame' => [
                'required',
                'image',
                'mimes:jpeg,png,jpg',
                'max:5048',
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

            'liveness_passed' => [
                'required',
                'accepted',
            ],
        ];

        $validated =
            $request->validate(
                $rules
            );

        $event =
            Event::findOrFail(
                $validated['event_id']
            );

        try {
            $attendance =
                $attendanceService->record(
                    user:
                        $request->user(),

                    event:
                        $event,

                    liveCameraFrame:
                        $request->file(
                            'live_camera_frame'
                        ),

                    latitude:
                        (float)
                        $validated['latitude'],

                    longitude:
                        (float)
                        $validated['longitude'],

                    locationAccuracy:
                        isset(
                            $validated[
                                'location_accuracy'
                            ]
                        )
                            ? (float)
                                $validated[
                                    'location_accuracy'
                                ]
                            : null,

                    livenessPassed:
                        true,

                    attendanceUuid:
                        $validated[
                            'attendance_uuid'
                        ] ?? null,

                    attendanceTime:
                        $validated[
                            'attendance_time'
                        ] ?? null,

                    source:
                        $offline
                            ? 'mobile_offline'
                            : 'mobile_online',

                    isOfflineSync:
                        $offline
                );
        } catch (AttendanceException $e) {
            return response()->json([
                'success' => false,
                'code' =>
                    $e->errorCode,
                'message' =>
                    $e->getMessage(),
                'data' =>
                    $e->data,
            ], $e->httpStatus);
        }

        return response()->json([
            'success' => true,

            'code' =>
                $offline
                    ? 'OFFLINE_ATTENDANCE_SYNCED'
                    : 'ATTENDANCE_RECORDED',

            'message' =>
                $offline
                    ? 'Offline attendance synchronized successfully.'
                    : 'Attendance recorded successfully.',

            'data' => [
                'attendance' =>
                    $attendance->load('event'),

                'geofence' => [
                    'passed' =>
                        true,

                    'distance_meters' =>
                        $attendance
                            ->distance_from_event,

                    'allowed_radius_meters' =>
                        $attendance
                            ->event
                            ->geofence_radius,
                ],
            ],
        ]);
    }
}