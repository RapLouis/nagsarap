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

        // Format upcoming events for the "Coming Up" widget
        $upcomingEvents = Event::upcoming()
            ->with('days')
            ->get()
            ->map(function ($event) use ($today) {
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
            })
            ->filter()
            ->values();

        // Format calendar events for the interactive calendar grid & inspector
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