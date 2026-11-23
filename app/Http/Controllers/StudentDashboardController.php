<?php

namespace App\Http\Controllers;

use App\Models\Attendance;
use App\Models\Event;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Str;
use Inertia\Inertia;
use Carbon\Carbon;

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
        $attendanceMap = [];
        if ($student && $student->attendances) {
            foreach ($student->attendances as $attendance) {
                $dateStr = Carbon::parse($attendance->event_date)->format('Y-m-d');
                $key = $attendance->checkpoint_key ?? ($attendance->type === 'in' ? Attendance::MORNING_TIME_IN : Attendance::MORNING_TIME_OUT);
                $attendanceMap[$attendance->event_id][$dateStr][$attendance->slot_index][$key] = true;
            }
        }

        // 1. Fetch active events for today with structured slot schedules and 4-checkpoint statuses
        $activeEvents = Event::ongoing()
            ->where($studentEventScope)
            ->with('days')
            ->get()
            ->transform(function ($event) use ($attendanceMap, $today) {
                $event->schedules = $event->days->map(function ($day) use ($event, $attendanceMap) {
                    $dateStr = $day->event_date instanceof Carbon ? $day->event_date->format('Y-m-d') : Carbon::parse($day->event_date)->format('Y-m-d');
                    
                    $slotsWithStatus = collect($day->slots ?? [])->map(function ($slot, $index) use ($event, $dateStr, $attendanceMap) {
                        return array_merge($slot, [
                            'slot_index'           => $index,
                            'morning_time_in'      => $attendanceMap[$event->event_id][$dateStr][$index][Attendance::MORNING_TIME_IN] ?? false,
                            'morning_time_out'     => $attendanceMap[$event->event_id][$dateStr][$index][Attendance::MORNING_TIME_OUT] ?? false,
                            'afternoon_time_in'    => $attendanceMap[$event->event_id][$dateStr][$index][Attendance::AFTERNOON_TIME_IN] ?? false,
                            'afternoon_time_out'   => $attendanceMap[$event->event_id][$dateStr][$index][Attendance::AFTERNOON_TIME_OUT] ?? false,
                            // Legacy backward compatibility flags
                            'checked_in'           => ($attendanceMap[$event->event_id][$dateStr][$index][Attendance::MORNING_TIME_IN] ?? false) || ($attendanceMap[$event->event_id][$dateStr][$index][Attendance::AFTERNOON_TIME_IN] ?? false),
                            'checked_out'          => ($attendanceMap[$event->event_id][$dateStr][$index][Attendance::MORNING_TIME_OUT] ?? false) || ($attendanceMap[$event->event_id][$dateStr][$index][Attendance::AFTERNOON_TIME_OUT] ?? false),
                        ]);
                    });

                    return [
                        'date'  => $dateStr,
                        'slots' => $slotsWithStatus->toArray(),
                    ];
                });
                return $event;
            });

        // 2. Format upcoming events for the "Coming Up" widget
        $upcomingEvents = Event::with('days')
            ->where($studentEventScope)
            ->get()
            ->map(function ($event) use ($today) {
                $futureDays = $event->days->filter(fn($day) => Carbon::parse($day->event_date)->toDateString() > $today);
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
        $calendarEvents = Event::with('days')
            ->where($studentEventScope)
            ->get()
            ->map(function ($event) use ($attendanceMap, $today) {
                $schedules = $event->days->isNotEmpty() 
                    ? $event->days->map(function ($day) use ($event, $attendanceMap, $today) {
                        $dateStr = $day->event_date instanceof Carbon ? $day->event_date->format('Y-m-d') : Carbon::parse($day->event_date)->format('Y-m-d');
                        
                        $slotsWithStatus = collect($day->slots ?? [])->map(function ($slot, $index) use ($event, $dateStr, $attendanceMap) {
                            return array_merge($slot, [
                                'slot_index'         => $index,
                                'morning_time_in'    => $attendanceMap[$event->event_id][$dateStr][$index][Attendance::MORNING_TIME_IN] ?? false,
                                'morning_time_out'   => $attendanceMap[$event->event_id][$dateStr][$index][Attendance::MORNING_TIME_OUT] ?? false,
                                'afternoon_time_in'  => $attendanceMap[$event->event_id][$dateStr][$index][Attendance::AFTERNOON_TIME_IN] ?? false,
                                'afternoon_time_out' => $attendanceMap[$event->event_id][$dateStr][$index][Attendance::AFTERNOON_TIME_OUT] ?? false,
                                'checked_in'         => ($attendanceMap[$event->event_id][$dateStr][$index][Attendance::MORNING_TIME_IN] ?? false) || ($attendanceMap[$event->event_id][$dateStr][$index][Attendance::AFTERNOON_TIME_IN] ?? false),
                                'checked_out'        => ($attendanceMap[$event->event_id][$dateStr][$index][Attendance::MORNING_TIME_OUT] ?? false) || ($attendanceMap[$event->event_id][$dateStr][$index][Attendance::AFTERNOON_TIME_OUT] ?? false),
                            ]);
                        });

                        $totalCheckpoints = count($day->slots ?? []) * 4;
                        $attendedCount = 0;
                        foreach ($day->slots ?? [] as $index => $_) {
                            foreach (Attendance::CHECKPOINTS as $cp) {
                                if ($attendanceMap[$event->event_id][$dateStr][$index][$cp] ?? false) {
                                    $attendedCount++;
                                }
                            }
                        }

                        $status = 'upcoming';
                        if ($dateStr < $today) {
                            $status = $attendedCount >= $totalCheckpoints && $totalCheckpoints > 0 ? 'attended' : ($attendedCount > 0 ? 'partial' : 'absent');
                        } elseif ($dateStr === $today) {
                            $status = $attendedCount > 0 ? 'partial' : 'active';
                        }

                        return [
                            'date'       => $dateStr,
                            'slots'      => $slotsWithStatus->toArray(),
                            'day_status' => $status,
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

        // Map student attendances by event_id, date, slot_index, and checkpoint_key
        $attendanceMap = [];
        if ($student && $student->attendances) {
            foreach ($student->attendances as $attendance) {
                $dateStr = Carbon::parse($attendance->event_date)->format('Y-m-d');
                $key = $attendance->checkpoint_key ?? ($attendance->type === 'in' ? Attendance::MORNING_TIME_IN : Attendance::MORNING_TIME_OUT);
                $attendanceMap[$attendance->event_id][$dateStr][$attendance->slot_index][$key] = true;
            }
        }

        $calendarEvents = Event::with('days')
            ->where($studentEventScope)
            ->get()
            ->map(function ($event) use ($attendanceMap, $today) {
                $schedules = $event->days->isNotEmpty() 
                    ? $event->days->map(function ($day) use ($event, $attendanceMap, $today) {
                        $dateStr = $day->event_date instanceof Carbon ? $day->event_date->format('Y-m-d') : Carbon::parse($day->event_date)->format('Y-m-d');
                        
                        $slotsWithStatus = collect($day->slots ?? [])->map(function ($slot, $index) use ($event, $dateStr, $attendanceMap) {
                            return array_merge($slot, [
                                'slot_index'         => $index,
                                'morning_time_in'    => $attendanceMap[$event->event_id][$dateStr][$index][Attendance::MORNING_TIME_IN] ?? false,
                                'morning_time_out'   => $attendanceMap[$event->event_id][$dateStr][$index][Attendance::MORNING_TIME_OUT] ?? false,
                                'afternoon_time_in'  => $attendanceMap[$event->event_id][$dateStr][$index][Attendance::AFTERNOON_TIME_IN] ?? false,
                                'afternoon_time_out' => $attendanceMap[$event->event_id][$dateStr][$index][Attendance::AFTERNOON_TIME_OUT] ?? false,
                                'checked_in'         => ($attendanceMap[$event->event_id][$dateStr][$index][Attendance::MORNING_TIME_IN] ?? false) || ($attendanceMap[$event->event_id][$dateStr][$index][Attendance::AFTERNOON_TIME_IN] ?? false),
                                'checked_out'        => ($attendanceMap[$event->event_id][$dateStr][$index][Attendance::MORNING_TIME_OUT] ?? false) || ($attendanceMap[$event->event_id][$dateStr][$index][Attendance::AFTERNOON_TIME_OUT] ?? false),
                            ]);
                        });

                        $totalCheckpoints = count($day->slots ?? []) * 4;
                        $attendedCount = 0;
                        foreach ($day->slots ?? [] as $index => $_) {
                            foreach (Attendance::CHECKPOINTS as $cp) {
                                if ($attendanceMap[$event->event_id][$dateStr][$index][$cp] ?? false) {
                                    $attendedCount++;
                                }
                            }
                        }

                        $status = 'upcoming';
                        if ($dateStr < $today) {
                            $status = $attendedCount >= $totalCheckpoints && $totalCheckpoints > 0 ? 'attended' : ($attendedCount > 0 ? 'partial' : 'absent');
                        } elseif ($dateStr === $today) {
                            $status = $attendedCount > 0 ? 'partial' : 'active';
                        }

                        return [
                            'date'       => $dateStr,
                            'slots'      => $slotsWithStatus->toArray(),
                            'day_status' => $status,
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

        return Inertia::render('Calendar', [
            'student'        => $student,
            'calendarEvents' => $calendarEvents,
            'today'          => $today,
        ]);
    }
}