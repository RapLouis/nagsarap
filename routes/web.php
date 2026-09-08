<?php

use App\Http\Controllers\AttendanceController;
use App\Http\Controllers\EventController;
use App\Http\Controllers\FaceVerificationController;
use App\Models\Event;
use App\Models\Student;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Route;
use Illuminate\Support\Facades\Storage;
use Inertia\Inertia;

/*
|--------------------------------------------------------------------------
| Public routes
|--------------------------------------------------------------------------
*/

Route::inertia(
    '/',
    'welcome'
)->name('home');


/*
|--------------------------------------------------------------------------
| Mobile → Web biometric verification bridge
|--------------------------------------------------------------------------
|
| PURPOSE:
|
| Flutter authenticates through Laravel Sanctum.
|
| The existing web biometric verification page uses Laravel's normal
| authenticated web session.
|
| Flutter first asks the protected API for a short-lived signed URL:
|
| /api/v1/register/web-verification-url
|
| Flutter then opens that signed URL inside WebView.
|
| This route:
|
| 1. validates the Laravel signature
| 2. loads the same User + Student
| 3. starts a normal Laravel web session
| 4. redirects to the EXISTING /register/verify-face page
|
| This allows Flutter to reuse the SAME:
|
| - React verification page
| - MediaPipe liveness
| - FaceVerificationController
| - FaceService
| - OpenCV
| - InsightFace
| - database
| - migrations
|
*/

/*
|--------------------------------------------------------------------------
| MOBILE → EXISTING WEB BIOMETRIC VERIFICATION
|--------------------------------------------------------------------------
*/

Route::get(
    '/mobile/register/verify-face/{user}',
    function (
        Request $request,
        User $user
    ) {
        /*
         * Signature validation is handled by:
         *
         * signed:relative
         *
         * DO NOT call hasValidSignature() here because that validates
         * the absolute host by default.
         */

        if ($user->role !== 'student') {
            abort(
                403,
                'Only student accounts can complete biometric verification.'
            );
        }

        $user->load('student');

        $student = $user->student;

        if (!$student) {
            abort(
                403,
                'No student profile is linked to this account.'
            );
        }

        /*
        |--------------------------------------------------------------------------
        | START NORMAL LARAVEL WEB SESSION
        |--------------------------------------------------------------------------
        */

        Auth::login($user);

        $request
            ->session()
            ->regenerate();

        /*
        |--------------------------------------------------------------------------
        | ALREADY VERIFIED
        |--------------------------------------------------------------------------
        */

        if (
            $student->verification_status ===
            'verified'
        ) {
            return redirect()
                ->route('dashboard');
        }

        /*
        |--------------------------------------------------------------------------
        | REUSE EXISTING WORKING WEB PAGE
        |--------------------------------------------------------------------------
        */

        return redirect()
            ->route(
                'register.verify-face'
            );
    }
)
    ->middleware(
        'signed:relative'
    )
    ->name(
        'mobile.register.verify-face.bridge'
    );


/*
|--------------------------------------------------------------------------
| Authenticated routes
|--------------------------------------------------------------------------
|
| IMPORTANT:
|
| Do NOT place register/verify-face behind the "verified" middleware.
|
| A newly registered account may still have:
|
| email_verified_at = NULL
|
| but it still needs to complete biometric verification.
|
*/

