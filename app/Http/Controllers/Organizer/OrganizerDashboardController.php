<?php

namespace App\Http\Controllers\Organizer;

use App\Http\Controllers\Controller;
use App\Models\Event;
use App\Models\Attendance;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Carbon\Carbon;

class OrganizerDashboardController extends Controller
{
    public function index(Request $request)
    {
        $userId = $request->user()->id;
        $today = Carbon::today()->toDateString();

        $ongoingEvent = Event::where('user_id', $userId)
            ->where('approval_status', 'approved')
            ->whereDate('event_date', '<=', $today)
            ->where(fn($q) => $q->whereDate('event_end_date', '>=', $today)->orWhereNull('event_end_date'))
            ->first();

        $liveAttendance = [];
        if ($ongoingEvent) {
            $liveAttendance = Attendance::where('event_id', $ongoingEvent->id)
                ->whereDate('created_at', Carbon::today())
                ->with('student')
                ->latest()
                ->take(10)
                ->get();
        }

        $eventAnalytics = Event::where('user_id', $userId)
            ->withCount('attendances')
            ->get(['id', 'title', 'approval_status', 'created_at'])
            ->map(fn($event) => [
                'id' => $event->id,
                'title' => $event->title,
                'status' => $event->approval_status,
                'total_attendance' => $event->attendances_count ?? 0,
            ]);

        return Inertia::render('organizer/Dashboard', [
            'ongoingEvent' => $ongoingEvent,
            'liveAttendance' => $liveAttendance,
            'eventAnalytics' => $eventAnalytics,
        ]);
    }
}