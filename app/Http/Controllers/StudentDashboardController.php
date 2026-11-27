<?php

namespace App\Http\Controllers;

use App\Models\Attendance;
use App\Models\Event;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Str;
use Inertia\Inertia;

class StudentDashboardController extends Controller
{
    /**
     * Render the main student dashboard.
     */
    public function index(Request $request)
    {
        $user = Auth::user();

        if ($user->role === 'admin') {
            return redirect()->route('admin.dashboard');
        }

        if ($user->role === 'organizer') {
            return redirect()->route('organizer.dashboard');
        }

        // Load student along with their attendances
        $student = $user->load(['student.attendances.event'])->student;

        // Redirect unverified students directly to face verification
        if ($student && $student->verification_status === 'pending_face_verification') {
            return redirect()->route('register.verify-face');
        }

        if ($student) {
            $student->face_photo_url = $student->face_photo_path
                ? route('student.face-photo', ['student' => $student->student_id])
                : null;
        }

        $today = now()->toDateString();
        $studentSectionStr = $student ? trim("{$student->degree} - {$student->year_section}") : '';

        $studentEventScope = function ($query) use ($studentSectionStr) {
            $query->where('target_scope', 'all')
                  ->orWhere(function ($sub) use ($studentSectionStr) {
                      $sub->where('target_scope', 'section')
                          ->whereJsonContains('target_sections', $studentSectionStr);
                  });
        };

        // Index student attendances by event_id, date, slot_index, and checkpoint_key
        $attendanceMap = $this->buildAttendanceMap($student);

        // 1. Fetch active events for today with structured slot schedules and active checkpoint statuses
        $activeEvents = Event::ongoing()
            ->where($studentEventScope)
            ->with('days')
            ->get()
            ->transform(function ($event) use ($attendanceMap) {
                $event->schedules = $event->days->map(function ($day) use ($event, $attendanceMap) {
                    $dateStr = $day->event_date instanceof Carbon
                        ? $day->event_date->format('Y-m-d')
                        : Carbon::parse($day->event_date)->format('Y-m-d');

                    $formatted = $this->formatDaySlots($day->slots ?? [], $event->event_id, $dateStr, $attendanceMap);

                    return [
                        'date'              => $dateStr,
                        'slots'             => $formatted['slots'],
                        'total_checkpoints' => $formatted['total_checkpoints'],
                        'attended_count'    => $formatted['attended_count'],
                    ];
                });

                return $event;
            });

        // 2. Format upcoming events for the "Coming Up" widget
        $upcomingEvents = Event::with('days')
            ->where($studentEventScope)
            ->get()
            ->map(function ($event) use ($today) {
                $futureDays = $event->days->filter(fn ($day) => Carbon::parse($day->event_date)->toDateString() > $today);
                if ($futureDays->isEmpty()) {
                    return null;
                }

                $sortedDays = $futureDays->sortBy('event_date');
                $nextDate = Carbon::parse($sortedDays->first()->event_date)->toDateString();
                $startDate = Carbon::parse($event->days->min('event_date'))->toDateString();
                $endDate = Carbon::parse($event->days->max('event_date'))->toDateString();

                return [
                    'event_id'   => $event->event_id,
                    'title'      => $event->title,
                    'location'   => $event->location,
                    'next_date'  => $nextDate,
                    'start_date' => $startDate,
                    'end_date'   => $endDate,
                    'day_count'  => $event->days->count(),
                ];
            })->filter()->values();

        // 3. Format calendar events for the dashboard preview widget
        $calendarEvents = $this->buildCalendarEvents($studentEventScope, $attendanceMap, $today);

        $totalExpectedEvents = Event::where($studentEventScope)->count();

        $challenge = [
            'nonce'        => Str::random(40),
            'direction'    => rand(0, 1) === 0 ? 'left' : 'right',
            'flash_colors' => ['red', 'green', 'blue'],
        ];

        return Inertia::render('dashboard', [
            'student'             => $student,
            'activeEvents'        => $activeEvents,
            'calendarEvents'      => $calendarEvents,
            'upcomingEvents'      => $upcomingEvents,
            'totalExpectedEvents' => $totalExpectedEvents,
            'today'               => $today,
            'livenessChallenge'   => $challenge,
        ]);
    }

    /**
     * Render the dedicated student calendar view.
     */
    public function calendar(Request $request)
    {
        $user = Auth::user();
        $student = $user?->load(['student.attendances.event'])->student;

        $studentSectionStr = $student ? trim("{$student->degree} - {$student->year_section}") : '';
        $studentEventScope = function ($query) use ($studentSectionStr) {
            $query->where('target_scope', 'all')
                  ->orWhere(function ($sub) use ($studentSectionStr) {
                      $sub->where('target_scope', 'section')
                          ->whereJsonContains('target_sections', $studentSectionStr);
                  });
        };

        $today = now()->toDateString();
        $attendanceMap = $this->buildAttendanceMap($student);
        $calendarEvents = $this->buildCalendarEvents($studentEventScope, $attendanceMap, $today);

        return Inertia::render('Calendar', [
            'student'        => $student,
            'calendarEvents' => $calendarEvents,
            'today'          => $today,
        ]);
    }

