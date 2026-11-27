<?php

namespace App\Http\Controllers\Organizer;

use App\Http\Controllers\Controller;
use App\Models\Event;
use App\Models\Student;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Inertia\Inertia;
use Carbon\Carbon;

class OrganizerEventController extends Controller
{
    /**
     * Normalize slot payloads so disabled morning/afternoon sessions have null time windows.
     */
    private function sanitizeSlots(array $slots): array
    {
        return array_map(function ($slot) {
            $morningEnabled = array_key_exists('morning_enabled', $slot)
                ? (bool) $slot['morning_enabled']
                : (array_key_exists('has_morning', $slot)
                    ? (bool) $slot['has_morning']
                    : (!empty($slot['morning_time_in_start']) || !empty($slot['time_in_start'])));

            $afternoonEnabled = array_key_exists('afternoon_enabled', $slot)
                ? (bool) $slot['afternoon_enabled']
                : (array_key_exists('has_afternoon', $slot)
                    ? (bool) $slot['has_afternoon']
                    : (!empty($slot['afternoon_time_in_start']) || !empty($slot['afternoon_time_out_start'])));

            return [
                'morning_enabled'          => $morningEnabled,
                'afternoon_enabled'        => $afternoonEnabled,
                'has_morning'              => $morningEnabled,
                'has_afternoon'            => $afternoonEnabled,
                'morning_time_in_start'    => $morningEnabled ? ($slot['morning_time_in_start'] ?? $slot['time_in_start'] ?? null) : null,
                'morning_time_in_end'      => $morningEnabled ? ($slot['morning_time_in_end'] ?? $slot['time_in_end'] ?? null) : null,
                'morning_time_out_start'   => $morningEnabled ? ($slot['morning_time_out_start'] ?? $slot['time_out_start'] ?? null) : null,
                'morning_time_out_end'     => $morningEnabled ? ($slot['morning_time_out_end'] ?? $slot['time_out_end'] ?? null) : null,
                'afternoon_time_in_start'  => $afternoonEnabled ? ($slot['afternoon_time_in_start'] ?? null) : null,
                'afternoon_time_in_end'    => $afternoonEnabled ? ($slot['afternoon_time_in_end'] ?? null) : null,
                'afternoon_time_out_start' => $afternoonEnabled ? ($slot['afternoon_time_out_start'] ?? null) : null,
                'afternoon_time_out_end'   => $afternoonEnabled ? ($slot['afternoon_time_out_end'] ?? null) : null,
                'time_in_start'            => $morningEnabled ? ($slot['time_in_start'] ?? $slot['morning_time_in_start'] ?? null) : null,
                'time_in_end'              => $morningEnabled ? ($slot['time_in_end'] ?? $slot['morning_time_in_end'] ?? null) : null,
                'time_out_start'           => $morningEnabled ? ($slot['time_out_start'] ?? $slot['morning_time_out_start'] ?? null) : null,
                'time_out_end'             => $morningEnabled ? ($slot['time_out_end'] ?? $slot['morning_time_out_end'] ?? null) : null,
            ];
        }, $slots);
    }

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
            
