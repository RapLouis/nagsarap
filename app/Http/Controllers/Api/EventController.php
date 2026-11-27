<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Attendance;
use App\Models\Event;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class EventController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $student = $request->user()?->student;
        $studentSectionStr = $student
            ? trim("{$student->degree} - {$student->year_section}")
            : null;

        $events = Event::with('days')
            ->where('is_active', true)
            ->where('approval_status', 'approved')
            ->orderBy('event_date')
            ->orderBy('created_at')
            ->get()
            ->filter(function (Event $event) use ($student, $studentSectionStr) {
                if (!$student) {
                    return true;
                }
                if ($event->target_scope === 'all' || empty($event->target_scope)) {
                    return true;
                }
                if ($event->target_scope === 'section') {
                    $sections = is_array($event->target_sections)
                        ? $event->target_sections
                        : (json_decode((string) $event->target_sections, true) ?? []);
                    return in_array($studentSectionStr, $sections, true);
                }
                return false;
            })
            ->values();

        $attendancesByEvent = collect();
        if ($student && $events->isNotEmpty()) {
            $attendancesByEvent = Attendance::where('student_id', $student->student_id)
                ->whereIn('event_id', $events->pluck('event_id'))
                ->get()
                ->groupBy('event_id');
        }

        return response()->json([
            'success' => true,
            'count' => $events->count(),
            'data' => $events->map(
                fn (Event $e) => $this->payload($e, $attendancesByEvent->get($e->event_id, collect()))
            )->values(),
        ]);
    }

    public function show(Request $request, Event $event): JsonResponse
    {
        $event->load('days');
        $student = $request->user()?->student;

        $attendances = $student
            ? Attendance::where('student_id', $student->student_id)
                ->where('event_id', $event->event_id)
                ->get()
            : collect();

        return response()->json([
            'success' => true,
            'data' => $this->payload($event, $attendances),
        ]);
    }

    private function payload(Event $e, $studentAttendances): array
    {
        $days = $e->days->sortBy('event_date')->values();
        $first = $days->first();

        $slots = $days->flatMap(function ($d) {
            $raw = is_string($d->slots) ? json_decode($d->slots, true) : ($d->slots ?? []);
            return is_array($raw) ? $raw : [];
        });

        $startCandidates = $slots->flatMap(fn ($s) => [
            $s['morning_time_in_start'] ?? null,
            $s['time_in_start'] ?? null,
            $s['afternoon_time_in_start'] ?? null,
        ])->filter()->sort()->values();

        $endCandidates = $slots->flatMap(fn ($s) => [
            $s['afternoon_time_out_end'] ?? null,
            $s['morning_time_out_end'] ?? null,
            $s['time_out_end'] ?? null,
            $s['afternoon_time_in_end'] ?? null,
            $s['morning_time_in_end'] ?? null,
            $s['time_in_end'] ?? null,
        ])->filter()->sort()->values();

        $start = $startCandidates->first();
        $end = $endCandidates->last() ?? $start;

        $mappedAttendances = $studentAttendances->map(function (Attendance $att) {
            $dateStr = $att->event_date
                ? Carbon::parse($att->event_date)->format('Y-m-d')
                : null;

            return [
                'attendance_id' => $att->attendance_id,
                'event_date' => $dateStr,
                'slot_index' => (int) ($att->slot_index ?? 0),
                'type' => $att->type,
                'checkpoint_key' => $att->checkpoint_key,
                'status' => $att->status,
                'attendance_time' => $att->attendance_time?->toIso8601String(),
            ];
        })->values();

        $hasTimeIn = $mappedAttendances->contains(
            fn ($a) => $a['type'] === 'in' || str_ends_with((string) $a['checkpoint_key'], '_in')
        );
        $hasTimeOut = $mappedAttendances->contains(
            fn ($a) => $a['type'] === 'out' || str_ends_with((string) $a['checkpoint_key'], '_out')
        );

        return [
            'event_id' => $e->event_id,
            'title' => $e->title,
            'description' => $e->description,
            'target_scope' => $e->target_scope ?? 'all',
            'target_sections' => $e->target_sections ?? [],
            'event_date' => $first?->event_date?->format('Y-m-d') ?? $e->event_date?->format('Y-m-d'),
            'event_end_date' => $days->last()?->event_date?->format('Y-m-d') ?? $e->event_end_date?->format('Y-m-d'),
            'start_time' => $start,
            'end_time' => $end,
            'location' => $e->location,
            'latitude' => $e->latitude,
            'longitude' => $e->longitude,
            'geofence_radius' => $e->radius_meters,
            'geofence_enabled' => $e->is_geofenced,
            'geofence_type' => $e->geofence_type,
            'geofence_polygon' => $e->geofence_polygon,
            'late_after_minutes' => 15,
            'is_active' => $e->is_active,
            'approval_status' => $e->approval_status,
            'has_time_in' => $hasTimeIn,
            'has_time_out' => $hasTimeOut,
            'student_attendances' => $mappedAttendances,
            'days' => $days->map(fn ($d) => [
                'event_day_id' => $d->event_day_id,
                'event_date' => $d->event_date->format('Y-m-d'),
                'slots' => is_string($d->slots) ? json_decode($d->slots, true) : ($d->slots ?? []),
            ])->values(),
            'created_at' => $e->created_at,
            'updated_at' => $e->updated_at,
        ];
    }
}