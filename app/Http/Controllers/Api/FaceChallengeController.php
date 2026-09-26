<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\FaceChallengeService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class FaceChallengeController extends Controller
{
    public function registration(Request $request, FaceChallengeService $challenges): JsonResponse
    {
        $student = $request->user()?->student;

        if (! $student) {
            return response()->json([
                'success' => false,
                'code' => 'STUDENT_NOT_FOUND',
                'message' => 'Student record not found.',
            ], 404);
        }

        $validated = $request->validate([
            'session_id' => ['required', 'string', 'min:16', 'max:100'],
        ]);

        return response()->json([
            'success' => true,
            'code' => 'LIVENESS_CHALLENGE_ISSUED',
            'message' => 'Liveness challenge issued.',
            'data' => $challenges->issue(
                $student->student_id,
                $validated['session_id'],
                'registration',
            ),
        ]);
    }

    public function attendance(Request $request, FaceChallengeService $challenges): JsonResponse
    {
        $student = $request->user()?->student;

        if (! $student) {
            return response()->json([
                'success' => false,
                'code' => 'STUDENT_NOT_FOUND',
                'message' => 'Student record not found.',
            ], 404);
        }

        $validated = $request->validate([
            'session_id' => ['required', 'string', 'min:16', 'max:100'],
            'event_id' => ['required', 'integer', 'exists:events,event_id'],
        ]);

        return response()->json([
            'success' => true,
            'code' => 'LIVENESS_CHALLENGE_ISSUED',
            'message' => 'Liveness challenge issued.',
            'data' => $challenges->issue(
                $student->student_id,
                $validated['session_id'],
                'attendance',
                (int) $validated['event_id'],
            ),
        ]);
    }
}
