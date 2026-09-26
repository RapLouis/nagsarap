<?php

use App\Http\Controllers\Admin\AdminDashboardController;
use App\Http\Controllers\Admin\StudentManagementController;
use App\Http\Controllers\AttendanceController;
use App\Http\Controllers\EventController;
use App\Http\Controllers\FaceVerificationController;
use App\Http\Controllers\Admin\AnalyticsController;
use App\Models\Event;
use App\Models\Student;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Route;
use Illuminate\Support\Facades\Storage;
use Inertia\Inertia;

Route::inertia('/', 'welcome')->name('home');

Route::middleware(['auth', 'verified'])->group(function () {

    // =========================================================================
    // DASHBOARD REDIRECT DISPATCHER
    // =========================================================================

    Route::get('/dashboard', function () {
        /** @var \App\Models\User $user */
        $user = Auth::user();

        // Redirect admin users directly to their dedicated dashboard
        if ($user->role === 'admin') {
            return redirect()->route('admin.dashboard');
        }

        $student = $user->load([
            'student.attendances.event'
        ])->student;

        // Redirect unverified students to face verification
        if ($student && $student->verification_status === 'pending_face_verification') {
            return redirect()->route('register.verify-face');
        }

        if ($student) {
            $student->face_photo_url = $student->face_photo_path
                ? route('student.face-photo', [
                    'student' => $student->student_id
                ])
                : null;
        }

        // Active events for student attendance (Filtered by today via ongoing scope)
        $activeEvents = Event::ongoing()->with('days')->get();

        return Inertia::render('dashboard', [
            'student' => $student,
            'activeEvents' => $activeEvents,
        ]);
    })->name('dashboard');


    // =========================================================================
    // ADMIN ROUTES
    // =========================================================================

    Route::middleware(['admin'])
        ->prefix('admin')
        ->as('admin.')
        ->group(function () {

            // -----------------------------------------------------------------
            // ADMIN DASHBOARD
            // -----------------------------------------------------------------

            Route::get(
                '/dashboard',
                [AdminDashboardController::class, 'index']
            )->name('dashboard');


            // -----------------------------------------------------------------
            // STUDENT MANAGEMENT
            // -----------------------------------------------------------------

            // Student list
            Route::get(
                '/students',
                [StudentManagementController::class, 'index']
            )->name('students.index');

            // Update student details
            Route::patch(
                '/students/{student}',
                [StudentManagementController::class, 'update']
            )->name('students.update');

            // Verify student (manual override)
            Route::patch(
                '/students/{student}/verify',
                [StudentManagementController::class, 'verify']
            )->name('students.verify');

            // Reject student (send back to pending face verification)
            Route::patch(
                '/students/{student}/reject',
                [StudentManagementController::class, 'reject']
            )->name('students.reject');

            // Delete student
            Route::delete(
                '/students/{student}',
                [StudentManagementController::class, 'destroy']
            )->name('students.destroy');
            // -----------------------------------------------------------------
            // STUDENT CLEARANCE
            // -----------------------------------------------------------------

            Route::get(
                '/clearance',
                function () {
                    return Inertia::render('admin/Clearance');
                }
            )->name('clearance.index');

            // -----------------------------------------------------------------
            // EVENT MANAGEMENT
            // -----------------------------------------------------------------

            // Event list
            Route::get(
                '/events',
                [EventController::class, 'index']
            )->name('events.index');

            // Create event
            Route::post(
                '/events',
                [EventController::class, 'store']
            )->name('events.store');

            // Update event
            Route::put(
                '/events/{event}',
                [EventController::class, 'update']
            )->name('events.update');

            // Toggle event active/inactive
            Route::patch(
                '/events/{event}/toggle',
                [EventController::class, 'toggleActive']
            )->name('events.toggle');

            // Delete event
            Route::delete(
                '/events/{event}',
                [EventController::class, 'destroy']
            )->name('events.destroy');

            // Update event status
            Route::patch(
                '/events/{event}/status', 
                [EventController::class, 'updateStatus']
            )->name('events.update-status');
            
            // -----------------------------------------------------------------
            // ADMIN ANALYTICS & REPORTS
            // -----------------------------------------------------------------

            // Global System Analytics page
            Route::get(
                '/analytics',
                [AnalyticsController::class, 'index']
            )->name('analytics.index');

            // Per-Event Drill-down analytics view
            Route::get(
                '/analytics/events/{event}',
                [AnalyticsController::class, 'showEvent']
            )->name('analytics.event-show');

        });


    // =========================================================================
    // BIOMETRIC FACE VERIFICATION
    // =========================================================================

    Route::get(
        '/register/verify-face',
        [FaceVerificationController::class, 'show']
    )->middleware('throttle:20,1')
     ->name('register.verify-face');

    Route::post(
        '/register/verify-face',
        [FaceVerificationController::class, 'verifyFace']
    )->middleware('throttle:10,1')
     ->name('register.verify-face.submit');


    // =========================================================================
    // ATTENDANCE
    // =========================================================================

    Route::post(
        '/attendance/check-in',
        [AttendanceController::class, 'markAttendance']
    )->name('attendance.check-in');


    // =========================================================================
    // SECURE PRIVATE STORAGE ACCESS
    // =========================================================================

    Route::get(
        '/student/{student:student_id}/face-photo',
        function (Student $student) {

            if (!$student->face_photo_path) {
                abort(404);
            }

            $relativePath = ltrim(
                str_replace(
                    ['/storage/', 'storage/'],
                    '',
                    $student->face_photo_path
                ),
                '/'
            );

            if (!Storage::disk('private')->exists($relativePath)) {
                abort(404);
            }

            return Storage::disk('private')->response($relativePath);
        }
    )->name('student.face-photo');
});

require __DIR__.'/settings.php';
// Mobile app bridge: opens the same server-side biometric verification flow when needed.
Route::get('/mobile/register/verify-face/{user}', function (\Illuminate\Http\Request $request, \App\Models\User $user) {
    abort_unless($user->role === 'student' && $user->student, 403);
    \Illuminate\Support\Facades\Auth::login($user);
    $request->session()->regenerate();
    return redirect()->route('register.verify-face');
})->middleware('signed:relative')->name('mobile.register.verify-face.bridge');
