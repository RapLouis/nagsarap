<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Event;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class EventController extends Controller
{
    /*
    |--------------------------------------------------------------------------
    | MOBILE EVENT LIST
    |--------------------------------------------------------------------------
    |
    | Return all active events.
    |
    | Flutter is responsible for splitting:
    |
    | - today's events
    | - upcoming events
    |
    | This avoids Laravel timezone/date filtering from hiding a valid event.
    |
    */

    public function index(Request $request): JsonResponse
    {
        $events = Event::query()
            ->where('is_active', 1)
            ->orderBy('event_date')
            ->orderBy('start_time')
            ->get([
                'event_id',
                'title',
                'description',
                'event_date',
                'start_time',
                'end_time',
                'location',
                'latitude',
                'longitude',
                'geofence_radius',
                'geofence_enabled',
                'late_after_minutes',
                'is_active',
                'created_at',
                'updated_at',
            ]);

        return response()->json([
            'success' => true,

            'count' => $events->count(),

            'data' => $events,
        ]);
    }

    /*
    |--------------------------------------------------------------------------
    | SINGLE EVENT
    |--------------------------------------------------------------------------
    */

    public function show(Event $event): JsonResponse
    {
        return response()->json([
            'success' => true,

            'data' => $event,
        ]);
    }
}