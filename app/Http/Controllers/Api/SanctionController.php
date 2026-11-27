<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Sanction;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class SanctionController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $user = $request->user();
        $student = $user?->student;

        if (!$student) {
            return response()->json([
                'success' => false,
                'message' => 'Student record not found.',
                'data' => [],
            ], 404);
        }

        // Safely trigger teammate's SanctionSyncService if available
        if (class_exists(\App\Services\SanctionSyncService::class)) {
            $syncService = app(\App\Services\SanctionSyncService::class);
            if (method_exists($syncService, 'syncForStudent')) {
                rescue(fn () => $syncService->syncForStudent($student));
            }
        }

        $sanctions = Sanction::with('event')
            ->where('student_id', $student->student_id)
            ->orderByDesc('event_date')
            ->orderBy('slot_index')
            ->get();

        $rows = $sanctions->map(function (Sanction $sanction) {
            $checkpointKey = match ($sanction->infraction_type) {
                'missing_morning_time_in' => 'morning_time_in',
                'missing_morning_time_out' => 'morning_time_out',
                'missing_afternoon_time_in' => 'afternoon_time_in',
                'missing_afternoon_time_out' => 'afternoon_time_out',
                default => null,
            };

            $checkpointLabel = match ($sanction->infraction_type) {
                'missing_morning_time_in' => 'Morning Time-In',
                'missing_morning_time_out' => 'Morning Time-Out',
                'missing_afternoon_time_in' => 'Afternoon Time-In',
                'missing_afternoon_time_out' => 'Afternoon Time-Out',
                default => $sanction->slot_label ?? 'Attendance Checkpoint',
            };

            return [
                'sanction_id' => $sanction->sanction_id,
                'student_id' => $sanction->student_id,
                'event_id' => $sanction->event_id,
                'event_title' => $sanction->event?->title ?? $sanction->title,
                'event_date' => $sanction->event_date?->format('Y-m-d'),
                'slot_index' => (int) ($sanction->slot_index ?? 0),
                'slot_label' => $sanction->slot_label,
                'infraction_type' => $sanction->infraction_type,
                'checkpoint_key' => $checkpointKey,
                'checkpoint_label' => $checkpointLabel,
                'fine_amount' => (float) ($sanction->fine_amount ?? 0),
                'title' => $sanction->title,
                'reason' => $sanction->reason,
                'status' => $sanction->status,
                'preferred_mode' => $sanction->preferred_mode,
                'excuse_category' => $sanction->excuse_category,
                'student_notes' => $sanction->student_notes,
                'official_receipt_no' => $sanction->official_receipt_no,
                'comm_service_hours' => $sanction->comm_service_hours !== null
                    ? (float) $sanction->comm_service_hours
                    : null,
                'admin_remarks' => $sanction->admin_remarks,
                'issued_at' => $sanction->issued_at?->toIso8601String(),
                'resolved_at' => $sanction->resolved_at?->toIso8601String(),
                'created_at' => $sanction->created_at?->toIso8601String(),
            ];
        })->values();

        $active = $sanctions->whereIn('status', ['unsettled', 'pending_verification']);

        $fineRatePerLog = 0.0;
        if (
            class_exists(\App\Models\SanctionSetting::class) &&
            method_exists(\App\Models\SanctionSetting::class, 'getFinePerLog')
        ) {
            $fineRatePerLog = (float) \App\Models\SanctionSetting::getFinePerLog();
        }

        return response()->json([
            'success' => true,
            'message' => 'Sanctions retrieved successfully.',
            'data' => $rows,
            'summary' => [
                'unsettled_balance' => (float) $active->sum('fine_amount'),
                'active_count' => $active->count(),
                'is_cleared' => $active->isEmpty(),
                'fine_rate_per_log' => $fineRatePerLog,
            ],
        ]);
    }
}