<?php

namespace App\Http\Controllers\Api;

use App\Actions\Fortify\CreateNewUser;
use App\Http\Controllers\Controller;
use App\Models\Student;
use App\Services\FaceService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use RuntimeException;

class RegistrationController extends Controller
{
    /*
    |--------------------------------------------------------------------------
    | VALIDATE REFERENCE PHOTO
    |--------------------------------------------------------------------------
    |
    | Called by Flutter immediately after a student selects a reference
    | photograph.
    |
    | This does NOT create an account.
    |
    | It only verifies that the image is usable by our face system.
    |
    | Flutter
    |    ↓
    | Laravel
    |    ↓
    | FaceService
    |    ↓
    | Python / OpenCV / InsightFace
    |
    */

    public function validatePhoto(
        Request $request,
        FaceService $faceService
    ): JsonResponse {
        /*
        |--------------------------------------------------------------------------
        | VALIDATE FILE
        |--------------------------------------------------------------------------
        */

        $request->validate([
            'profile_photo' => [
                'required',
                'file',
                'image',
                'mimes:jpeg,jpg,png',
                'max:5048',
            ],
        ]);

        /*
        |--------------------------------------------------------------------------
        | RUN REAL FACE VALIDATION
        |--------------------------------------------------------------------------
        */

        try {
            $embedding =
                $faceService
                    ->extractEmbeddingFromUploadedFile(
                        $request->file(
                            'profile_photo'
                        )
                    );

            /*
             * InsightFace embedding should contain
             * substantially more than 100 values.
             */

            if (
                !is_array($embedding) ||
                count($embedding) < 100
            ) {
                return response()->json([
                    'success' => false,

                    'code' =>
                        'INVALID_FACE_EMBEDDING',

                    'message' =>
                        'A usable face could not be extracted from this photo. Please select another photo.',
                ], 422);
            }

            return response()->json([
                'success' => true,

                'code' =>
                    'REFERENCE_PHOTO_VALID',

                'message' =>
                    'Face detected. Photo is ready for registration.',
            ]);
        } catch (RuntimeException $e) {
            /*
             * The Python/FaceService error is passed
             * back to Flutter.
             *
             * Examples may include:
             *
             * - No face detected
             * - Image too blurry
             * - Multiple faces detected
             * - Unable to decode image
             */

            return response()->json([
                'success' => false,

                'code' =>
                    'REFERENCE_PHOTO_INVALID',

                'message' =>
                    $e->getMessage(),
            ], 422);
        }
    }

    /*
    |--------------------------------------------------------------------------
    | REGISTER
    |--------------------------------------------------------------------------
    */

    public function register(
        Request $request,
        CreateNewUser $creator
    ): JsonResponse {
        $user = $creator->create(
            $request->all()
        );

        $token = $user
            ->createToken(
                $request->input(
                    'device_name',
                    'Flutter Device'
                ),
                ['student']
            )
            ->plainTextToken;

        $user->load('student');

        return response()->json([
            'success' => true,

            'code' =>
                'REGISTRATION_CREATED',

            'message' =>
                'Registration created. Complete live face verification.',

            'data' => [
                'token' =>
                    $token,

                'token_type' =>
                    'Bearer',

                'user' =>
                    $user,

                'student' =>
                    $user->student,
            ],
        ], 201);
    }

    /*
    |--------------------------------------------------------------------------
    | VERIFY LIVE REGISTRATION FACE
    |--------------------------------------------------------------------------
    |
    | Stage 14 will call this endpoint after the student completes
    | the live liveness sequence.
    |
    */

