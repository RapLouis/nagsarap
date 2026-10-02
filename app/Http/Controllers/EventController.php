<?php

namespace App\Http\Controllers;

use App\Models\Event;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Inertia\Inertia;
use Inertia\Response;
use Carbon\Carbon;

class EventController extends Controller
{
    public function index(Request $request): Response
    {
        $search    = $request->input('search');
        $activeTab = $request->input('tab', 'ongoing');

        // Eager-load the 'days' child relationship so Inertia gets the daily schedules
        $query = Event::with('days')
            ->when($search, function ($q) use ($search) {
                $q->where(function ($sub) use ($search) {
                    $sub->where('title', 'like', "%{$search}%")
                        ->orWhere('location', 'like', "%{$search}%")
                        ->orWhere('description', 'like', "%{$search}%");
                });
            });

        $eventsQuery = clone $query;

        switch ($activeTab) {
            case 'ongoing':
                $eventsQuery->ongoing();    
                break;
            case 'upcoming':
                $eventsQuery->upcoming();
                break;
            case 'completed':
                $eventsQuery->completed();
                break;
            case 'pending':
                $eventsQuery->pending();
                break;
            case 'declined':
                $eventsQuery->declined();
                break;
            default:
                $eventsQuery->ongoing();
                break;
        }

        $events = $eventsQuery->orderBy('created_at', 'desc')
                            ->paginate(10)
                            ->withQueryString();

        // Transform the paginated collection to dynamically include 'schedules' 
        // derived from the 'days' relationship for the frontend table view.
        $events->getCollection()->transform(function ($event) {
            $event->schedules = $event->days->map(function ($day) {
                return [
                    'date'  => $day->event_date,
                    'slots' => $day->slots ?? [],
                ];
            });

            return $event;
        });

        $counts = [
            'ongoing'   => Event::ongoing()->count(),
            'upcoming'  => Event::upcoming()->count(),
            'completed' => Event::completed()->count(),
            'pending'   => Event::pending()->count(),
            'declined'  => Event::declined()->count(),
        ];

        return Inertia::render('admin/Events', [
            'events'  => $events,
            'counts'  => $counts,
            'filters' => [
                'search' => $search ?? '',
                'tab'    => $activeTab,
            ],
        ]);
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'title'                              => ['required', 'string', 'max:150'],
            'description'                        => ['nullable', 'string'],
            'event_date'                         => ['required', 'date'],
            'event_end_date'                     => ['nullable', 'date', 'after_or_equal:event_date'],
            'schedules'                          => ['required', 'array', 'min:1'],
            'schedules.*.date'                   => ['required', 'date'],
            'schedules.*.slots'                  => ['required', 'array', 'min:1'],
            'schedules.*.slots.*.time_in_start'  => ['required'],
            'schedules.*.slots.*.time_in_end'    => ['nullable'],
            'schedules.*.slots.*.time_out_start' => ['nullable'],
            'schedules.*.slots.*.time_out_end'   => ['nullable'],
            'location'                           => ['nullable', 'string', 'max:100'],
            'is_geofenced'                       => ['boolean'],
            'geofence_type'                      => ['nullable', Rule::in(['radius', 'polygon'])],
            'latitude'                           => ['nullable', 'required_if:is_geofenced,true', 'numeric', 'between:-90,90'],
            'longitude'                          => ['nullable', 'required_if:is_geofenced,true', 'numeric', 'between:-180,180'],
            'radius_meters'                      => ['nullable', 'integer', 'min:10', 'max:5000'],
            'geofence_polygon'                   => ['nullable', 'required_if:geofence_type,polygon', 'array', 'min:3'],
            'approval_status'                    => ['nullable', Rule::in(['approved', 'pending', 'declined'])],
            'is_active'                          => ['boolean'],
        ]);

        $isGeofenced  = $request->boolean('is_geofenced', false);
        $geofenceType = $validated['geofence_type'] ?? 'radius';
        $user = $request->user();
        $isAdmin = $user && (($user->is_admin ?? false) || in_array($user->role ?? '', ['admin', 'super_admin']));

        // Loop through each schedule date and create a separate standalone event row
        foreach ($validated['schedules'] as $index => $schedule) {
            $dayNumber = $index + 1;
            $totalDays = count($validated['schedules']);

            // Parse and format the date safely to Y-m-d
            $scheduleDate = Carbon::parse($schedule['date'])->format('Y-m-d');

            // Suffix title with Day count if it's a multi-day event
            $eventTitle = $totalDays > 1 
                ? "{$validated['title']} (Day {$dayNumber} - {$scheduleDate})" 
                : $validated['title'];

            $event = Event::create([
                'title'            => $eventTitle,
                'description'      => $validated['description'] ?? null,
                'event_date'       => $scheduleDate,
                'event_end_date'   => $scheduleDate,
                'location'         => $validated['location'] ?? null,
                'is_geofenced'     => $isGeofenced,
                'geofence_type'    => $isGeofenced ? $geofenceType : 'radius',
                'latitude'         => $isGeofenced ? ($validated['latitude'] ?? null) : null,
                'longitude'        => $isGeofenced ? ($validated['longitude'] ?? null) : null,
                'radius_meters'    => $isGeofenced ? ($validated['radius_meters'] ?? 100) : 100,
                'geofence_polygon' => ($isGeofenced && $geofenceType === 'polygon') ? $validated['geofence_polygon'] : null,
                'approval_status'  => $isAdmin ? 'approved' : 'pending',
                'is_active'        => $request->boolean('is_active', true),
            ]);

            // Save the slots specifically for this daily event row using the formatted date
            $event->days()->create([
                'event_date' => $scheduleDate,
                'slots'      => $schedule['slots'],
            ]);
        }

        return back()->with('message', 'Multi-day events successfully created as separate daily records!');
    }

    public function update(Request $request, Event $event)
    {
        $validated = $request->validate([
            'title'                              => ['required', 'string', 'max:150'],
            'description'                        => ['nullable', 'string'],
            'event_date'                         => ['required', 'date'],
            'event_end_date'                     => ['nullable', 'date', 'after_or_equal:event_date'],
            'schedules'                          => ['required', 'array', 'min:1'],
            'schedules.*.date'                   => ['required', 'date'],
            'schedules.*.slots'                  => ['required', 'array', 'min:1'],
            'schedules.*.slots.*.time_in_start'  => ['required'],
            'schedules.*.slots.*.time_in_end'    => ['nullable'],
            'schedules.*.slots.*.time_out_start' => ['nullable'],
            'schedules.*.slots.*.time_out_end'   => ['nullable'],
            'location'                           => ['nullable', 'string', 'max:100'],
            'is_geofenced'                       => ['boolean'],
            'geofence_type'                      => ['nullable', Rule::in(['radius', 'polygon'])],
            'latitude'                           => ['nullable', 'required_if:is_geofenced,true', 'numeric', 'between:-90,90'],
            'longitude'                          => ['nullable', 'required_if:is_geofenced,true', 'numeric', 'between:-180,180'],
            'radius_meters'                      => ['nullable', 'integer', 'min:10', 'max:5000'],
            'geofence_polygon'                   => ['nullable', 'required_if:geofence_type,polygon', 'array', 'min:3'],
            'approval_status'                    => ['required', Rule::in(['approved', 'pending', 'declined'])],
            'is_active'                          => ['boolean'],
        ]);

        $isGeofenced  = $request->boolean('is_geofenced', false);
        $geofenceType = $validated['geofence_type'] ?? 'radius';

        $event->update([
            'title'            => $validated['title'],
            'description'      => $validated['description'] ?? null,
            'event_date'       => Carbon::parse($validated['event_date'])->format('Y-m-d'),
            'event_end_date'   => isset($validated['event_end_date']) ? Carbon::parse($validated['event_end_date'])->format('Y-m-d') : null,
            'location'         => $validated['location'] ?? null,
            'is_geofenced'     => $isGeofenced,
            'geofence_type'    => $isGeofenced ? $geofenceType : 'radius',
            'latitude'         => $isGeofenced ? ($validated['latitude'] ?? $event->latitude) : null,
            'longitude'        => $isGeofenced ? ($validated['longitude'] ?? $event->longitude) : null,
            'radius_meters'    => $isGeofenced ? ($validated['radius_meters'] ?? 100) : 100,
            'geofence_polygon' => ($isGeofenced && $geofenceType === 'polygon') ? $validated['geofence_polygon'] : null,
            'approval_status'  => $validated['approval_status'],
            'is_active'        => $request->boolean('is_active', true),
        ]);

        $event->days()->delete();

        foreach ($validated['schedules'] as $schedule) {
            $scheduleDate = Carbon::parse($schedule['date'])->format('Y-m-d');

            $event->days()->create([
                'event_date' => $scheduleDate,
                'slots'      => $schedule['slots'],
            ]);
        }

        return back()->with('message', 'Event updated successfully!');
    }

    public function updateStatus(Request $request, Event $event)
    {
        $validated = $request->validate([
            'approval_status' => ['required', Rule::in(['approved', 'pending', 'declined'])],
        ]);

        $event->update(['approval_status' => $validated['approval_status']]);

        return back()->with('message', "Event status updated to {$validated['approval_status']}.");
    }

    public function toggleActive(Event $event)
    {
        $event->update(['is_active' => !$event->is_active]);

        return back()->with('message', 'Event active status updated!');
    }

    public function destroy(Event $event)
    {
        $event->delete();

        return back()->with('message', 'Event deleted successfully.');
    }
}