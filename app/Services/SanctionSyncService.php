<?php

namespace App\Services;

use App\Models\Attendance;
use App\Models\Event;
use App\Models\Sanction;
use App\Models\SanctionSetting;
use App\Models\Student;
use Carbon\Carbon;
use Illuminate\Support\Collection;

class SanctionSyncService
{
    public function syncForStudent(Student $student, ?Collection $allEvents = null, ?float $fineRate = null): void
    {
        if ($student->verification_status !== 'verified') {
            return;
        }

        $tz = config('app.timezone', 'Asia/Manila');
        $now = Carbon::now($tz);
        $fineRate = $fineRate ?? SanctionSetting::getFinePerLog();
        $studentSectionStr = trim("{$student->degree} - {$student->year_section}");

        // Filter preloaded events or query directly for single-student sync
        $events = ($allEvents ?? Event::with('days')->get())->filter(function (Event $event) use ($studentSectionStr) {
            if ($event->target_scope === 'all') {
                return true;
            }
            if ($event->target_scope === 'section') {
                $sections = is_array($event->target_sections)
                    ? $event->target_sections
                    : (json_decode((string) $event->target_sections, true) ?? []);
                return in_array($studentSectionStr, $sections, true);
            }
            return false;
        });

        $student->loadMissing('attendances');
        $attendanceMap = [];
        foreach ($student->attendances as $att) {
            $dateStr = Carbon::parse($att->event_date)->format('Y-m-d');
            $checkpointKey = $att->checkpoint_key ?? ($att->type === 'in' ? Attendance::MORNING_TIME_IN : Attendance::MORNING_TIME_OUT);
            $attendanceMap[$att->event_id][$dateStr][$att->slot_index][$checkpointKey] = true;
        }

        $checkpointsConfig = [
            Attendance::MORNING_TIME_IN => [
                'session'      => 'morning',
                'start_keys'   => ['morning_time_in_start', 'time_in_start'],
                'end_keys'     => ['morning_time_in_end', 'time_in_end'],
                'infraction'   => 'missing_morning_time_in',
                'title_prefix' => 'Missing Morning Time-In',
            ],
            Attendance::MORNING_TIME_OUT => [
                'session'      => 'morning',
                'start_keys'   => ['morning_time_out_start', 'time_out_start'],
                'end_keys'     => ['morning_time_out_end', 'time_out_end'],
                'infraction'   => 'missing_morning_time_out',
                'title_prefix' => 'Missing Morning Time-Out',
            ],
            Attendance::AFTERNOON_TIME_IN => [
                'session'      => 'afternoon',
                'start_keys'   => ['afternoon_time_in_start'],
                'end_keys'     => ['afternoon_time_in_end'],
                'infraction'   => 'missing_afternoon_time_in',
                'title_prefix' => 'Missing Afternoon Time-In',
            ],
            Attendance::AFTERNOON_TIME_OUT => [
                'session'      => 'afternoon',
                'start_keys'   => ['afternoon_time_out_start'],
                'end_keys'     => ['afternoon_time_out_end'],
                'infraction'   => 'missing_afternoon_time_out',
                'title_prefix' => 'Missing Afternoon Time-Out',
            ],
        ];

        foreach ($events as $event) {
            // Skip unapproved/rejected draft events if approval status is tracked
            if (isset($event->status) && in_array($event->status, ['pending', 'rejected'], true)) {
                continue;
            }

            foreach ($event->days as $day) {
                $dateStr = Carbon::parse($day->event_date)->toDateString();

                // Future event days cannot have missed checkpoints yet
                if ($dateStr > $now->toDateString()) {
                    continue;
                }

                $slots = $day->slots ?? [['label' => 'Slot 1']];
                foreach ($slots as $index => $slot) {
                    $slotLabel = is_array($slot) ? ($slot['label'] ?? ('Slot ' . ($index + 1))) : ('Slot ' . ($index + 1));

                    // Respect explicit afternoon toggle if stored in JSON
                    $afternoonExplicitlyDisabled = is_array($slot)
                        && array_key_exists('has_afternoon', $slot)
                        && $slot['has_afternoon'] === false;

                    foreach ($checkpointsConfig as $checkpointKey => $config) {
                        if ($config['session'] === 'afternoon' && $afternoonExplicitlyDisabled) {
                            continue;
                        }

                        $startTime = $this->firstNonEmpty($slot, $config['start_keys']);
                        $endTime   = $this->firstNonEmpty($slot, $config['end_keys']);

                        $isConfigured = !empty($startTime);
                        if (empty($day->slots) && $config['session'] === 'morning') {
                            $isConfigured = true;
                        }

                        if (!$isConfigured) {
                            continue;
                        }

                        // Ensure the checkpoint's cutoff window has actually closed before issuing a sanction
                        if (!$this->hasWindowClosed($dateStr, $startTime, $endTime, $now, $tz)) {
                            continue;
                        }

                        $hasLogged = $attendanceMap[$event->event_id][$dateStr][$index][$checkpointKey] ?? false;

                        if (!$hasLogged) {
                            Sanction::firstOrCreate(
                                [
                                    'student_id'      => $student->student_id,
                                    'event_id'        => $event->event_id,
                                    'event_date'      => $dateStr,
                                    'slot_index'      => $index,
                                    'infraction_type' => $config['infraction'],
                                ],
                                [
                                    'slot_label'     => $slotLabel,
                                    'fine_amount'    => $fineRate > 0 ? $fineRate : 50.00,
                                    'title'          => "{$config['title_prefix']}: {$event->title}",
                                    'reason'         => "Missed checkpoint ({$checkpointKey}) for {$slotLabel} on {$dateStr}.",
                                    'status'         => 'unsettled',
                                    'preferred_mode' => 'unselected',
                                    'issued_at'      => $now,
                                ]
                            );
                        }
                    }
                }
            }
        }
    }

    public function syncAllStudents(): void
    {
        $allEvents = Event::with('days')->get();
        $fineRate  = SanctionSetting::getFinePerLog();

        Student::where('verification_status', 'verified')
            ->with('attendances')
            ->chunk(100, function ($students) use ($allEvents, $fineRate) {
                foreach ($students as $student) {
                    $this->syncForStudent($student, $allEvents, $fineRate);
                }
            });
    }

    private function firstNonEmpty(mixed $slot, array $keys): ?string
    {
        if (!is_array($slot)) {
            return null;
        }
        foreach ($keys as $key) {
            if (!empty($slot[$key])) {
                return trim((string) $slot[$key]);
            }
        }
        return null;
    }

    private function hasWindowClosed(string $dateStr, ?string $startTime, ?string $endTime, Carbon $now, string $tz): bool
    {
        if (empty($startTime)) {
            return $dateStr < $now->toDateString();
        }

        $start = Carbon::parse("{$dateStr} {$startTime}", $tz);

        if (!empty($endTime)) {
            $end = Carbon::parse("{$dateStr} {$endTime}", $tz)->endOfMinute();
            if ($end->lessThanOrEqualTo($start)) {
                $end->addDay(); // Handle overnight window crossover
            }
        } else {
            $end = $start->copy()->endOfDay();
        }

        return $now->greaterThan($end);
    }
}