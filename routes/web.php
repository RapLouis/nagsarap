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
use Carbon\Carbon;

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

        $today = now()->toDateString();

        // Active events for today
        $activeEvents = Event::ongoing()->with('days')->get()->transform(function ($event) {
            $event->schedules = $event->days->map(function ($day) {
                return [
                    'date'  => Carbon::parse($day->event_date)->format('Y-m-d'),
                    'slots' => $day->slots ?? [],
                ];
            });
            return $event;
        });

        // Upcoming events for the Coming Up widget
        $upcomingEvents = Event::with('days')->get()->map(function ($event) use ($today) {
            $futureDays = $event->days->filter(fn($day) => Carbon::parse($day->event_date)->toDateString() > $today);
            if ($futureDays->isEmpty()) {
                return null;
            }

            $sortedDays = $futureDays->sortBy('event_date');
            $nextDate = Carbon::parse($sortedDays->first()->event_date)->toDateString();
            $startDate = Carbon::parse($event->days->min('event_date'))->toDateString();
            $endDate = Carbon::parse($event->days->max('event_date'))->toDateString();

            return [
                'event_id' => $event->event_id,
                'title' => $event->title,
                'location' => $event->location,
                'next_date' => $nextDate,
                'start_date' => $startDate,
                'end_date' => $endDate,
                'day_count' => $event->days->count(),
            ];
        })->filter()->values();

        // Calendar events for grid and inspector
        $calendarEvents = Event::with('days')->get()->map(function ($event) {
            $schedules = $event->days->isNotEmpty() 
                ? $event->days->map(function ($day) {
                    return [
                        'date' => $day->event_date instanceof Carbon ? $day->event_date->format('Y-m-d') : Carbon::parse($day->event_date)->format('Y-m-d'),
                        'slots' => $day->slots ?? [],
                    ];
                })
                : [
                    [
                        'date' => $event->event_date instanceof Carbon ? $event->event_date->format('Y-m-d') : Carbon::parse($event->event_date)->format('Y-m-d'),
                        'slots' => [],
                    ]
                ];

            return [
                'event_id' => $event->event_id,
                'title' => $event->title,
                'location' => $event->location,
                'schedules' => $schedules->toArray(),
            ];
        });

        $totalExpectedEvents = Event::count();

        return Inertia::render('dashboard', [
            'student' => $student,
            'activeEvents' => $activeEvents,
            'calendarEvents' => $calendarEvents,
            'upcomingEvents' => $upcomingEvents,
            'totalExpectedEvents' => $totalExpectedEvents,
            'today' => $today,
        ]);
    })->name('dashboard');


    // =========================================================================
    // STUDENT CHECK-IN HUB
    // =========================================================================

    Route::get('/check-in', function () {
        /** @var \App\Models\User $user */
        $user = Auth::user();

        $student = $user->load([
            'student.attendances.event'
        ])->student;

        if ($student) {
            $student->face_photo_url = $student->face_photo_path
                ? route('student.face-photo', ['student' => $student->student_id])
                : null;
        }

        $activeEvents = Event::ongoing()->with('days')->get()->transform(function ($event) {
            $event->schedules = $event->days->map(function ($day) {
                return [
                    'date'  => Carbon::parse($day->event_date)->format('Y-m-d'),
                    'slots' => $day->slots ?? [],
                ];
            });
            return $event;
        });

        return Inertia::render('CheckIn', [
            'student' => $student,
            'activeEvents' => $activeEvents,
        ]);
    })->name('check-in');


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

            Route::get(
                '/students',
                [StudentManagementController::class, 'index']
            )->name('students.index');

            Route::patch(
                '/students/{student}',
                [StudentManagementController::class, 'update']
            )->name('students.update');

            Route::patch(
                '/students/{student}/verify',
                [StudentManagementController::class, 'verify']
            )->name('students.verify');

            Route::patch(
                '/students/{student}/reject',
                [StudentManagementController::class, 'reject']
            )->name('students.reject');

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

            Route::get(
                '/events',
                [EventController::class, 'index']
            )->name('events.index');

            Route::post(
                '/events',
                [EventController::class, 'store']
            )->name('events.store');

            Route::put(
                '/events/{event}',
                [EventController::class, 'update']
            )->name('events.update');

            Route::patch(
                '/events/{event}/toggle',
                [EventController::class, 'toggleActive']
            )->name('events.toggle');

            Route::delete(
                '/events/{event}',
                [EventController::class, 'destroy']
            )->name('events.destroy');

            Route::patch(
                '/events/{event}/status', 
                [EventController::class, 'updateStatus']
            )->name('events.update-status');
            
            // -----------------------------------------------------------------
            // ADMIN ANALYTICS & REPORTS
            // -----------------------------------------------------------------

            Route::get(
                '/analytics',
                [AnalyticsController::class, 'index']
            )->name('analytics.index');

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

Route::get('/mobile/register/verify-face/{user}', function (\Illuminate\Http\Request $request, \App\Models\User $user) {
    abort_unless($user->role === 'student' && $user->student, 403);
    \Illuminate\Support\Facades\Auth::login($user);
    $request->session()->regenerate();
    return redirect()->route('register.verify-face');
})->middleware('signed:relative')->name('mobile.register.verify-face.bridge');