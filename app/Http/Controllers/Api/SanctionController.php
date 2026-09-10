<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class SanctionController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $user = $request->user();

        if (!$user) {
            return response()->json([
                'success' => false,
                'message' => 'Unauthenticated.',
                'data' => [],
            ], 401);
        }

        if (!$user->student_id) {
            return response()->json([
                'success' => false,
                'message' => 'No student profile is linked to this account.',
                'data' => [],
            ], 403);
        }

        $sanctions = DB::table('sanctions')
            ->where(
                'student_id',
                $user->student_id
            )
            ->orderByRaw(
                'COALESCE(issued_at, created_at) DESC'
            )
            ->get();

        return response()->json([
            'success' => true,
            'message' => 'Sanctions retrieved successfully.',
            'data' => $sanctions,
        ]);
    }
}