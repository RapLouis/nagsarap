<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\URL;
use Throwable;

class WebVerificationController extends Controller
{
    public function createUrl(
        Request $request
    ): JsonResponse {
        try {
            $user = $request->user();

            if (!$user) {
                return response()->json([
                    'success' => false,
                    'code' => 'UNAUTHENTICATED',
                    'message' => 'Authentication is required.',
                ], 401);
            }

            if ($user->role !== 'student') {
                return response()->json([
                    'success' => false,
                    'code' => 'STUDENT_REQUIRED',
                    'message' =>
                        'Only student accounts can complete biometric verification.',
                ], 403);
            }

            $user->load('student');

            $student = $user->student;

            if (!$student) {
                return response()->json([
                    'success' => false,
                    'code' => 'STUDENT_NOT_FOUND',
                    'message' =>
                        'No student profile is linked to this account.',
                ], 404);
            }

            if (
                $student->verification_status ===
                'verified'
            ) {
                return response()->json([
                    'success' => true,
                    'code' => 'ALREADY_VERIFIED',
                    'message' =>
                        'Biometric verification is already complete.',
                    'data' => [
                        'verified' => true,
                        'url' => null,
                    ],
                ]);
            }

            /*
            |--------------------------------------------------------------------------
            | IMPORTANT
            |--------------------------------------------------------------------------
            |
            | Generate a RELATIVE signed URL.
            |
            | This prevents 10.0.2.2 / localhost host differences from
            | invalidating the Laravel signature.
            |
            */

            $signedUrl =
                URL::temporarySignedRoute(
                    'mobile.register.verify-face.bridge',
                    now()->addMinutes(10),
                    [
                        'user' => $user->getKey(),
                    ],
                    absolute: false
                );

            return response()->json([
                'success' => true,
                'code' =>
                    'WEB_VERIFY_URL_CREATED',
                'message' =>
                    'Biometric verification URL created.',
                'data' => [
                    'verified' => false,
                    'url' => $signedUrl,
                ],
            ]);
        } catch (Throwable $e) {
            report($e);

            return response()->json([
                'success' => false,
                'code' =>
                    'WEB_VERIFY_URL_FAILED',
                'message' =>
                    config('app.debug')
                        ? $e->getMessage()
                        : 'Unable to create biometric verification URL.',
            ], 500);
        }
    }
}