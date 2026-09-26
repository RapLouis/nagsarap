<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Student;
use App\Models\Event;
use App\Models\Attendance;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Carbon;
use Inertia\Inertia;

class AnalyticsController extends Controller
{
    // ─────────────────────────────────────────────────────────────────────────
    // GLOBAL SYSTEM ANALYTICS
    // ─────────────────────────────────────────────────────────────────────────

    public function index(Request $request)
    {
        $now = Carbon::now();

        // ── Dynamic Date Range Filter ────────────────────────────────────────

        $range = $request->input('range', '12m');

        $startDate = match ($range) {
            'month' => $now->copy()->startOfMonth(),

            'semester' => $now->copy()
                ->subMonths(5)
                ->startOfMonth(),

            default => $now->copy()
                ->subMonths(11)
                ->startOfMonth(),
        };

        // ── Current / Previous Month ─────────────────────────────────────────

        $thisMonthStart = $now->copy()->startOfMonth();

        $lastMonthStart = $now->copy()
            ->subMonth()
            ->startOfMonth();

        $lastMonthEnd = $now->copy()
            ->subMonth()
            ->endOfMonth();

        // ── Core Counts ──────────────────────────────────────────────────────

        $totalStudents = Student::whereNotNull('face_embedding')->count();

        // Updated to query through the child event_days table
        $totalEvents = Event::whereHas('days', function ($query) use ($startDate) {
            $query->where('event_date', '>=', $startDate);
        })->count();

        $totalAttendances = Attendance::where(
            'logged_at',
            '>=',
            $startDate
        )->count();

        // ── Global Attendance Rate ───────────────────────────────────────────

        $globalAttendanceRate = (
            $totalEvents > 0 &&
            $totalStudents > 0
        )
            ? round(
                ($totalAttendances / ($totalStudents * $totalEvents)) * 100,
                2
            )
            : 0;

        // ── Biometric Success Rate ───────────────────────────────────────────

        $successfulVerifications = Attendance::where(
                'logged_at',
                '>=',
                $startDate
            )
            ->whereIn('status', ['success', 'present'])
            ->count();

        $biometricSuccessRate = $totalAttendances > 0
            ? round(
                ($successfulVerifications / $totalAttendances) * 100,
                2
            )
            : 100;

        // ── KPI Deltas ───────────────────────────────────────────────────────
        // Current month compared with previous month

        $thisMonthAttendances = Attendance::where(
            'logged_at',
            '>=',
            $thisMonthStart
        )->count();

        $lastMonthAttendances = Attendance::whereBetween(
            'logged_at',
            [$lastMonthStart, $lastMonthEnd]
        )->count();

        $thisMonthSuccess = Attendance::whereIn(
                'status',
                ['success', 'present']
            )
            ->where('logged_at', '>=', $thisMonthStart)
            ->count();

        $lastMonthSuccess = Attendance::whereIn(
                'status',
                ['success', 'present']
            )
            ->whereBetween(
                'logged_at',
                [$lastMonthStart, $lastMonthEnd]
            )
            ->count();

        $thisMonthRate = $thisMonthAttendances > 0
            ? round(
                ($thisMonthSuccess / $thisMonthAttendances) * 100,
                2
            )
            : 100;

        $lastMonthRate = $lastMonthAttendances > 0
            ? round(
                ($lastMonthSuccess / $lastMonthAttendances) * 100,
                2
            )
            : 100;

        $deltas = [
            'attendances' => $lastMonthAttendances > 0
                ? round(
                    (
                        ($thisMonthAttendances - $lastMonthAttendances)
                        / $lastMonthAttendances
                    ) * 100,
                    1
                )
                : null,

            'biometricSuccessRate' => $lastMonthRate > 0
                ? round(
                    (
                        ($thisMonthRate - $lastMonthRate)
                        / $lastMonthRate
                    ) * 100,
                    1
                )
                : null,
        ];

        // ── Monthly Attendance Trend ─────────────────────────────────────────

        $monthlyTrend = Attendance::select(
                DB::raw(
                    "DATE_FORMAT(logged_at, '%b %Y') as month"
                ),
                DB::raw(
                    "DATE_FORMAT(logged_at, '%Y-%m') as sort_key"
                ),
                DB::raw('COUNT(*) as total'),
                DB::raw(
                    "SUM(
                        CASE
                            WHEN status IN ('success', 'present') THEN 1
                            ELSE 0
                        END
                    ) as successful"
                ),
                DB::raw(
                    'ROUND(AVG(confidence_score), 4) as avg_confidence'
                )
            )
            ->where('logged_at', '>=', $startDate)
            ->groupBy('month', 'sort_key')
            ->orderBy('sort_key')
            ->get()
            ->map(fn ($row) => [
                'month' => $row->month,
                'total' => (int) $row->total,
                'successful' => (int) $row->successful,
                'avg_confidence' => (float) (
                    $row->avg_confidence ?? 0
                ),
            ]);

        // ── Per-Event Summary (Joined with event_days) ────────────────────────