    /**
     * Index student attendances by event_id, date, slot_index, and checkpoint_key.
     */
    private function buildAttendanceMap($student): array
    {
        $attendanceMap = [];
        if ($student && $student->attendances) {
            foreach ($student->attendances as $attendance) {
                $dateStr = Carbon::parse($attendance->event_date)->format('Y-m-d');
                $key = $attendance->checkpoint_key ?? ($attendance->type === 'in' ? Attendance::MORNING_TIME_IN : Attendance::MORNING_TIME_OUT);
                $attendanceMap[$attendance->event_id][$dateStr][$attendance->slot_index][$key] = true;
            }
        }

        return $attendanceMap;
    }

    /**
     * Build formatted calendar event payloads respecting enabled morning/afternoon sessions.
     */
    private function buildCalendarEvents(callable $studentEventScope, array $attendanceMap, string $today)
    {
        return Event::with('days')
            ->where($studentEventScope)
            ->get()
            ->map(function ($event) use ($attendanceMap, $today) {
                $schedules = $event->days->isNotEmpty()
                    ? $event->days->map(function ($day) use ($event, $attendanceMap, $today) {
                        $dateStr = $day->event_date instanceof Carbon
                            ? $day->event_date->format('Y-m-d')
                            : Carbon::parse($day->event_date)->format('Y-m-d');

                        $formatted = $this->formatDaySlots($day->slots ?? [], $event->event_id, $dateStr, $attendanceMap);
                        $totalCheckpoints = $formatted['total_checkpoints'];
                        $attendedCount = $formatted['attended_count'];

                        $status = 'upcoming';
                        if ($dateStr < $today) {
                            $status = $attendedCount >= $totalCheckpoints && $totalCheckpoints > 0
                                ? 'attended'
                                : ($attendedCount > 0 ? 'partial' : 'absent');
                        } elseif ($dateStr === $today) {
                            $status = $attendedCount > 0 ? 'partial' : 'active';
                        }

                        return [
                            'date'              => $dateStr,
                            'slots'             => $formatted['slots'],
                            'day_status'        => $status,
                            'total_checkpoints' => $totalCheckpoints,
                            'attended_count'    => $attendedCount,
                        ];
                    })->toArray()
                    : [];

                return [
                    'event_id'  => $event->event_id,
                    'title'     => $event->title,
                    'location'  => $event->location,
                    'schedules' => $schedules,
                ];
            });
    }

    /**
     * Determine enabled sessions per slot and calculate accurate checkpoint totals.
     */
    private function formatDaySlots(array $rawSlots, int $eventId, string $dateStr, array $attendanceMap): array
    {
        $totalCheckpoints = 0;
        $attendedCount = 0;

        $slots = collect($rawSlots)->map(function ($slot, $index) use ($eventId, $dateStr, $attendanceMap, &$totalCheckpoints, &$attendedCount) {
            $hasMorning = ($slot['morning_enabled'] ?? true)
                && (!empty($slot['morning_time_in_start']) || !empty($slot['morning_in']) || !empty($slot['start_time']) || !isset($slot['morning_enabled']));

            // Check explicit flag first; fallback to checking if afternoon time fields are non-empty
            $hasAfternoon = array_key_exists('afternoon_enabled', $slot)
                ? (bool) $slot['afternoon_enabled']
                : (!empty($slot['afternoon_time_in_start']) || !empty($slot['afternoon_in']) || !empty($slot['afternoon_start']));

            $morningIn = $hasMorning && ($attendanceMap[$eventId][$dateStr][$index][Attendance::MORNING_TIME_IN] ?? false);
            $morningOut = $hasMorning && ($attendanceMap[$eventId][$dateStr][$index][Attendance::MORNING_TIME_OUT] ?? false);
            $afternoonIn = $hasAfternoon && ($attendanceMap[$eventId][$dateStr][$index][Attendance::AFTERNOON_TIME_IN] ?? false);
            $afternoonOut = $hasAfternoon && ($attendanceMap[$eventId][$dateStr][$index][Attendance::AFTERNOON_TIME_OUT] ?? false);

            if ($hasMorning) {
                $totalCheckpoints += 2;
                $attendedCount += ($morningIn ? 1 : 0) + ($morningOut ? 1 : 0);
            }

            if ($hasAfternoon) {
                $totalCheckpoints += 2;
                $attendedCount += ($afternoonIn ? 1 : 0) + ($afternoonOut ? 1 : 0);
            }

            return array_merge($slot, [
                'slot_index'         => $index,
                'has_morning'        => $hasMorning,
                'has_afternoon'      => $hasAfternoon,
                'morning_time_in'    => $morningIn,
                'morning_time_out'   => $morningOut,
                'afternoon_time_in'  => $hasAfternoon ? $afternoonIn : null,
                'afternoon_time_out' => $hasAfternoon ? $afternoonOut : null,
                'checked_in'         => $morningIn || $afternoonIn,
                'checked_out'        => $morningOut || $afternoonOut,
            ]);
        })->toArray();

        return [
            'slots'             => $slots,
            'total_checkpoints' => $totalCheckpoints,
            'attended_count'    => $attendedCount,
        ];
    }
}