Route::middleware(['auth'])->group(function () {

    /*
    |--------------------------------------------------------------------------
    | Registration biometric verification page
    |--------------------------------------------------------------------------
    |
    | Registration flow:
    |
    | WEB:
    |
    | POST /register
    |      ↓
    | Fortify creates Student + User
    |      ↓
    | Fortify logs user in
    |      ↓
    | FortifyServiceProvider redirects here
    |
    |
    | MOBILE:
    |
    | Flutter POST /api/v1/register
    |      ↓
    | SAME CreateNewUser
    |      ↓
    | Sanctum token returned
    |      ↓
    | Flutter requests temporary signed URL
    |      ↓
    | /mobile/register/verify-face/{user}
    |      ↓
    | Laravel web session created
    |      ↓
    | redirected here
    |
    */

    Route::get(
        '/register/verify-face',
        function () {

            $user = Auth::user();

            /*
             * Only student accounts should use biometric registration.
             */

            if (
                !$user ||
                $user->role !== 'student'
            ) {
                return redirect()
                    ->route('dashboard');
            }

            /*
             * Load the linked Student.
             */

            $student = $user
                ->load('student')
                ->student;

            /*
             * This should not normally happen because CreateNewUser
             * creates Student + User in one DB transaction.
             */

            if (!$student) {
                abort(
                    403,
                    'No student profile is linked to this account.'
                );
            }

            /*
             * Student already finished biometric verification.
             *
             * Do not make them repeat liveness verification.
             */

            if (
                $student
                    ->verification_status ===
                'verified'
            ) {
                return redirect()
                    ->route('dashboard');
            }

            /*
             * Generate authorized private photo URL.
             *
             * The actual image stays inside the Laravel private disk.
             */

            $student->face_photo_url =
                $student->face_photo_path
                    ? route(
                        'student.face-photo',
                        [
                            'student' =>
                                $student->student_id,
                        ]
                    )
                    : null;

            /*
             * IMPORTANT:
             *
             * This is your EXISTING web React page.
             *
             * We are intentionally reusing this exact page for Flutter's
             * WebView instead of rewriting MediaPipe liveness in Dart.
             */

            return Inertia::render(
                'auth/verify-face',
                [
                    'student' =>
                        $student,
                ]
            );
        }
    )->name(
        'register.verify-face'
    );


    /*
    |--------------------------------------------------------------------------
    | Submit live biometric verification
    |--------------------------------------------------------------------------
    |
    | SAME endpoint for the working web verification flow.
    |
    | verifyFace() should:
    |
    | 1. receive live camera frame
    | 2. require liveness_passed
    | 3. extract InsightFace embedding
    | 4. compare with registered embedding
    | 5. perform duplicate-face protection
    | 6. update:
    |
    |    verification_status = verified
    |
    | 7. redirect to dashboard
    |
    */

    Route::post(
        '/register/verify-face',
        [
            FaceVerificationController::class,
            'verifyFace',
        ]
    )
        ->middleware(
            'throttle:20,1'
        )
        ->name(
            'register.verify-face.submit'
        );


    /*
    |--------------------------------------------------------------------------
    | Student dashboard
    |--------------------------------------------------------------------------
    */

    Route::get(
        '/dashboard',
        function () {

            $user = Auth::user();

            /*
             * Load Student + attendance relationships.
             */

            $student = $user
                ->load([
                    'student.attendances.event',
                ])
                ->student;

            /*
             * Student accounts MUST have a Student profile.
             */

            if (
                $user->role ===
                    'student' &&
                !$student
            ) {
                abort(
                    403,
                    'No student profile is linked to this account.'
                );
            }

            /*
             * Prevent bypassing biometric registration.
             *
             * Any student who has not reached "verified"
             * goes back to the biometric verification page.
             */

            if (
                $user->role ===
                    'student' &&
                $student &&
                $student
                    ->verification_status !==
                    'verified'
            ) {
                return redirect()
                    ->route(
                        'register.verify-face'
                    );
            }

            /*
             * Private face-photo URL.
             */

            if ($student) {
                $student->face_photo_url =
                    $student->face_photo_path
                        ? route(
                            'student.face-photo',
                            [
                                'student' =>
                                    $student
                                        ->student_id,
                            ]
                        )
                        : null;
            }

            /*
             * Current date.
             */

            $today =
                now()->toDateString();

            /*
             * Events happening today.
             */

            $activeEvents =
                Event::query()
                    ->where(
                        'is_active',
                        true
                    )
                    ->whereDate(
                        'event_date',
                        $today
                    )
                    ->orderBy(
                        'start_time'
                    )
                    ->get();

            /*
             * Upcoming events.
             */

            $upcomingEvents =
                Event::query()
                    ->where(
                        'is_active',
                        true
                    )
                    ->whereDate(
                        'event_date',
                        '>',
                        $today
                    )
                    ->orderBy(
                        'event_date'
                    )
                    ->orderBy(
                        'start_time'
                    )
                    ->limit(10)
                    ->get();

            /*
             * Render student dashboard.
             */

            return Inertia::render(
                'dashboard',
                [
                    'student' =>
                        $student,

                    'activeEvents' =>
                        $activeEvents,

                    'upcomingEvents' =>
                        $upcomingEvents,

                    'totalExpectedEvents' =>
                        Event::query()
                            ->count(),
                ]
            );
        }
    )->name(
        'dashboard'
    );


    /*
    |--------------------------------------------------------------------------
    | Web attendance
    |--------------------------------------------------------------------------
    */

    Route::post(
        '/attendance/check-in',
        [
            AttendanceController::class,
            'markAttendance',
        ]
    )
        ->middleware(
            'throttle:30,1'
        )
        ->name(
            'attendance.check-in'
        );


    /*
    |--------------------------------------------------------------------------
    | Admin / Organizer event management
    |--------------------------------------------------------------------------
    */

    Route::middleware(
        'role:admin,organizer'
    )->group(function () {

        Route::get(
            '/events',
            [
                EventController::class,
                'index',
            ]
        )->name(
            'events.index'
        );

        Route::post(
            '/events',
            [
                EventController::class,
                'store',
            ]
        )->name(
            'events.store'
        );

        Route::put(
            '/events/{event}',
            [
                EventController::class,
                'update',
            ]
        )->name(
            'events.update'
        );

        Route::patch(
            '/events/{event}/toggle',
            [
                EventController::class,
                'toggleActive',
            ]
        )->name(
            'events.toggle'
        );
    });


    /*
    |--------------------------------------------------------------------------
    | Private student face photo
    |--------------------------------------------------------------------------
    |
    | The face photo must NOT be directly available from /storage.
    |
    | Allowed:
    |
    | - student viewing their own face image
    | - administrator
    |
    */

    Route::get(
        '/student/{student:student_id}/face-photo',
        function (
            Student $student
        ) {

            $user =
                Auth::user();

            /*
             * Student owns the image OR user is an admin.
             */

            $isOwner =
                (int) $user->student_id ===
                (int) $student
                    ->student_id;

            $isAdmin =
                method_exists(
                    $user,
                    'isAdmin'
                )
                    ? $user->isAdmin()
                    : $user->role ===
                        'admin';

            abort_unless(
                $isOwner ||
                    $isAdmin,
                403
            );

            if (
                !$student
                    ->face_photo_path
            ) {
                abort(404);
            }

            /*
             * Support both:
             *
             * profile_photos/file.jpg
             *
             * and older values like:
             *
             * /storage/profile_photos/file.jpg
             */

            $relativePath =
                ltrim(
                    str_replace(
                        [
                            '/storage/',
                            'storage/',
                        ],
                        '',
                        $student
                            ->face_photo_path
                    ),
                    '/'
                );

            if (
                !Storage::disk(
                    'private'
                )->exists(
                    $relativePath
                )
            ) {
                abort(404);
            }

            return Storage::disk(
                'private'
            )->response(
                $relativePath
            );
        }
    )->name(
        'student.face-photo'
    );
});


require __DIR__.'/settings.php';