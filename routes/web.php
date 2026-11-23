<?php

use App\Http\Controllers\Admin\AdminDashboardController;
use App\Http\Controllers\Admin\AdminEventApprovalController;
use App\Http\Controllers\Admin\AdminSanctionController;
use App\Http\Controllers\Admin\AnalyticsController;
use App\Http\Controllers\Admin\ClearanceController;
use App\Http\Controllers\Admin\OrganizerManagementController;
use App\Http\Controllers\Admin\StudentManagementController;
use App\Http\Controllers\AttendanceController;
use App\Http\Controllers\EventController;
use App\Http\Controllers\FaceVerificationController;
use App\Http\Controllers\FirstTimePasswordController;
use App\Http\Controllers\StudentDashboardController;
use App\Http\Controllers\StudentNotificationController;
use App\Http\Controllers\StudentSanctionController;
use App\Http\Controllers\StudentRegistrationController;
use App\Http\Controllers\Organizer\KioskController;
use App\Http\Controllers\Organizer\OrganizerDashboardController;
use App\Http\Controllers\Organizer\OrganizerEventController;
use App\Http\Middleware\EnsurePasswordIsChanged;
use App\Http\Middleware\EnsureUserIsOrganizer;
use App\Models\Student;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Route;
use Illuminate\Support\Facades\Storage;
use Inertia\Inertia;
use Carbon\Carbon;

/*
|--------------------------------------------------------------------------
| Web Routes
|--------------------------------------------------------------------------
*/

Route::inertia('/', 'welcome')->name('home');

// =========================================================================
// GUEST REGISTRATION ROUTES
// =========================================================================

Route::middleware('guest')->group(function () {
    Route::get('/register', [StudentRegistrationController::class, 'showRegistrationForm'])->name('register');
    Route::post('/register', [StudentRegistrationController::class, 'register']);
});


// =========================================================================
// MANDATORY FIRST-TIME PASSWORD CHANGE ROUTES
// =========================================================================

Route::middleware(['auth'])->group(function () {
    Route::get('/first-time-change-password', [FirstTimePasswordController::class, 'show'])
        ->name('password.first-change');

    Route::post('/first-time-change-password', [FirstTimePasswordController::class, 'update'])
        ->name('password.first-change.update');
});


// =========================================================================
// AUTHENTICATED, VERIFIED & PASSWORD-CHECKED USER ROUTES
// =========================================================================

