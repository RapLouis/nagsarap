<?php

namespace App\Http\Controllers;

use App\Models\Event;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Inertia\Inertia;
use Inertia\Response;

class EventController extends Controller
{
    /**
     * Display a listing of events filtered by lifecycle tab and search query.
     */
    public function index(Request $request): Response
    {
        $search    = $request->input('search');
        $activeTab = $request->input('tab', 'ongoing');

        // Base query with search filter
        $query = Event::query()
            ->when($search, function ($q) use ($search) {
                $q->where(function ($sub) use ($search) {
                    $sub->where('title', 'like', "%{$search}%")
                        ->orWhere('location', 'like', "%{$search}%")
                        ->orWhere('description', 'like', "%{$search}%");
                });
            });

        // Apply Eloquent scopes based on the requested tab
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

        $events = $eventsQuery->orderBy('event_date', 'desc')
                              ->paginate(10)
                              ->withQueryString();

        // Calculate tab counts using model scopes
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

    /**
     * Store a newly created event.
     */
    public function store(Request $request)
    {
        $validated = $request->validate([
            'title'            => ['required', 'string', 'max:150'],
            'description'      => ['nullable', 'string'],
            'event_date'       => ['required', 'date'],
            'location'         => ['nullable', 'string', 'max:100'],
            'is_geofenced'     => ['boolean'],
            'geofence_type'    => ['nullable', Rule::in(['radius', 'polygon'])],
            
            // Conditional validation for Radius
            'latitude'         => ['nullable', 'required_if:is_geofenced,true', 'numeric', 'between:-90,90'],
            'longitude'        => ['nullable', 'required_if:is_geofenced,true', 'numeric', 'between:-180,180'],
            'radius_meters'    => ['nullable', 'integer', 'min:10', 'max:5000'],

            // Conditional validation for Polygon
            'geofence_polygon' => ['nullable', 'required_if:geofence_type,polygon', 'array', 'min:3'],
            'geofence_polygon.*.lat' => ['required_with:geofence_polygon', 'numeric', 'between:-90,90'],
            'geofence_polygon.*.lng' => ['required_with:geofence_polygon', 'numeric', 'between:-180,180'],

            'time_in_start'    => ['required'],
            'time_in_end'      => ['nullable'],
            'time_out_start'   => ['nullable'],
            'time_out_end'     => ['nullable'],
            'approval_status'  => ['nullable', Rule::in(['approved', 'pending', 'declined'])],
            'is_active'        => ['boolean'],
        ]);

        $isGeofenced  = $request->boolean('is_geofenced', false);
        $geofenceType = $validated['geofence_type'] ?? 'radius';

        // Role-based Auto-Approval Logic
        $user = $request->user();

        // Safe check using database columns (is_admin boolean or role string)
        $isAdmin = $user && (
            (isset($user->is_admin) && $user->is_admin) || 
            (isset($user->role) && in_array($user->role, ['admin', 'super_admin']))
        );

        $approvalStatus = $isAdmin ? 'approved' : 'pending';

        Event::create([
            'title'            => $validated['title'],
            'description'      => $validated['description'] ?? null,
            'event_date'       => $validated['event_date'],
            'location'         => $validated['location'] ?? null,
            'is_geofenced'     => $isGeofenced,
            'geofence_type'    => $isGeofenced ? $geofenceType : 'radius',
            'latitude'         => $isGeofenced ? ($validated['latitude'] ?? null) : null,
            'longitude'        => $isGeofenced ? ($validated['longitude'] ?? null) : null,
            'radius_meters'    => $isGeofenced ? ($validated['radius_meters'] ?? 100) : 100,
            'geofence_polygon' => ($isGeofenced && $geofenceType === 'polygon') ? $validated['geofence_polygon'] : null,
            'time_in_start'    => $validated['time_in_start'],
            'time_in_end'      => $validated['time_in_end'] ?? null,
            'time_out_start'   => $validated['time_out_start'] ?? null,
            'time_out_end'     => $validated['time_out_end'] ?? null,
            'approval_status'  => $approvalStatus,
            'is_active'        => $request->boolean('is_active', true),
        ]);

        return back()->with('message', 'Event created successfully!');
    }

    /**
     * Update the specified event.
     */
    public function update(Request $request, Event $event)
    {
        $validated = $request->validate([
            'title'            => ['required', 'string', 'max:150'],
            'description'      => ['nullable', 'string'],
            'event_date'       => ['required', 'date'],
            'location'         => ['nullable', 'string', 'max:100'],
            'is_geofenced'     => ['boolean'],
            'geofence_type'    => ['nullable', Rule::in(['radius', 'polygon'])],

            // Conditional validation for Radius
            'latitude'         => ['nullable', 'required_if:is_geofenced,true', 'numeric', 'between:-90,90'],
            'longitude'        => ['nullable', 'required_if:is_geofenced,true', 'numeric', 'between:-180,180'],
            'radius_meters'    => ['nullable', 'integer', 'min:10', 'max:5000'],

            // Conditional validation for Polygon
            'geofence_polygon' => ['nullable', 'required_if:geofence_type,polygon', 'array', 'min:3'],
            'geofence_polygon.*.lat' => ['required_with:geofence_polygon', 'numeric', 'between:-90,90'],
            'geofence_polygon.*.lng' => ['required_with:geofence_polygon', 'numeric', 'between:-180,180'],

            'time_in_start'    => ['required'],
            'time_in_end'      => ['nullable'],
            'time_out_start'   => ['nullable'],
            'time_out_end'     => ['nullable'],
            'approval_status'  => ['required', Rule::in(['approved', 'pending', 'declined'])],
            'is_active'        => ['boolean'],
        ]);

        $isGeofenced  = $request->boolean('is_geofenced', false);
        $geofenceType = $validated['geofence_type'] ?? 'radius';

        $event->update([
            'title'            => $validated['title'],
            'description'      => $validated['description'] ?? null,
            'event_date'       => $validated['event_date'],
            'location'         => $validated['location'] ?? null,
            'is_geofenced'     => $isGeofenced,
            'geofence_type'    => $isGeofenced ? $geofenceType : 'radius',
            'latitude'         => $isGeofenced ? ($validated['latitude'] ?? $event->latitude) : null,
            'longitude'        => $isGeofenced ? ($validated['longitude'] ?? $event->longitude) : null,
            'radius_meters'    => $isGeofenced ? ($validated['radius_meters'] ?? 100) : 100,
            'geofence_polygon' => ($isGeofenced && $geofenceType === 'polygon') ? $validated['geofence_polygon'] : null,
            'time_in_start'    => $validated['time_in_start'],
            'time_in_end'      => $validated['time_in_end'] ?? null,
            'time_out_start'   => $validated['time_out_start'] ?? null,
            'time_out_end'     => $validated['time_out_end'] ?? null,
            'approval_status'  => $validated['approval_status'],
            'is_active'        => $request->boolean('is_active', true),
        ]);

        return back()->with('message', 'Event updated successfully!');
    }

    /**
     * Quick status update for Pending events (Approve / Decline).
     */
    public function updateStatus(Request $request, Event $event)
    {
        $validated = $request->validate([
            'approval_status' => ['required', Rule::in(['approved', 'pending', 'declined'])],
        ]);

        $event->update(['approval_status' => $validated['approval_status']]);

        return back()->with('message', "Event status updated to {$validated['approval_status']}.");
    }

    /**
     * Toggle active/inactive status.
     */
    public function toggleActive(Event $event)
    {
        $event->update(['is_active' => !$event->is_active]);

        return back()->with('message', 'Event active status updated!');
    }

    /**
     * Remove the specified event.
     */
    public function destroy(Event $event)
    {
        $event->delete();

        return back()->with('message', 'Event deleted successfully.');
    }
}