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
    public function validatePhoto(
        Request $request,
        FaceService $faceService
    ): JsonResponse {
        $request->validate([
            'profile_photo' => [
                'required',
                'file',
                'image',
                'mimes:jpeg,jpg,png',
                'max:5048',
            ],
        ]);

        try {
            $embedding =
                $faceService
                    ->extractEmbeddingFromUploadedFile(
                        $request->file(
                            'profile_photo'
                        )
                    );

            if (
                !is_array($embedding)
                || count($embedding) < 100
            ) {
                return response()->json([
                    'success' => false,
                    'code' =>
                        'INVALID_FACE_EMBEDDING',
                    'message' =>
                        'A usable face could not be extracted from this photo.',
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
            return response()->json([
                'success' => false,
                'code' =>
                    'REFERENCE_PHOTO_INVALID',
                'message' =>
                    $e->getMessage(),
            ], 422);
        }
    }

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
                'token' => $token,
                'token_type' =>
                    'Bearer',
                'user' => $user,
                'student' =>
                    $user->student,
            ],
        ], 201);
    }

    public function verifyFace(
        Request $request,
        FaceService $faceService
    ): JsonResponse {
        $request->validate([
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

            'live_camera_frame' => [
                'required',
                'image',
                'mimes:jpeg,jpg,png',
                'max:5048',
            ],
        ]);

        $user = $request->user();

        if (!$user) {
            return response()->json([
                'success' => false,
                'code' =>
                    'UNAUTHENTICATED',
                'message' =>
                    'Authentication is required.',
            ], 401);
        }

        $student = $user->student;

        if (!$student) {
            return response()->json([
                'success' => false,
                'code' =>
                    'STUDENT_NOT_FOUND',
                'message' =>
                    'Student record not found.',
            ], 404);
        }

        if (
            $student->verification_status
            === 'verified'
        ) {
            return response()->json([
                'success' => true,
                'code' =>
                    'ALREADY_VERIFIED',
                'message' =>
                    'Biometric registration is already complete.',
                'data' => [
                    'student' =>
                        $student,
                    'verification_status' =>
                        'verified',
                ],
            ]);
        }

        /*
        |--------------------------------------------------------------------------
        | SERVER-SIDE MEDIAPIPE LIVENESS
        |--------------------------------------------------------------------------
        */

        try {
            $liveness =
                $faceService
                    ->verifyLiveness(
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
                        ),
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

        /*
        |--------------------------------------------------------------------------
        | LIVE INSIGHTFACE EMBEDDING
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
        | REFERENCE EMBEDDING
        |--------------------------------------------------------------------------
        */

        $referenceEmbedding =
            $student->face_embedding;

        if (
            !is_array($referenceEmbedding)
            || empty($referenceEmbedding)
        ) {
            if (
                !$student->face_photo_path
                || !Storage::disk('private')
                    ->exists(
                        $student
                            ->face_photo_path
                    )
            ) {
                return response()->json([
                    'success' => false,
                    'code' =>
                        'REFERENCE_PHOTO_NOT_FOUND',
                    'message' =>
                        'Reference face data could not be found.',
                ], 422);
            }

            try {
                $referenceEmbedding =
                    $faceService
                        ->extractEmbeddingFromBytes(
                            Storage::disk(
                                'private'
                            )->get(
                                $student
                                    ->face_photo_path
                            )
                        );
            } catch (
                RuntimeException $e
            ) {
                return response()->json([
                    'success' => false,
                    'code' =>
                        'REFERENCE_FACE_FAILED',
                    'message' =>
                        $e->getMessage(),
                ], 422);
            }
        }

        /*
        |--------------------------------------------------------------------------
        | IDENTITY MATCH
        |--------------------------------------------------------------------------
        */

        $similarity =
            $faceService
                ->cosineSimilarity(
                    $liveEmbedding,
                    $referenceEmbedding
                );

        $threshold =
            (float) config(
                'services.face.enrollment_threshold',
                0.50
            );

        if (
            $similarity
            < $threshold
        ) {
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
        | DUPLICATE FACE
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
                !is_array(
                    $otherStudent
                        ->face_embedding
                )
                || empty(
                    $otherStudent
                        ->face_embedding
                )
            ) {
                continue;
            }

            $duplicateSimilarity =
                $faceService
                    ->cosineSimilarity(
                        $liveEmbedding,
                        $otherStudent
                            ->face_embedding
                    );

            if (
                $duplicateSimilarity
                >= $duplicateThreshold
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
        | VERIFIED
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
                'liveness' =>
                    $liveness,
            ],
        ]);
    }
}