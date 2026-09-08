<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;

class AuthController extends Controller
{
    /**
     * Mobile student login.
     *
     * Flutter sends:
     *
     * {
     *     "student_number": "23-140012",
     *     "password": "Password123!"
     * }
     */
    public function login(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'student_number' => [
                'required',
                'string',
                'max:20',
            ],

            'password' => [
                'required',
                'string',
            ],
        ]);

        $studentNumber = trim(
            $validated['student_number']
        );

        /*
        |--------------------------------------------------------------------------
        | Find the USER through the linked STUDENT
        |--------------------------------------------------------------------------
        |
        | users.student_id -> students.student_id
        |
        | We are NOT authenticating directly against the students table
        | because the password belongs to the users table.
        |
        */

        $user = User::query()
            ->with('student')
            ->whereHas(
                'student',
                function ($query) use ($studentNumber) {
                    $query->where(
                        'student_number',
                        $studentNumber
                    );
                }
            )
            ->first();

        /*
        |--------------------------------------------------------------------------
        | Validate credentials
        |--------------------------------------------------------------------------
        */

        if (
            !$user ||
            !Hash::check(
                $validated['password'],
                $user->password
            )
        ) {
            throw ValidationException::withMessages([
                'student_number' =>
                    'The student number or password is incorrect.',
            ]);
        }

        /*
        |--------------------------------------------------------------------------
        | Student-only mobile authentication
        |--------------------------------------------------------------------------
        */

        if ($user->role !== 'student') {
            return response()->json([
                'success' => false,
                'message' =>
                    'This account cannot use the student mobile application.',
            ], 403);
        }

        /*
        |--------------------------------------------------------------------------
        | Remove old mobile token for this device
        |--------------------------------------------------------------------------
        |
        | This avoids filling personal_access_tokens with duplicate
        | "Flutter Android" tokens every time the student logs in.
        |
        */

        $user->tokens()
            ->where(
                'name',
                'Flutter Android'
            )
            ->delete();

        /*
        |--------------------------------------------------------------------------
        | Create Sanctum token
        |--------------------------------------------------------------------------
        */

        $token = $user
            ->createToken(
                'Flutter Android'
            )
            ->plainTextToken;

        /*
        |--------------------------------------------------------------------------
        | Response
        |--------------------------------------------------------------------------
        |
        | This response matches the Flutter AuthService.
        |
        */

        return response()->json([
            'success' => true,

            'message' =>
                'Login successful.',

            'token' =>
                $token,

            'user' => [
                'id' =>
                    $user->id,

                'student_id' =>
                    $user->student_id,

                'name' =>
                    $user->name,

                'email' =>
                    $user->email,

                'role' =>
                    $user->role,
            ],

            'student' =>
                $user->student,
        ]);
    }

    /**
     * Return the currently authenticated student.
     */
    public function me(Request $request): JsonResponse
    {
        $user = $request
            ->user()
            ->load('student');

        return response()->json([
            'success' => true,

            'data' => [
                'user' => [
                    'id' =>
                        $user->id,

                    'student_id' =>
                        $user->student_id,

                    'name' =>
                        $user->name,

                    'email' =>
                        $user->email,

                    'role' =>
                        $user->role,
                ],

                'student' =>
                    $user->student,
            ],
        ]);
    }

    /**
     * Logout current mobile device.
     */
    public function logout(Request $request): JsonResponse
    {
        $token =
            $request
                ->user()
                ?->currentAccessToken();

        if ($token !== null) {
            $token->delete();
        }

        return response()->json([
            'success' => true,

            'message' =>
                'Logged out successfully.',
        ]);
    }
}