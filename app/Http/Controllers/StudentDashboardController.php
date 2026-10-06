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
        $today = now()->toDateString();

        // 1. Fetch active events for today with structured slot schedules
        $activeEvents = Event::ongoing()->with('days')->get()->transform(function ($event) {
            $event->schedules = $event->days->map(function ($day) {
                return [
                    'date'  => $day->event_date instanceof Carbon ? $day->event_date->format('Y-m-d') : Carbon::parse($day->event_date)->format('Y-m-d'),
                    'slots' => $day->slots ?? [],
                ];
            });
            return $event;
        });

        // 2. Format upcoming events for the "Coming Up" widget
        $upcomingEventsQuery = Event::with('days')->get();

        $upcomingEvents = $upcomingEventsQuery->map(function ($event) use ($today) {
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

        // 3. Format calendar events for the interactive calendar grid & inspector
        $calendarEvents = Event::with('days')
            ->get()
            ->map(function ($event) {
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
    }
}