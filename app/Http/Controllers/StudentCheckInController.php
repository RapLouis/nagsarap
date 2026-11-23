<?php

namespace App\Http\Controllers;

use App\Exceptions\AttendanceException;
use App\Models\Attendance;
use App\Models\Event;
use App\Models\StudentNotification;
use App\Services\AttendanceService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;

class StudentCheckinController extends Controller
{
    public function __construct(
        private readonly AttendanceService $attendanceService
    ) {}

    /**
     * Handle student check-in submission supporting four independent checkpoints.
     */
    public function store(Request $request)
    {
        $user = Auth::user();

        // 1. Validate incoming check-in payload
        $validated = $request->validate([
            'event_id'          => ['required', 'integer', 'exists:events,event_id'],
            'slot_index'        => ['required', 'integer', 'min:0', 'max:99'],
            'type'              => ['required', 'in:in,out'],
            'checkpoint_key'    => ['nullable', 'string', 'max:50', 'in:morning_time_in,morning_time_out,afternoon_time_in,afternoon_time_out'],
            'live_camera_frame' => ['required', 'image', 'mimes:jpeg,png,jpg', 'max:5048'],
            'latitude'          => ['required', 'numeric', 'between:-90,90'],
            'longitude'         => ['required', 'numeric', 'between:-180,180'],
            'location_accuracy' => ['nullable', 'numeric'],
            'liveness_passed'   => ['required', 'boolean'],
            'attendance_uuid'   => ['nullable', 'string'],
            'attendance_time'   => ['nullable', 'date'],
        ]);

        $event = Event::findOrFail($validated['event_id']);

        try {
            // 2. Delegate recording to AttendanceService which now handles 4-checkpoint uniqueness & slot resolution
            $attendance = $this->attendanceService->record(
                user: $user,
                event: $event,
                liveCameraFrame: $request->file('live_camera_frame'),
                latitude: (float) $validated['latitude'],
                longitude: (float) $validated['longitude'],
                locationAccuracy: $validated['location_accuracy'] ?? null,
                livenessPassed: (bool) $validated['liveness_passed'],
                attendanceUuid: $validated['attendance_uuid'] ?? null,
                attendanceTime: $validated['attendance_time'] ?? null,
                source: 'mobile_online',
                isOfflineSync: false,
                slotIndex: (int) $validated['slot_index'],
                type: $validated['type']
            );

            // Optionally, pass checkpoint_key if explicitly passed in request
            if (!empty($validated['checkpoint_key']) && $attendance->checkpoint_key !== $validated['checkpoint_key']) {
                $attendance->checkpoint_key = $validated['checkpoint_key'];
                $attendance->save();
            }

            // 3. Create student notification
            $checkpointLabel = match ($attendance->checkpoint_key) {
                Attendance::MORNING_TIME_IN => 'Morning Time-In',
                Attendance::MORNING_TIME_OUT => 'Morning Time-Out',
                Attendance::AFTERNOON_TIME_IN => 'Afternoon Time-In',
                Attendance::AFTERNOON_TIME_OUT => 'Afternoon Time-Out',
                default => 'Attendance Checkpoint',
            };

            StudentNotification::create([
                'student_id' => $user->student->student_id,
                'title'      => "{$checkpointLabel} Recorded",
                'message'    => "You have successfully logged your {$checkpointLabel} for {$event->title}.",
                'type'       => 'attendance',
                'is_read'    => false,
            ]);

            return response()->json([
                'success' => true,
                'message' => "{$checkpointLabel} recorded successfully.",
                'data'    => $attendance,
            ], 201);

        } catch (AttendanceException $e) {
            return response()->json([
                'success' => false,
                'error_code' => $e->getErrorCode(),
                'message'    => $e->getMessage(),
                'details'    => $e->getDetails(),
            ], $e->getStatusCode());
        }
    }
}