            // Generate public URL for the official letter if it exists
            $event->official_letter_url = $event->official_letter_path 
                ? Storage::url($event->official_letter_path) 
                : null;

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
            'title'                                       => 'required|string|max:255',
            'description'                                 => 'nullable|string',
            'location'                                    => 'nullable|string',
            'is_geofenced'                                => 'boolean',
            'geofence_type'                               => 'in:radius,polygon',
            'latitude'                                    => 'nullable|numeric',
            'longitude'                                   => 'nullable|numeric',
            'radius_meters'                               => 'integer',
            'geofence_polygon'                            => 'nullable|array',
            'target_scope'                                => 'in:all,section',
            'target_sections'                             => 'nullable|array',
            'event_date'                                  => 'required|date',
            'event_end_date'                              => 'nullable|date|after_or_equal:event_date',
            'schedules'                                   => 'nullable|array',
            'schedules.*.date'                            => ['required', 'string'],
            'schedules.*.slots'                           => ['required', 'array', 'min:1'],
            'schedules.*.slots.*.morning_enabled'         => ['nullable', 'boolean'],
            'schedules.*.slots.*.afternoon_enabled'       => ['nullable', 'boolean'],
            'schedules.*.slots.*.has_morning'             => ['nullable', 'boolean'],
            'schedules.*.slots.*.has_afternoon'           => ['nullable', 'boolean'],
            'schedules.*.slots.*.morning_time_in_start'   => ['nullable'],
            'schedules.*.slots.*.morning_time_in_end'     => ['nullable'],
            'schedules.*.slots.*.morning_time_out_start'  => ['nullable'],
            'schedules.*.slots.*.morning_time_out_end'    => ['nullable'],
            'schedules.*.slots.*.afternoon_time_in_start' => ['nullable'],
            'schedules.*.slots.*.afternoon_time_in_end'   => ['nullable'],
            'schedules.*.slots.*.afternoon_time_out_start'=> ['nullable'],
            'schedules.*.slots.*.afternoon_time_out_end'  => ['nullable'],
            'is_active'                                   => 'boolean',
            'official_letter'                             => 'required|file|mimes:pdf,jpg,jpeg,png|max:5120', // Max 5MB letter file
        ]);

        // Handle Official Letter Upload
        if ($request->hasFile('official_letter')) {
            $validated['official_letter_path'] = $request->file('official_letter')->store('event-letters', 'public');
        }
        unset($validated['official_letter']);

        $validated['user_id'] = $request->user()->id;
        $validated['approval_status'] = 'pending';
        $validated['status'] = 'pending';

        $schedules = $validated['schedules'] ?? [];
        unset($validated['schedules']);

        $event = Event::create($validated);

        // Store schedule days & slots into event_days relation table with sanitized slot data
        if (!empty($schedules)) {
            foreach ($schedules as $sched) {
                $event->days()->create([
                    'event_date' => $sched['date'] ?? $validated['event_date'],
                    'slots' => $this->sanitizeSlots($sched['slots'] ?? []),
                ]);
            }
        }

        return redirect()->back()->with('success', 'Event and official letter submitted for admin approval.');
    }

    public function update(Request $request, Event $event)
    {
        if ($event->user_id !== $request->user()->id) {
            abort(403, 'Unauthorized action.');
        }

        $validated = $request->validate([
            'title'                                       => 'required|string|max:255',
            'description'                                 => 'nullable|string',
            'location'                                    => 'nullable|string',
            'is_geofenced'                                => 'boolean',
            'geofence_type'                               => 'in:radius,polygon',
            'latitude'                                    => 'nullable|numeric',
            'longitude'                                   => 'nullable|numeric',
            'radius_meters'                               => 'integer',
            'geofence_polygon'                            => 'nullable|array',
            'target_scope'                                => 'in:all,section',
            'target_sections'                             => 'nullable|array',
            'event_date'                                  => 'required|date',
            'event_end_date'                              => 'nullable|date|after_or_equal:event_date',
            'schedules'                                   => 'nullable|array',
            'schedules.*.date'                            => ['required', 'string'],
            'schedules.*.slots'                           => ['required', 'array', 'min:1'],
            'schedules.*.slots.*.morning_enabled'         => ['nullable', 'boolean'],
            'schedules.*.slots.*.afternoon_enabled'       => ['nullable', 'boolean'],
            'schedules.*.slots.*.has_morning'             => ['nullable', 'boolean'],
            'schedules.*.slots.*.has_afternoon'           => ['nullable', 'boolean'],
            'schedules.*.slots.*.morning_time_in_start'   => ['nullable'],
            'schedules.*.slots.*.morning_time_in_end'     => ['nullable'],
            'schedules.*.slots.*.morning_time_out_start'  => ['nullable'],
            'schedules.*.slots.*.morning_time_out_end'    => ['nullable'],
            'schedules.*.slots.*.afternoon_time_in_start' => ['nullable'],
            'schedules.*.slots.*.afternoon_time_in_end'   => ['nullable'],
            'schedules.*.slots.*.afternoon_time_out_start'=> ['nullable'],
            'schedules.*.slots.*.afternoon_time_out_end'  => ['nullable'],
            'is_active'                                   => 'boolean',
            'official_letter'                             => 'nullable|file|mimes:pdf,jpg,jpeg,png|max:5120',
        ]);

        // Handle replacement of Official Letter if a new file is provided
        if ($request->hasFile('official_letter')) {
            if ($event->official_letter_path && Storage::disk('public')->exists($event->official_letter_path)) {
                Storage::disk('public')->delete($event->official_letter_path);
            }
            $validated['official_letter_path'] = $request->file('official_letter')->store('event-letters', 'public');
        }
        unset($validated['official_letter']);

        $validated['approval_status'] = 'pending'; // Reset back to pending upon update
        
        $schedules = $validated['schedules'] ?? [];
        unset($validated['schedules']);

        $event->update($validated);

        if (!empty($schedules)) {
            $event->days()->delete();
            foreach ($schedules as $sched) {
                $event->days()->create([
                    'event_date' => $sched['date'] ?? $validated['event_date'],
                    'slots' => $this->sanitizeSlots($sched['slots'] ?? []),
                ]);
            }
        }

        return redirect()->back()->with('success', 'Event updated and resubmitted with official letter for admin approval.');
    }

    public function destroy(Request $request, Event $event)
    {
        if ($event->user_id !== $request->user()->id) {
            abort(403, 'Unauthorized action.');
        }

        // Delete official letter file from storage if it exists
        if ($event->official_letter_path && Storage::disk('public')->exists($event->official_letter_path)) {
            Storage::disk('public')->delete($event->official_letter_path);
        }

        $event->days()->delete();
        $event->delete();
        
        return redirect()->back()->with('success', 'Event deleted successfully.');
    }
}