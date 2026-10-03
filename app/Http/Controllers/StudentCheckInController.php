<?php

namespace App\Http\Controllers;

use App\Models\Event;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Inertia\Inertia;
use Carbon\Carbon;

class StudentCheckInController extends Controller
{
    /**
     * Display the dedicated student check-in hub page.
     */
    public function index(Request $request)
    {
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

        // Format the secure private photo URL if it exists
        if ($student) {
            $student->face_photo_url = $student->face_photo_path
                ? route('student.face-photo', [
                    'student' => $student->student_id
                ])
                : null;
        }

        // Fetch ongoing/active events for today and transform schedules for the frontend
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
    }
}