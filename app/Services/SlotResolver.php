<?php

namespace App\Services;

use App\Exceptions\AttendanceException;
use App\Models\Attendance;
use App\Models\Event;
use Carbon\Carbon;
use Carbon\CarbonInterface;

/**
 * Single source of truth for "which slot / which window is this attendance for".
 *
 * A slot lives in event_days.slots (JSON list). Each slot may define:
 *   time_in_start,  time_in_end,  time_out_start,  time_out_end
 *
 * Every attendance row is identified by (event_date, slot_index, type), so a
 * Time-In never blocks a Time-Out, and Slot 1 never blocks Slot 2.
 */
class SlotResolver
{
    /** Extra minutes accepted before the start / after the end of a window. */
    public const GRACE_MINUTES = 0;

    /** Time-In is no longer required to perform a Time-Out. */
    public const REQUIRE_TIME_IN_FOR_TIME_OUT = false;

    /**
     * Resolve a slot explicitly chosen by the client (slot_index + type).
     *
     * @return array{date:string,index:int,type:string,slot:array,start:Carbon,end:Carbon,status:string}
     */
    public function resolve(Event $event, CarbonInterface $at, int $slotIndex, string $type): array
    {
        $at = $this->localize($at);

        foreach ($this->candidateDays($event, $at) as [$date, $day]) {
            $slots = array_values($day->slots ?? []);

            if (!isset($slots[$slotIndex])) {
                continue;
            }

            $resolved = $this->match($date, $slotIndex, $slots[$slotIndex], $type, $at);

            if ($resolved) {
                return $resolved;
            }
        }

        throw new AttendanceException(
            'SLOT_CLOSED',
            $type === 'out'
                ? 'The Time-Out window for this slot is not open right now.'
                : 'The Time-In window for this slot is not open right now.',
            422,
            ['slot_index' => $slotIndex, 'type' => $type, 'attendance_time' => $at->toIso8601String()]
        );
    }

    /**
     * Resolve explicitly when slot_index + type are supplied; otherwise infer the
     * window from the timestamp (keeps older mobile clients working).
     */
    public function resolveOrInfer(Event $event, CarbonInterface $at, ?int $slotIndex, ?string $type): array
    {
        if ($slotIndex !== null && $type !== null) {
            return $this->resolve($event, $at, $slotIndex, $type);
        }

        $at = $this->localize($at);

        foreach ($this->candidateDays($event, $at) as [$date, $day]) {
            foreach (array_values($day->slots ?? []) as $index => $slot) {
                foreach (['in', 'out'] as $candidateType) {
                    $resolved = $this->match($date, $index, $slot, $candidateType, $at);

                    if ($resolved) {
                        return $resolved;
                    }
                }
            }
        }

        throw new AttendanceException(
            'EVENT_OUTSIDE_WINDOW',
            'Attendance is not open for this event at the supplied time.',
            422,
            ['attendance_time' => $at->toIso8601String()]
        );
    }

    /**
     * Slot-aware duplicate protection. Only looks at records for the SAME
     * event day + slot, so other slots and the opposite type never interfere.
     */
    public function guard(int $studentId, int $eventId, array $resolved, bool $lock = false): void
    {
        $query = Attendance::where('student_id', $studentId)
            ->where('event_id', $eventId)
            ->where('event_date', $resolved['date'])
            ->where('slot_index', $resolved['index']);

        if ($lock) {
            $query->lockForUpdate();
        }

        $types = $query->pluck('type')->all();

        if (in_array($resolved['type'], $types, true)) {
            throw new AttendanceException(
                'ALREADY_CHECKED_IN',
                $resolved['type'] === 'out'
                    ? 'You have already checked out for this time slot.'
                    : 'You have already checked in for this time slot.',
                409
            );
        }
    }

    /* ------------------------------------------------------------------ */

    /** @return array{0:string,1:\App\Models\EventDay}[] today first, then yesterday (overnight windows) */
    private function candidateDays(Event $event, CarbonInterface $at): array
    {
        $event->loadMissing('days');

        $out = [];

        foreach ([$at->toDateString(), $at->copy()->subDay()->toDateString()] as $date) {
            $day = $event->days->first(
                fn ($d) => Carbon::parse($d->event_date)->toDateString() === $date
            );

            if ($day) {
                $out[] = [$date, $day];
            }
        }

        return $out;
    }

    private function match(string $date, int $index, array $slot, string $type, CarbonInterface $at): ?array
    {
        $startKey = $type === 'in' ? 'time_in_start' : 'time_out_start';
        $endKey = $type === 'in' ? 'time_in_end' : 'time_out_end';

        if (empty($slot[$startKey])) {
            return null;
        }

        $tz = config('app.timezone');
        $start = Carbon::parse("{$date} " . trim($slot[$startKey]), $tz);

        if (!empty($slot[$endKey])) {
            $end = Carbon::parse("{$date} " . trim($slot[$endKey]), $tz)->endOfMinute();

            if ($end->lessThanOrEqualTo($start)) {
                $end->addDay(); // window crosses midnight
            }
        } else {
            // No cutoff configured: open until the end of that day (matches the UI).
            $end = $start->copy()->endOfDay();
        }

        $from = $start->copy()->subMinutes(self::GRACE_MINUTES);
        $to = $end->copy()->addMinutes(self::GRACE_MINUTES);

        if (!$at->betweenIncluded($from, $to)) {
            return null;
        }

        return [
            'date' => $date,
            'index' => $index,
            'type' => $type,
            'slot' => $slot,
            'start' => $start,
            'end' => $end,
            'status' => 'present', // Always marked as present when within the admin-set window
        ];
    }

    private function localize(CarbonInterface $at): Carbon
    {
        return Carbon::instance($at)->timezone(config('app.timezone'));
    }
}