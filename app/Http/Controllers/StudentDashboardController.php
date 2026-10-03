<?php

namespace App\Http\Controllers;

use App\Models\Event;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Inertia\Inertia;
use Carbon\Carbon;

class StudentDashboardController extends Controller
{
    public function index(Request $request)
    {
        $user = Auth::user();

        if ($user->role === 'admin') {
            return redirect()->route('admin.dashboard');
        }

        $student = $user->load(['student.attendances.event'])->student;

        // Fetch and transform active events for today
        $activeEvents = Event::ongoing()->with('days')->get()->transform(function ($event) {
            $event->schedules = $event->days->map(function ($day) {
                return [
                    'date'  => Carbon::parse($day->event_date)->format('Y-m-d'),
                    'slots' => $day->slots ?? [],
                ];
            });
            return $event;
        });

        return Inertia::render('dashboard', [
            'student' => $student,
            'activeEvents' => $activeEvents,
        ]);
    }
}