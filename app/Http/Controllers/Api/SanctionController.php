<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class SanctionController extends Controller
{
    public function index(Request $r): JsonResponse
    {
        $user = $r->user();
        $studentId = $user?->student_id;

        if (!$studentId) {
            return response()->json([
                'success' => false,
                'message' => 'Student record not found.',
                'data' => [],
            ], 404);
        }

        $studentCreatedAt = DB::table('students')
            ->where('student_id', $studentId)
            ->value('created_at') ?? $user->created_at;

        $rows = DB::table('sanctions')
            ->leftJoin('events', 'sanctions.event_id', '=', 'events.event_id')
            ->where('sanctions.student_id', $studentId)
            ->where(function ($query) use ($studentCreatedAt) {
                if ($studentCreatedAt) {
                    $query->where('events.created_at', '>=', $studentCreatedAt)
                          ->orWhere('events.start_date', '>=', date('Y-m-d', strtotime($studentCreatedAt)))
                          ->orWhereNull('sanctions.event_id');
                }
            })
            ->select(
                'sanctions.*',
                DB::raw('COALESCE(events.event_date, events.start_date, sanctions.issued_at, sanctions.created_at) as event_date')
            )
            ->orderByRaw('COALESCE(events.event_date, events.start_date, sanctions.issued_at, sanctions.created_at) DESC')
            ->get();

        return response()->json([
            'success' => true,
            'message' => 'Sanctions retrieved successfully.',
            'data' => $rows,
        ]);
    }
}