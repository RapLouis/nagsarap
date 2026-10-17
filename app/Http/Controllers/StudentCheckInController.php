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
        $today = now()->toDateString(); // 2026-10-06

        // Fetch active events for today
        $activeEvents = Event::ongoing()->with('days')->get()->transform(function ($event) {
            $event->schedules = $event->days->map(function ($day) {
                return [
                    'date'  => Carbon::parse($day->event_date)->format('Y-m-d'),
                    'slots' => $day->slots ?? [],
                ];
            });
            return $event;
        });

        // Fetch upcoming events for dates strictly after today
        $upcomingEventsQuery = Event::where('approval_status', 'approved')
            ->where(function($q) use ($today) {
                $q->whereDate('event_date', '>', $today)
                  ->orWhereHas('days', function($sub) use ($today) {
                      $sub->whereDate('event_date', '>', $today);
                  });
            })
            ->with('days')
            ->get();

        $upcomingEvents = $upcomingEventsQuery->map(function ($event) {
            $firstDay = $event->days->sortBy('event_date')->first();
            $nextDate = $firstDay ? Carbon::parse($firstDay->event_date)->toDateString() : ($event->event_date ? Carbon::parse($event->event_date)->toDateString() : '');

            return [
                'event_id' => $event->event_id,
                'title' => $event->title,
                'location' => $event->location,
                'next_date' => $nextDate,
                'start_date' => $event->event_date ? Carbon::parse($event->event_date)->toDateString() : $nextDate,
                'end_date' => $event->event_end_date ? Carbon::parse($event->event_end_date)->toDateString() : $nextDate,
                'day_count' => $event->days->count() ?: 1,
            ];
        })->filter(fn($e) => !empty($e['next_date']) && $e['next_date'] > $today)->values();

        // Format calendar events
        $calendarEvents = Event::where('approval_status', 'approved')
            ->with('days')
            ->get()
            ->map(function ($event) {
                return [
                    'event_id' => $event->event_id,
                    'title' => $event->title,
                    'location' => $event->location,
                    'schedules' => $event->days->map(function ($day) {
                        return [
                            'date' => Carbon::parse($day->event_date)->format('Y-m-d'),
                            'slots' => $day->slots ?? [],
                        ];
                    })->toArray(),
                ];
            });

        $totalExpectedEvents = Event::where('approval_status', 'approved')->count();

        return Inertia::render('dashboard', [
            'student' => $student,
            'activeEvents' => $activeEvents,
            'calendarEvents' => $calendarEvents,
            'upcomingEvents' => $upcomingEvents,
            'totalExpectedEvents' => $totalExpectedEvents,
            'today' => $today,
        ]);
    }
}