Route::middleware(['auth', 'verified', EnsurePasswordIsChanged::class])->group(function () {

    // -------------------------------------------------------------------------
    // MAIN STUDENT DASHBOARD & CALENDAR
    // -------------------------------------------------------------------------
    Route::get('/dashboard', [StudentDashboardController::class, 'index'])->name('dashboard');


    // -------------------------------------------------------------------------
    // STUDENT SANCTIONS & ATTENDANCE HISTORY
    // -------------------------------------------------------------------------
    Route::get('/sanctions', [StudentSanctionController::class, 'index'])
        ->name('sanctions.index');
    Route::post('/sanctions/declare', [StudentSanctionController::class, 'declareResolution'])
        ->name('sanctions.declare');
    Route::post('/sanctions/{sanction}/excuse', [StudentSanctionController::class, 'submitExcuse'])
        ->name('sanctions.excuse');
    Route::get('/sanctions/{sanction}/proof', [StudentSanctionController::class, 'viewProof'])
        ->name('sanctions.proof');


    // -------------------------------------------------------------------------
    // STUDENT CHECK-IN HUB
    // -------------------------------------------------------------------------
    Route::get('/check-in', function () {
        /** @var \App\Models\User $user */
        $user = Auth::user();

        if ($user->role === 'organizer') {
            return redirect()->route('organizer.dashboard');
        }
        if ($user->role === 'admin') {
            return redirect()->route('admin.dashboard');
        }

        $student = $user->load(['student.attendances.event'])->student;

        if ($student) {
            $student->face_photo_url = $student->face_photo_path
                ? route('student.face-photo', ['student' => $student->student_id])
                : null;
        }

        $studentSectionStr = $student ? trim("{$student->degree} - {$student->year_section}") : '';

        $studentEventScope = function ($query) use ($studentSectionStr) {
            $query->where('target_scope', 'all')
                  ->orWhere(function ($sub) use ($studentSectionStr) {
                      $sub->where('target_scope', 'section')
                          ->whereJsonContains('target_sections', $studentSectionStr);
                  });
        };

        $activeEvents = \App\Models\Event::ongoing()
            ->where($studentEventScope)
            ->with('days')
            ->get()
            ->transform(function ($event) {
                $event->schedules = $event->days->map(function ($day) {
                    return [
                        'date'  => Carbon::parse($day->event_date)->format('Y-m-d'),
                        'slots' => $day->slots ?? [],
                    ];
                });
                return $event;
            });

        return Inertia::render('CheckIn', [
            'student'      => $student,
            'activeEvents' => $activeEvents,
        ]);
    })->name('check-in');


    // -------------------------------------------------------------------------
    // ADMIN PANEL ROUTES
    // -------------------------------------------------------------------------
    Route::middleware(['admin'])
        ->prefix('admin')
        ->as('admin.')
        ->group(function () {
            Route::get('/dashboard', [AdminDashboardController::class, 'index'])->name('dashboard');
            Route::get('/students', [StudentManagementController::class, 'index'])->name('students.index');
            Route::patch('/students/{student}', [StudentManagementController::class, 'update'])->name('students.update');
            Route::patch('/students/{student}/verify', [StudentManagementController::class, 'verify'])->name('students.verify');
            Route::patch('/students/{student}/reject', [StudentManagementController::class, 'reject'])->name('students.reject');
            Route::delete('/students/{student}', [StudentManagementController::class, 'destroy'])->name('students.destroy');

            // Direct Organizer Account Provisioning Routes
            Route::get('/organizers', [OrganizerManagementController::class, 'index'])->name('organizers.index');
            Route::post('/organizers', [OrganizerManagementController::class, 'store'])->name('organizers.store');
            Route::put('/organizers/{user}/reset-password', [OrganizerManagementController::class, 'resetPassword'])->name('organizers.reset-password');
            Route::delete('/organizers/{user}', [OrganizerManagementController::class, 'destroy'])->name('organizers.destroy');

            Route::get('/clearance', [ClearanceController::class, 'index'])->name('clearance.index');
            Route::patch('/clearance/{clearance}/status', [ClearanceController::class, 'updateStatus'])->name('clearance.update');

            // Admin Sanctions Management & Verification
            Route::get('/sanctions', [AdminSanctionController::class, 'index'])->name('sanctions.index');
            Route::post('/sanctions/fine-rate', [AdminSanctionController::class, 'updateFineRate'])->name('sanctions.update-rate');
            Route::post('/sanctions/verify-cash', [AdminSanctionController::class, 'verifyCash'])->name('sanctions.verify-cash');
            Route::post('/sanctions/verify-service', [AdminSanctionController::class, 'verifyService'])->name('sanctions.verify-service');
            Route::post('/sanctions/{sanction}/review-excuse', [AdminSanctionController::class, 'reviewExcuse'])->name('sanctions.review-excuse');

            Route::get('/events', [EventController::class, 'index'])->name('events.index');
            Route::post('/events', [EventController::class, 'store'])->name('events.store');
            Route::put('/events/{event}', [EventController::class, 'update'])->name('events.update');
            Route::patch('/events/{event}/toggle', [EventController::class, 'toggleActive'])->name('events.toggle');
            Route::delete('/events/{event}', [EventController::class, 'destroy'])->name('events.destroy');
            Route::patch('/events/{event}/status', [EventController::class, 'updateStatus'])->name('events.update-status');

            // Admin Event Approvals
            Route::post('/events/{event}/approve', [AdminEventApprovalController::class, 'approve'])->name('events.approve');
            Route::post('/events/{event}/reject', [AdminEventApprovalController::class, 'reject'])->name('events.reject');
            
            Route::get('/analytics', [AnalyticsController::class, 'index'])->name('analytics.index');
            Route::get('/analytics/events/{event}', [AnalyticsController::class, 'showEvent'])->name('analytics.event-show');
        });


    // -------------------------------------------------------------------------
    // ORGANIZER WORKSPACE ROUTES
    // -------------------------------------------------------------------------
    Route::middleware([EnsureUserIsOrganizer::class])
        ->prefix('organizer')
        ->as('organizer.')
        ->group(function () {
            Route::get('/dashboard', [OrganizerDashboardController::class, 'index'])->name('dashboard');
            Route::get('/events', [OrganizerEventController::class, 'index'])->name('events.index');
            Route::post('/events', [OrganizerEventController::class, 'store'])->name('events.store');
            Route::put('/events/{event}', [OrganizerEventController::class, 'update'])->name('events.update');
            Route::delete('/events/{event}', [OrganizerEventController::class, 'destroy'])->name('events.destroy');

            Route::get('/kiosk', [KioskController::class, 'index'])->name('kiosk.index');
            Route::get('/kiosk/challenge', [KioskController::class, 'challenge'])->name('kiosk.challenge');
            Route::post('/kiosk/verify', [KioskController::class, 'verifyFace'])->name('kiosk.verify');
            Route::get('/students/search', [KioskController::class, 'searchStudents'])->name('students.search');
            Route::post('/kiosk/manual-override', [KioskController::class, 'manualOverride'])->name('kiosk.manual-override');
        });


    // -------------------------------------------------------------------------
    // BIOMETRIC FACE VERIFICATION & ATTENDANCE
    // -------------------------------------------------------------------------
    Route::get('/register/verify-face', [FaceVerificationController::class, 'show'])
        ->middleware('throttle:20,1')
        ->name('register.verify-face');

    Route::post('/register/verify-face', [FaceVerificationController::class, 'verifyFace'])
        ->middleware('throttle:10,1')
        ->name('register.verify-face.submit');

    Route::post('/attendance/check-in', [AttendanceController::class, 'markAttendance'])->name('attendance.check-in');

    Route::get('/student/{student:student_id}/face-photo', function (Student $student) {
        if (!$student->face_photo_path) abort(404);
        $relativePath = ltrim(str_replace(['/storage/', 'storage/'], '', $student->face_photo_path), '/');
        if (!Storage::disk('private')->exists($relativePath)) abort(404);
        return Storage::disk('private')->response($relativePath);
    })->name('student.face-photo');

    Route::get('/notifications', [StudentNotificationController::class, 'index'])->name('notifications.index');
    Route::patch('/notifications/{notification}/read', [StudentNotificationController::class, 'markAsRead'])->name('notifications.read');
    Route::patch('/notifications/read-all', [StudentNotificationController::class, 'markAllAsRead'])->name('notifications.read-all');

    Route::get('/calendar', [App\Http\Controllers\StudentDashboardController::class, 'calendar'])
    ->name('calendar');

    
});

require __DIR__.'/settings.php';

// Mobile Bridge Route
Route::get('/mobile/register/verify-face/{user}', function (Request $request, \App\Models\User $user) {
    abort_unless($user->role === 'student' && $user->student, 403);
    Auth::login($user);
    $request->session()->regenerate();
    return redirect()->route('register.verify-face');
})->middleware('signed:relative')->name('mobile.register.verify-face.bridge');