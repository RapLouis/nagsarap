<?php

namespace App\Http\Controllers\Organizer;

use App\Http\Controllers\Controller;
use App\Models\Event;
use App\Models\Student;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Carbon\Carbon;

class OrganizerEventController extends Controller
{
    public function index(Request $request)
    {
        $userId = $request->user()->id;
        $search = $request->input('search');
        $tab = $request->input('tab', 'ongoing');
        $today = Carbon::today()->toDateString();

        $baseQuery = Event::where('user_id', $userId);

        $counts = [
            'ongoing' => (clone $baseQuery)->where('approval_status', 'approved')->whereDate('event_date', $today)->count(),
            'upcoming' => (clone $baseQuery)->where('approval_status', 'approved')->whereDate('event_date', '>', $today)->count(),
            'completed' => (clone $baseQuery)->where('approval_status', 'approved')->where(fn($q) => $q->whereDate('event_end_date', '<', $today)->orWhere(fn($sub) => $sub->whereNull('event_end_date')->whereDate('event_date', '<', $today)))->count(),
            'pending' => (clone $baseQuery)->where('approval_status', 'pending')->count(),
            'declined' => (clone $baseQuery)->where('approval_status', 'declined')->count(),
        ];

        // Eager load days relation so time windows are available to the table
        $query = Event::where('user_id', $userId)->with('days');

        if ($search) {
            $query->where(fn($q) => $q->where('title', 'like', "%{$search}%")->orWhere('location', 'like', "%{$search}%"));
        }

        switch ($tab) {
            case 'ongoing':
                $query->where('approval_status', 'approved')
                      ->whereDate('event_date', $today);
                break;
            case 'upcoming':
                $query->where('approval_status', 'approved')->whereDate('event_date', '>', $today);
                break;
            case 'completed':
                $query->where('approval_status', 'approved')
                      ->where(fn($q) => $q->whereDate('event_end_date', '<', $today)->orWhere(fn($sub) => $sub->whereNull('event_end_date')->whereDate('event_date', '<', $today)));
                break;
            case 'pending':
                $query->where('approval_status', 'pending');
                break;
            case 'declined':
                $query->where('approval_status', 'declined');
                break;
        }

        $events = $query->latest('event_date')->paginate(10)->withQueryString();

        $events->getCollection()->transform(function ($event) {
            $event->event_id = $event->id;
            // Map event days and slots to the schedules payload expected by frontend table cells
            $event->schedules = $event->days->map(function ($day) {
                return [
                    'date' => $day->event_date instanceof Carbon ? $day->event_date->format('Y-m-d') : $day->event_date,
                    'slots' => $day->slots ?? [],
                ];
            });
            return $event;
        });

        $availableSections = Student::select('degree', 'year_section')
            ->distinct()
            ->get()
            ->map(fn($s) => trim("{$s->degree} - {$s->year_section}"))
            ->filter()
            ->unique()
            ->values();

        $venues = Event::where('user_id', $userId)
            ->whereNotNull('location')
            ->select('location', 'latitude', 'longitude', 'radius_meters')
            ->distinct()
            ->take(5)
            ->get();

        return Inertia::render('organizer/Events', [
            'events' => $events,
            'counts' => $counts,
            'venues' => $venues,
            'availableSections' => $availableSections,
            'filters' => ['search' => $search, 'tab' => $tab],
        ]);
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'title' => 'required|string|max:255',
            'description' => 'nullable|string',
            'location' => 'nullable|string',
            'is_geofenced' => 'boolean',
            'geofence_type' => 'in:radius,polygon',
            'latitude' => 'nullable|numeric',
            'longitude' => 'nullable|numeric',
            'radius_meters' => 'integer',
            'geofence_polygon' => 'nullable|array',
            'target_scope' => 'in:all,section',
            'target_sections' => 'nullable|array',
            'event_date' => 'required|date',
            'event_end_date' => 'nullable|date|after_or_equal:event_date',
            'schedules' => 'nullable|array',
            'is_active' => 'boolean',
        ]);

        $validated['user_id'] = $request->user()->id;
        $validated['approval_status'] = 'pending';
        $validated['status'] = 'pending';

        $schedules = $validated['schedules'] ?? [];
        unset($validated['schedules']);

        $event = Event::create($validated);

        // Store schedule days & slots into event_days relation table
        if (!empty($schedules)) {
            foreach ($schedules as $sched) {
                $event->days()->create([
                    'event_date' => $sched['date'] ?? $validated['event_date'],
                    'slots' => $sched['slots'] ?? [],
                ]);
            }
        }

        return redirect()->back()->with('success', 'Event submitted for admin approval.');
    }

    public function update(Request $request, Event $event)
    {
        if ($event->user_id !== $request->user()->id) {
            abort(403, 'Unauthorized action.');
        }

        $validated = $request->validate([
            'title' => 'required|string|max:255',
            'description' => 'nullable|string',
            'location' => 'nullable|string',
            'is_geofenced' => 'boolean',
            'geofence_type' => 'in:radius,polygon',
            'latitude' => 'nullable|numeric',
            'longitude' => 'nullable|numeric',
            'radius_meters' => 'integer',
            'geofence_polygon' => 'nullable|array',
            'target_scope' => 'in:all,section',
            'target_sections' => 'nullable|array',
            'event_date' => 'required|date',
            'event_end_date' => 'nullable|date|after_or_equal:event_date',
            'schedules' => 'nullable|array',
            'is_active' => 'boolean',
        ]);

        $validated['approval_status'] = 'pending';
        
        $schedules = $validated['schedules'] ?? [];
        unset($validated['schedules']);

        $event->update($validated);

        if (!empty($schedules)) {
            $event->days()->delete();
            foreach ($schedules as $sched) {
                $event->days()->create([
                    'event_date' => $sched['date'] ?? $validated['event_date'],
                    'slots' => $sched['slots'] ?? [],
                ]);
            }
        }

        return redirect()->back()->with('success', 'Event updated and resubmitted for admin approval.');
    }

    public function destroy(Request $request, Event $event)
    {
        if ($event->user_id !== $request->user()->id) {
            abort(403, 'Unauthorized action.');
        }

        $event->days()->delete();
        $event->delete();
        return redirect()->back()->with('success', 'Event deleted successfully.');
    }
}