        $eventSummary = Event::select(
                'events.event_id',
                'events.title',
                DB::raw('MIN(ed.event_date) as start_date'),
                DB::raw('MAX(ed.event_date) as end_date'),
                DB::raw('COUNT(DISTINCT ed.event_day_id) as total_days'),
                DB::raw('COUNT(a.attendance_id) as attended'),
                DB::raw(
                    "SUM(
                        CASE
                            WHEN a.status IN ('success', 'present') THEN 1
                            ELSE 0
                        END
                    ) as successful"
                ),
                DB::raw(
                    'ROUND(AVG(a.confidence_score), 4) as avg_confidence'
                )
            )
            ->join('event_days as ed', 'ed.event_id', '=', 'events.event_id')
            ->leftJoin(
                'attendances as a',
                'a.event_id',
                '=',
                'events.event_id'
            )
            ->where(
                'ed.event_date',
                '>=',
                $startDate
            )
            ->groupBy(
                'events.event_id',
                'events.title'
            )
            ->orderByDesc('start_date')
            ->limit(20)
            ->get()
            ->map(fn ($row) => [
                'id' => $row->event_id,
                'event' => $row->title,
                'date' => $row->total_days > 1 
                    ? "{$row->start_date} to {$row->end_date}" 
                    : $row->start_date,
                'attended' => (int) $row->attended,
                'successful' => (int) $row->successful,
                'avg_confidence' => (float) (
                    $row->avg_confidence ?? 0
                ),
            ]);

        // ── Hour-of-Day Distribution ─────────────────────────────────────────

        $hourlyDistribution = Attendance::select(
                DB::raw('HOUR(logged_at) as hour'),
                DB::raw('COUNT(*) as count')
            )
            ->whereIn('status', ['success', 'present'])
            ->where('logged_at', '>=', $startDate)
            ->groupBy(
                DB::raw('HOUR(logged_at)')
            )
            ->orderBy('hour')
            ->get()
            ->map(fn ($row) => [
                'hour' => (int) $row->hour,
                'label' => Carbon::createFromTime(
                    $row->hour
                )->format('g A'),
                'count' => (int) $row->count,
            ]);

        // ── Course / Degree Breakdown ────────────────────────────────────────

        $courseBreakdown = Student::select(
                'degree as course',
                DB::raw('count(*) as total')
            )
            ->groupBy('degree')
            ->orderByDesc('total')
            ->get()
            ->map(fn ($row) => [
                'course' => $row->course ?? 'Unspecified',
                'total' => (int) $row->total,
            ]);

        // ── Return Global Analytics ──────────────────────────────────────────

        return Inertia::render('admin/analytics/index', [
            'metrics' => [
                'totalStudents' => $totalStudents,
                'totalEvents' => $totalEvents,
                'globalAttendanceRate' => $globalAttendanceRate,
                'biometricSuccessRate' => $biometricSuccessRate,
            ],

            'deltas' => $deltas,

            'courseBreakdown' => $courseBreakdown,

            'monthlyTrend' => $monthlyTrend,

            'eventSummary' => $eventSummary,

            'hourlyDistribution' => $hourlyDistribution,

            'filters' => [
                'range' => $range,
            ],
        ]);
    }


    // ─────────────────────────────────────────────────────────────────────────
    // PER-EVENT DRILL-DOWN ANALYTICS
    // ─────────────────────────────────────────────────────────────────────────

    public function showEvent(Event $event)
    {
        // Eager-load child days relationship
        $event->load('days');

        // ── Event-level Counts ────────────────────────────────────────────────

        $totalAttendees = Attendance::where(
            'event_id',
            $event->event_id
        )->count();

        $successfulCheckins = Attendance::where(
                'event_id',
                $event->event_id
            )
            ->whereIn('status', ['success', 'present'])
            ->count();

        $avgConfidence = Attendance::where(
                'event_id',
                $event->event_id
            )
            ->whereIn('status', ['success', 'present'])
            ->avg('confidence_score');

        $eventSuccessRate = $totalAttendees > 0
            ? round(
                ($successfulCheckins / $totalAttendees) * 100,
                2
            )
            : 0;

        // ── Per-Day Breakdown (Multi-Day Support) ─────────────────────────────

        $dailyBreakdown = $event->days->map(function ($day) use ($event) {
            $dateStr = $day->event_date instanceof Carbon 
                ? $day->event_date->format('Y-m-d') 
                : Carbon::parse($day->event_date)->format('Y-m-d');

            $attendeesCount = Attendance::where('event_id', $event->event_id)
                ->whereDate('logged_at', $dateStr)
                ->count();

            $successfulCount = Attendance::where('event_id', $event->event_id)
                ->whereDate('logged_at', $dateStr)
                ->whereIn('status', ['success', 'present'])
                ->count();

            return [
                'date' => $dateStr,
                'slots' => $day->slots, // JSON array of time slots for this specific day
                'attendees' => $attendeesCount,
                'successful' => $successfulCount,
            ];
        });

        // ── Department / Degree Breakdown (With Registrants vs Checked In) ────

        $departmentBreakdown = DB::table('students as s')
            ->select(
                DB::raw("COALESCE(s.degree, 'Unspecified') as course"),
                DB::raw('COUNT(s.student_id) as total'),
                DB::raw("SUM(CASE WHEN a.attendance_id IS NOT NULL THEN 1 ELSE 0 END) as checked_in"),
                DB::raw("SUM(CASE WHEN a.attendance_id IS NOT NULL AND a.status IN ('success', 'present') THEN 1 ELSE 0 END) as successful"),
                DB::raw("SUM(CASE WHEN a.attendance_id IS NULL THEN 1 ELSE 0 END) as no_show"),
                DB::raw('ROUND(AVG(a.confidence_score), 4) as avg_confidence')
            )
            ->leftJoin('attendances as a', function($join) use ($event) {
                $join->on('s.student_id', '=', 'a.student_id')
                     ->where('a.event_id', '=', $event->event_id);
            })
            ->groupBy(DB::raw("COALESCE(s.degree, 'Unspecified')"))
            ->orderByDesc('total')
            ->get()
            ->map(fn ($row) => [
                'course' => $row->course,
                'total' => (int) $row->total,
                'checkedIn' => (int) $row->checked_in,
                'successful' => (int) $row->successful,
                'noShow' => (int) $row->no_show,
                'avg_confidence' => (float) ($row->avg_confidence ?? 0),
            ]);

        // ── Check-in Timeline (Cumulative Area Pattern) ───────────────────────

        $rawTimeline = Attendance::select(
                DB::raw('DATE_FORMAT(logged_at, "%h:%i %p") as label'),
                DB::raw('MIN(logged_at) as sort_time'),
                DB::raw('COUNT(*) as count'),
                DB::raw("SUM(CASE WHEN status IN ('success', 'present') THEN 1 ELSE 0 END) as successful")
            )
            ->where('event_id', $event->event_id)
            ->groupBy('label')
            ->orderBy('sort_time')
            ->get();

        $runningTotal = 0;
        $checkinTimeline = $rawTimeline->map(function ($row) use (&$runningTotal) {
            $runningTotal += (int) $row->count;
            return [
                'label' => $row->label,
                'count' => (int) $row->count,
                'successful' => (int) $row->successful,
                'cumulative' => $runningTotal,
            ];
        });

        // ── Student Attendance Roster ─────────────────────────────────────────

        $roster = DB::table('attendances as a')
            ->join(
                'students as s',
                's.student_id',
                '=',
                'a.student_id'
            )
            ->select(
                's.student_id',
                DB::raw(
                    "CONCAT(
                        s.firstname,
                        ' ',
                        s.surname
                    ) as name"
                ),
                's.degree as course',
                'a.status',
                'a.confidence_score',
                'a.logged_at'
            )
            ->where(
                'a.event_id',
                $event->event_id
            )
            ->orderBy('a.logged_at')
            ->get()
            ->map(fn ($row) => [
                'student_id' => $row->student_id,
                'name' => $row->name,
                'course' => $row->course ?? 'Unspecified',
                'status' => $row->status,
                'confidence_score' => round(
                    (float) $row->confidence_score,
                    4
                ),
                'logged_at' => Carbon::parse(
                    $row->logged_at
                )->format('Y-m-d H:i:s'),
            ]);

        // ── Flagged Low-Confidence Check-ins (e.g. Confidence < 70% or 0.70) ──

        $flaggedRoster = DB::table('attendances as a')
            ->join('students as s', 's.student_id', '=', 'a.student_id')
            ->select(
                's.student_id',
                DB::raw("CONCAT(s.firstname, ' ', s.surname) as name"),
                's.degree as course',
                'a.confidence_score',
                'a.logged_at'
            )
            ->where('a.event_id', $event->event_id)
            ->where('a.confidence_score', '<', 0.70)
            ->orderBy('a.confidence_score', 'asc')
            ->limit(5)
            ->get()
            ->map(fn ($row) => [
                'student_id' => $row->student_id,
                'name' => $row->name,
                'course' => $row->course ?? 'Unspecified',
                'confidence_score' => round((float) $row->confidence_score, 4),
                'logged_at' => Carbon::parse($row->logged_at)->format('Y-m-d H:i:s'),
            ]);

        // ── Return Event Analytics ────────────────────────────────────────────

        return Inertia::render('admin/analytics/eventshow', [
            'event' => [
                'id' => $event->event_id,
                'title' => $event->title,
                'description' => $event->description,
                'location' => $event->location,
                'schedules' => $event->days->map(fn ($d) => [
                    'date' => $d->event_date instanceof Carbon ? $d->event_date->format('Y-m-d') : $d->event_date,
                    'slots' => $d->slots,
                ]),
            ],

            'analytics' => [
                'totalAttendees' => $totalAttendees,
                'successfulCheckins' => $successfulCheckins,
                'eventSuccessRate' => $eventSuccessRate,
                'avgConfidence' => round(
                    (float) ($avgConfidence ?? 0),
                    4
                ),
                'dailyBreakdown' => $dailyBreakdown, // Day-by-day stats & slots
                'departmentBreakdown' => $departmentBreakdown,
                'checkinTimeline' => $checkinTimeline,
                'roster' => $roster,
                'flaggedRoster' => $flaggedRoster,
            ],
        ]);
    }
}