    public function verifyFace(
        Request $request,
        FaceService $faceService
    ): JsonResponse {
        $request->validate([
            'live_camera_frame' => [
                'required',
                'image',
                'mimes:jpeg,png,jpg',
                'max:5048',
            ],

            'liveness_passed' => [
                'required',
                'accepted',
            ],
        ]);

        /*
        |--------------------------------------------------------------------------
        | AUTHENTICATED STUDENT
        |--------------------------------------------------------------------------
        */

        $user =
            $request->user();

        if (!$user) {
            return response()->json([
                'success' => false,

                'code' =>
                    'UNAUTHENTICATED',

                'message' =>
                    'Authentication is required.',
            ], 401);
        }

        $student =
            $user->student;

        if (!$student) {
            return response()->json([
                'success' => false,

                'code' =>
                    'STUDENT_NOT_FOUND',

                'message' =>
                    'Student record not found.',
            ], 404);
        }

        /*
        |--------------------------------------------------------------------------
        | LIVE FACE EMBEDDING
        |--------------------------------------------------------------------------
        */

        try {
            $liveEmbedding =
                $faceService
                    ->extractEmbeddingFromUploadedFile(
                        $request->file(
                            'live_camera_frame'
                        )
                    );
        } catch (RuntimeException $e) {
            return response()->json([
                'success' => false,

                'code' =>
                    'FACE_SCAN_FAILED',

                'message' =>
                    $e->getMessage(),
            ], 422);
        }

        /*
        |--------------------------------------------------------------------------
        | REFERENCE PHOTO
        |--------------------------------------------------------------------------
        */

        if (!$student->face_photo_path) {
            return response()->json([
                'success' => false,

                'code' =>
                    'REFERENCE_PHOTO_NOT_FOUND',

                'message' =>
                    'Reference photo is missing.',
            ], 422);
        }

        if (
            !Storage::disk('private')
                ->exists(
                    $student->face_photo_path
                )
        ) {
            return response()->json([
                'success' => false,

                'code' =>
                    'REFERENCE_PHOTO_NOT_FOUND',

                'message' =>
                    'The registered reference photo could not be found.',
            ], 422);
        }

        /*
        |--------------------------------------------------------------------------
        | COMPARE LIVE FACE WITH REFERENCE PHOTO
        |--------------------------------------------------------------------------
        */

        try {
            $referenceBytes =
                Storage::disk('private')
                    ->get(
                        $student->face_photo_path
                    );

            $referenceEmbedding =
                $faceService
                    ->extractEmbeddingFromBytes(
                        $referenceBytes
                    );

            $similarity =
                $faceService
                    ->cosineSimilarity(
                        $liveEmbedding,
                        $referenceEmbedding
                    );
        } catch (RuntimeException $e) {
            return response()->json([
                'success' => false,

                'code' =>
                    'REFERENCE_FACE_FAILED',

                'message' =>
                    $e->getMessage(),
            ], 422);
        }

        /*
        |--------------------------------------------------------------------------
        | MATCH THRESHOLD
        |--------------------------------------------------------------------------
        */

        $threshold = (float) config(
            'services.face.enrollment_threshold',
            0.50
        );

        if ($similarity < $threshold) {
            return response()->json([
                'success' => false,

                'code' =>
                    'FACE_MISMATCH',

                'message' =>
                    'Live face does not match the uploaded profile photo.',

                'data' => [
                    'similarity' =>
                        round(
                            $similarity,
                            4
                        ),

                    'required_similarity' =>
                        $threshold,
                ],
            ], 422);
        }

        /*
        |--------------------------------------------------------------------------
        | DUPLICATE FACE CHECK
        |--------------------------------------------------------------------------
        */

        $duplicateThreshold =
            (float) config(
                'services.face.match_threshold',
                0.60
            );

        $otherStudents =
            Student::query()
                ->whereNotNull(
                    'face_embedding'
                )
                ->where(
                    'student_id',
                    '!=',
                    $student->student_id
                )
                ->get();

        foreach (
            $otherStudents
            as $otherStudent
        ) {
            if (
                empty(
                    $otherStudent->face_embedding
                )
            ) {
                continue;
            }

            try {
                $duplicateSimilarity =
                    $faceService
                        ->cosineSimilarity(
                            $liveEmbedding,
                            $otherStudent
                                ->face_embedding
                        );
            } catch (RuntimeException) {
                continue;
            }

            if (
                $duplicateSimilarity >=
                $duplicateThreshold
            ) {
                return response()->json([
                    'success' => false,

                    'code' =>
                        'DUPLICATE_FACE',

                    'message' =>
                        'This face is already registered to another student.',
                ], 409);
            }
        }

        /*
        |--------------------------------------------------------------------------
        | BIOMETRICS VERIFIED
        |--------------------------------------------------------------------------
        */

        $student->update([
            'face_embedding' =>
                $liveEmbedding,

            'verification_status' =>
                'verified',
        ]);

        return response()->json([
            'success' => true,

            'code' =>
                'BIOMETRICS_VERIFIED',

            'message' =>
                'Biometric verification completed successfully.',

            'data' => [
                'student' =>
                    $student->fresh(),

                'similarity' =>
                    round(
                        $similarity,
                        4
                    ),

                'verification_status' =>
                    'verified',
            ],
        ]);
    }
}