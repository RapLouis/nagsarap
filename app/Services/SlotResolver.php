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
 *   morning_time_in_start, morning_time_in_end,
 *   morning_time_out_start, morning_time_out_end,
 *   afternoon_time_in_start, afternoon_time_in_end,
 *   afternoon_time_out_start, afternoon_time_out_end
 *   (with fallback to legacy time_in_start/time_out_start).
 *
 * Every attendance row is identified by (event_date, slot_index, checkpoint_key),
 * so morning time-in, morning time-out, afternoon time-in, and afternoon time-out
 * can coexist independently within the same slot.
 */
class SlotResolver
{
    /** Extra minutes accepted before the start / after the end of a window. */
    public const GRACE_MINUTES = 0;

    /** Time-In is no longer required to perform a Time-Out. */
    public const REQUIRE_TIME_IN_FOR_TIME_OUT = false;

    /**
     * Resolve a slot explicitly chosen by the client (slot_index + checkpoint_key / type).
     *
     * @return array{date:string,index:int,type:string,checkpoint_key:string,slot:array,start:Carbon,end:Carbon,status:string}
     */
    public function resolve(Event $event, CarbonInterface $at, int $slotIndex, ?string $checkpointKey = null, ?string $type = null): array
    {
        $at = $this->localize($at);

        if (!$checkpointKey && $type) {
            $checkpointKey = $this->inferCheckpointKey($type, $at);
        } elseif (!$checkpointKey) {
            $checkpointKey = Attendance::MORNING_TIME_IN;
        }

        foreach ($this->candidateDays($event, $at) as [$date, $day]) {
            $slots = array_values($day->slots ?? []);

            if (!isset($slots[$slotIndex])) {
                continue;
            }

            $resolved = $this->match($date, $slotIndex, $slots[$slotIndex], $checkpointKey, $at);

            if ($resolved) {
                return $resolved;
            }
        }

        throw new AttendanceException(
            'SLOT_CLOSED',
            'The attendance window for this checkpoint is not open right now.',
            422,
            ['slot_index' => $slotIndex, 'checkpoint_key' => $checkpointKey, 'attendance_time' => $at->toIso8601String()]
        );
    }

    /**
     * Resolve explicitly when slot_index + checkpoint_key/type are supplied; otherwise infer the
     * window from the timestamp across all four checkpoints.
     */
    public function resolveOrInfer(Event $event, CarbonInterface $at, ?int $slotIndex, ?string $checkpointKey = null, ?string $type = null): array
    {
        if ($slotIndex !== null && ($checkpointKey !== null || $type !== null)) {
            return $this->resolve($event, $at, $slotIndex, $checkpointKey, $type);
        }

        $at = $this->localize($at);

        foreach ($this->candidateDays($event, $at) as [$date, $day]) {
            foreach (array_values($day->slots ?? []) as $index => $slot) {
                foreach (Attendance::CHECKPOINTS as $candidateCheckpoint) {
                    $resolved = $this->match($date, $index, $slot, $candidateCheckpoint, $at);

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
     * Slot-aware duplicate protection based on checkpoint_key.
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

        $checkpointKeys = $query->pluck('checkpoint_key')->all();

        if (in_array($resolved['checkpoint_key'], $checkpointKeys, true)) {
            $message = match ($resolved['checkpoint_key']) {
                Attendance::MORNING_TIME_IN => 'You have already logged your morning time-in for this time slot.',
                Attendance::MORNING_TIME_OUT => 'You have already logged your morning time-out for this time slot.',
                Attendance::AFTERNOON_TIME_IN => 'You have already logged your afternoon time-in for this time slot.',
                Attendance::AFTERNOON_TIME_OUT => 'You have already logged your afternoon time-out for this time slot.',
                default => 'You have already logged attendance for this checkpoint.',
            };

            throw new AttendanceException(
                'ALREADY_CHECKED_IN',
                $message,
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

    private function match(string $date, int $index, array $slot, string $checkpointKey, CarbonInterface $at): ?array
    {
        [$startKey, $endKey, $type] = match ($checkpointKey) {
            Attendance::MORNING_TIME_IN => [
                $slot['morning_time_in_start'] ?? $slot['time_in_start'] ?? null,
                $slot['morning_time_in_end'] ?? $slot['time_in_end'] ?? null,
                'in'
            ],
            Attendance::MORNING_TIME_OUT => [
                $slot['morning_time_out_start'] ?? $slot['time_out_start'] ?? null,
                $slot['morning_time_out_end'] ?? $slot['time_out_end'] ?? null,
                'out'
            ],
            Attendance::AFTERNOON_TIME_IN => [
                $slot['afternoon_time_in_start'] ?? null,
                $slot['afternoon_time_in_end'] ?? null,
                'in'
            ],
            Attendance::AFTERNOON_TIME_OUT => [
                $slot['afternoon_time_out_start'] ?? null,
                $slot['afternoon_time_out_end'] ?? null,
                'out'
            ],
            default => [
                $slot['time_in_start'] ?? null,
                $slot['time_in_end'] ?? null,
                'in'
            ],
        };

        if (empty($startKey)) {
            return null;
        }

        $tz = config('app.timezone');
        $start = Carbon::parse("{$date} " . trim($startKey), $tz);

        if (!empty($endKey)) {
            $end = Carbon::parse("{$date} " . trim($endKey), $tz)->endOfMinute();

            if ($end->lessThanOrEqualTo($start)) {
                $end->addDay(); // window crosses midnight
            }
        } else {
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
            'checkpoint_key' => $checkpointKey,
            'slot' => $slot,
            'start' => $start,
            'end' => $end,
            'status' => 'present',
        ];
    }

    private function inferCheckpointKey(string $type, CarbonInterface $at): string
    {
        $hour = (int) $at->format('G');

        if ($type === 'in') {
            return $hour < 12 ? Attendance::MORNING_TIME_IN : Attendance::AFTERNOON_TIME_IN;
        }

        return $hour < 12 ? Attendance::MORNING_TIME_OUT : Attendance::AFTERNOON_TIME_OUT;
    }

    private function localize(CarbonInterface $at): Carbon
    {
        return Carbon::instance($at)->timezone(config('app.timezone'));
    }
}