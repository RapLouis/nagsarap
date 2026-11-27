<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Attendance;
use App\Models\Event;
use App\Models\Student;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Inertia\Inertia;

class AnalyticsController extends Controller
{
    // ─────────────────────────────────────────────────────────────────────────
    // GLOBAL SYSTEM ANALYTICS
    // ─────────────────────────────────────────────────────────────────────────

    public function index(Request $request)
    {
        $now = Carbon::now();
        $today = $now->toDateString();

        // ── Dynamic Date Range & Directory Filters ───────────────────────────

        $range = in_array($request->input('range'), ['month', 'semester', '12m'], true)
            ? $request->input('range')
            : '12m';

        $search = trim((string) $request->input('search', ''));

        $status = in_array($request->input('status'), ['all', 'held', 'upcoming'], true)
            ? $request->input('status')
            : 'all';

        $sort = in_array(
            $request->input('sort'),
            ['recent', 'highest_turnout', 'lowest_turnout', 'lowest_confidence'],
            true
        )
            ? $request->input('sort')
            : 'recent';

        $startDate = match ($range) {
            'month' => $now->copy()->startOfMonth(),
            'semester' => $now->copy()->subMonths(5)->startOfMonth(),
            default => $now->copy()->subMonths(11)->startOfMonth(),
        };

        $startDateStr = $startDate->toDateString();

        // ── Current / Previous Month Boundaries ──────────────────────────────

        $thisMonthStart = $now->copy()->startOfMonth();
        $lastMonthStart = $now->copy()->subMonth()->startOfMonth();
        $lastMonthEnd = $now->copy()->subMonth()->endOfMonth();

        // ── Core Counts & Pre-Aggregated Subqueries ──────────────────────────

        $totalStudents = Student::whereNotNull('face_embedding')->count();

        // Subquery: aggregate event_days per event_id first to avoid Cartesian joins
        $daysSubquery = DB::table('event_days')
            ->select(
                'event_id',
                DB::raw('MIN(event_date) as start_date'),
                DB::raw('MAX(event_date) as end_date'),
                DB::raw('COUNT(DISTINCT event_day_id) as total_days')
            )
            ->groupBy('event_id');

        // Subquery: aggregate attendances per event_id within the selected window
        $attendanceSubquery = DB::table('attendances')
            ->select(
                'event_id',
                DB::raw('COUNT(attendance_id) as attended'),
                DB::raw("SUM(CASE WHEN status IN ('success', 'present') THEN 1 ELSE 0 END) as successful"),
                DB::raw('ROUND(AVG(confidence_score), 4) as avg_confidence')
            )
            ->where('logged_at', '>=', $startDate)
            ->groupBy('event_id');

        // Total events overlapping the selected period
        $totalEvents = DB::table('events as e')
            ->joinSub($daysSubquery, 'ed', 'ed.event_id', '=', 'e.event_id')
            ->where('ed.end_date', '>=', $startDateStr)
            ->count();

        // Held events count (events that have started on or before today) for accurate turnout rate
        $heldEventsCount = DB::table('events as e')
            ->joinSub($daysSubquery, 'ed', 'ed.event_id', '=', 'e.event_id')
            ->where('ed.end_date', '>=', $startDateStr)
            ->where('ed.start_date', '<=', $today)
            ->count();

        $attendanceTotals = Attendance::where('logged_at', '>=', $startDate)
            ->selectRaw('COUNT(*) as total')
            ->selectRaw("SUM(CASE WHEN status IN ('success', 'present') THEN 1 ELSE 0 END) as successful")
            ->first();

        $totalAttendances = (int) ($attendanceTotals->total ?? 0);
        $successfulVerifications = (int) ($attendanceTotals->successful ?? 0);

        // ── Global Attendance & Biometric Success Rates ──────────────────────

        $globalAttendanceRate = ($heldEventsCount > 0 && $totalStudents > 0)
            ? min(100, round(($totalAttendances / ($totalStudents * $heldEventsCount)) * 100, 2))
            : 0;

        $biometricSuccessRate = $totalAttendances > 0
            ? round(($successfulVerifications / $totalAttendances) * 100, 2)
            : 0;

        // ── KPI Deltas (Current Month vs. Previous Month) ────────────────────

        $thisMonthStats = Attendance::where('logged_at', '>=', $thisMonthStart)
            ->selectRaw('COUNT(*) as total')
            ->selectRaw("SUM(CASE WHEN status IN ('success', 'present') THEN 1 ELSE 0 END) as successful")
            ->first();

        $lastMonthStats = Attendance::whereBetween('logged_at', [$lastMonthStart, $lastMonthEnd])
            ->selectRaw('COUNT(*) as total')
            ->selectRaw("SUM(CASE WHEN status IN ('success', 'present') THEN 1 ELSE 0 END) as successful")
            ->first();

        $thisMonthAttendances = (int) ($thisMonthStats->total ?? 0);
        $lastMonthAttendances = (int) ($lastMonthStats->total ?? 0);
        $thisMonthSuccess = (int) ($thisMonthStats->successful ?? 0);
        $lastMonthSuccess = (int) ($lastMonthStats->successful ?? 0);

        $thisMonthRate = $thisMonthAttendances > 0
            ? round(($thisMonthSuccess / $thisMonthAttendances) * 100, 2)
            : null;

        $lastMonthRate = $lastMonthAttendances > 0
            ? round(($lastMonthSuccess / $lastMonthAttendances) * 100, 2)
            : null;

        $deltas = [
            'attendances' => $lastMonthAttendances > 0
                ? round((($thisMonthAttendances - $lastMonthAttendances) / $lastMonthAttendances) * 100, 1)
                : null,

            'biometricSuccessRate' => ($thisMonthRate !== null && $lastMonthRate !== null && $lastMonthRate > 0)
                ? round((($thisMonthRate - $lastMonthRate) / $lastMonthRate) * 100, 1)
                : null,
        ];

        // ── Monthly Attendance Trend ─────────────────────────────────────────

        $monthlyTrend = Attendance::select(
                DB::raw("DATE_FORMAT(logged_at, '%b %Y') as month"),
                DB::raw("DATE_FORMAT(logged_at, '%Y-%m') as sort_key"),
                DB::raw('COUNT(*) as total'),
                DB::raw("SUM(CASE WHEN status IN ('success', 'present') THEN 1 ELSE 0 END) as successful"),
                DB::raw('ROUND(AVG(confidence_score), 4) as avg_confidence')
            )
            ->where('logged_at', '>=', $startDate)
            ->groupBy('month', 'sort_key')
            ->orderBy('sort_key')
            ->get()
            ->map(function ($row) {
                $total = (int) $row->total;
                $successful = (int) $row->successful;

                return [
                    'month' => $row->month,
                    'total' => $total,
                    'successful' => $successful,
                    'pass_rate' => $total > 0 ? round(($successful / $total) * 100, 1) : 0,
                    'avg_confidence' => (float) ($row->avg_confidence ?? 0),
                ];
            });

        // ── Base Event Analytics Query (Safe, Non-Multiplying Joins) ─────────

        $baseEventQuery = DB::table('events as e')
            ->joinSub($daysSubquery, 'ed', 'ed.event_id', '=', 'e.event_id')
            ->leftJoinSub($attendanceSubquery, 'att', 'att.event_id', '=', 'e.event_id')
            ->where('ed.end_date', '>=', $startDateStr)
            ->select(
                'e.event_id as id',
                'e.title as event',
                'e.location',
                'ed.start_date',
                'ed.end_date',
                'ed.total_days',
                DB::raw('COALESCE(att.attended, 0) as attended'),
                DB::raw('COALESCE(att.successful, 0) as successful'),
                DB::raw('COALESCE(att.avg_confidence, 0) as avg_confidence')
            );

        $formatEventRow = function ($row) use ($today) {
            $totalDays = (int) $row->total_days;
            $attended = (int) $row->attended;
            $successful = (int) $row->successful;
            $isUpcoming = $row->start_date > $today && $attended === 0;

            return [
                'id' => (int) $row->id,
                'event' => $row->event,
                'location' => $row->location,
                'date' => $totalDays > 1
                    ? "{$row->start_date} to {$row->end_date}"
                    : $row->start_date,
                'start_date' => $row->start_date,
                'end_date' => $row->end_date,
                'total_days' => $totalDays,
                'is_upcoming' => $isUpcoming,
                'attended' => $attended,
                'successful' => $successful,
                'pass_rate' => $attended > 0 ? round(($successful / $attended) * 100, 1) : 0,
                'avg_confidence' => $attended > 0 ? round((float) $row->avg_confidence, 4) : 0,
            ];
        };

        // ── Top 8 Ranked Events (For Scale-Safe Bar Chart) ───────────────────

        $highestTurnoutEvents = (clone $baseEventQuery)
            ->where('ed.start_date', '<=', $today)
            ->whereRaw('COALESCE(att.attended, 0) > 0')
            ->orderByDesc('attended')
            ->orderByDesc('ed.start_date')
            ->limit(8)
            ->get()
            ->map($formatEventRow)
            ->values();

        $lowestTurnoutEvents = (clone $baseEventQuery)
            ->where('ed.start_date', '<=', $today)
            ->whereRaw('COALESCE(att.attended, 0) > 0')
            ->orderBy('attended')
            ->orderByDesc('ed.start_date')
            ->limit(8)
            ->get()
            ->map($formatEventRow)
            ->values();

        // ── Paginated Event Directory (Handles 1,000+ Events) ────────────────

        $directoryQuery = clone $baseEventQuery;

        if ($search !== '') {
            $directoryQuery->where(function ($q) use ($search) {
                $q->where('e.title', 'like', "%{$search}%")
                  ->orWhere('e.location', 'like', "%{$search}%");
            });
        }

        if ($status === 'held') {
            $directoryQuery->where('ed.start_date', '<=', $today);
        } elseif ($status === 'upcoming') {
            $directoryQuery->where('ed.start_date', '>', $today);
        }

        match ($sort) {
            'highest_turnout' => $directoryQuery
                ->orderByDesc('attended')
                ->orderByDesc('ed.start_date'),
            'lowest_turnout' => $directoryQuery
                ->where('ed.start_date', '<=', $today)
                ->orderBy('attended')
                ->orderByDesc('ed.start_date'),
            'lowest_confidence' => $directoryQuery
                ->whereRaw('COALESCE(att.attended, 0) > 0')
                ->orderBy('avg_confidence')
                ->orderByDesc('ed.start_date'),
            default => $directoryQuery
                ->orderByDesc('ed.start_date')
                ->orderByDesc('e.event_id'),
        };

        // Force relative path so ngrok / reverse proxies never emit localhost URLs
        $eventDirectory = $directoryQuery
            ->paginate(15)
            ->withPath($request->getPathInfo())
            ->withQueryString()
            ->through($formatEventRow);

        // ── Hour-of-Day Distribution ─────────────────────────────────────────

        $hourlyDistribution = Attendance::select(
                DB::raw('HOUR(logged_at) as hour'),
                DB::raw('COUNT(*) as count')
            )
            ->whereIn('status', ['success', 'present'])
            ->where('logged_at', '>=', $startDate)
            ->groupBy(DB::raw('HOUR(logged_at)'))
            ->orderBy('hour')
            ->get()
            ->map(fn ($row) => [
                'hour' => (int) $row->hour,
                'label' => Carbon::createFromTime((int) $row->hour)->format('g A'),
                'count' => (int) $row->count,
            ]);

        // ── Course / Degree Breakdown ────────────────────────────────────────

        $courseBreakdown = Student::select(
                DB::raw("COALESCE(degree, 'Unspecified') as course"),
                DB::raw('COUNT(*) as total'),
                DB::raw('SUM(CASE WHEN face_embedding IS NOT NULL THEN 1 ELSE 0 END) as enrolled_biometric')
            )
            ->groupBy(DB::raw("COALESCE(degree, 'Unspecified')"))
            ->orderByDesc('total')
            ->get()
            ->map(fn ($row) => [
                'course' => $row->course,
                'total' => (int) $row->total,
                'enrolled_biometric' => (int) $row->enrolled_biometric,
            ]);

        // ── Return Global Analytics ──────────────────────────────────────────

        return Inertia::render('admin/analytics/index', [
            'metrics' => [
                'totalStudents' => $totalStudents,
                'totalEvents' => $totalEvents,
                'heldEvents' => $heldEventsCount,
                'globalAttendanceRate' => $globalAttendanceRate,
                'biometricSuccessRate' => $biometricSuccessRate,
            ],

            'deltas' => $deltas,

            'courseBreakdown' => $courseBreakdown,

            'monthlyTrend' => $monthlyTrend,

            'topEvents' => [
                'highestTurnout' => $highestTurnoutEvents,
                'lowestTurnout' => $lowestTurnoutEvents,
            ],

            'eventDirectory' => $eventDirectory,

            // Backwards-compatible fallback
            'eventSummary' => $highestTurnoutEvents,

            'hourlyDistribution' => $hourlyDistribution,

            'filters' => [
                'range' => $range,
                'search' => $search,
                'status' => $status,
                'sort' => $sort,
            ],
        ]);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // PER-EVENT DRILL-DOWN ANALYTICS
    // ─────────────────────────────────────────────────────────────────────────

    public function showEvent(Event $event)
    {
        $event->load(['days' => fn ($q) => $q->orderBy('event_date')]);

        // ── Event-level Counts (Single Aggregate Query) ──────────────────────

        $eventTotals = Attendance::where('event_id', $event->event_id)
            ->selectRaw('COUNT(*) as total')
            ->selectRaw("SUM(CASE WHEN status IN ('success', 'present') THEN 1 ELSE 0 END) as successful")
            ->selectRaw("AVG(CASE WHEN status IN ('success', 'present') THEN confidence_score ELSE NULL END) as avg_confidence")
            ->first();

        $totalAttendees = (int) ($eventTotals->total ?? 0);
        $successfulCheckins = (int) ($eventTotals->successful ?? 0);
        $avgConfidence = (float) ($eventTotals->avg_confidence ?? 0);

        $eventSuccessRate = $totalAttendees > 0
            ? round(($successfulCheckins / $totalAttendees) * 100, 2)
            : 0;

        // ── Per-Day Breakdown (Single Grouped Query — No N+1 Loop) ───────────

        $dailyStatsByDate = Attendance::where('event_id', $event->event_id)
            ->select(
                DB::raw('DATE(logged_at) as log_date'),
                DB::raw('COUNT(*) as attendees'),
                DB::raw("SUM(CASE WHEN status IN ('success', 'present') THEN 1 ELSE 0 END) as successful")
            )
            ->groupBy(DB::raw('DATE(logged_at)'))
            ->get()
            ->keyBy('log_date');

        $dailyBreakdown = $event->days->map(function ($day) use ($dailyStatsByDate) {
            $dateStr = $day->event_date instanceof Carbon
                ? $day->event_date->format('Y-m-d')
                : Carbon::parse($day->event_date)->format('Y-m-d');

            $stats = $dailyStatsByDate->get($dateStr);

            return [
                'date' => $dateStr,
                'slots' => $day->slots,
                'attendees' => (int) ($stats->attendees ?? 0),
                'successful' => (int) ($stats->successful ?? 0),
            ];
        });

        // ── Department / Degree Breakdown (Pre-Aggregated Per Student) ───────

        $studentEventStats = DB::table('attendances')
            ->select(
                'student_id',
                DB::raw('COUNT(*) as checkins'),
                DB::raw("MAX(CASE WHEN status IN ('success', 'present') THEN 1 ELSE 0 END) as has_verified"),
                DB::raw('AVG(confidence_score) as avg_confidence')
            )
            ->where('event_id', $event->event_id)
            ->groupBy('student_id');

        $departmentBreakdown = DB::table('students as s')
            ->leftJoinSub($studentEventStats, 'sa', 'sa.student_id', '=', 's.student_id')
            ->select(
                DB::raw("COALESCE(s.degree, 'Unspecified') as course"),
                DB::raw('COUNT(DISTINCT s.student_id) as total'),
                DB::raw('SUM(CASE WHEN sa.student_id IS NOT NULL THEN 1 ELSE 0 END) as checked_in'),
                DB::raw('SUM(COALESCE(sa.has_verified, 0)) as successful'),
                DB::raw('SUM(CASE WHEN sa.student_id IS NULL THEN 1 ELSE 0 END) as no_show'),
                DB::raw('ROUND(AVG(sa.avg_confidence), 4) as avg_confidence')
            )
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
            ->join('students as s', 's.student_id', '=', 'a.student_id')
            ->select(
                's.student_id',
                DB::raw("CONCAT(s.firstname, ' ', s.surname) as name"),
                's.degree as course',
                'a.status',
                'a.confidence_score',
                'a.logged_at'
            )
            ->where('a.event_id', $event->event_id)
            ->orderBy('a.logged_at')
            ->get()
            ->map(fn ($row) => [
                'student_id' => $row->student_id,
                'name' => $row->name,
                'course' => $row->course ?? 'Unspecified',
                'status' => $row->status,
                'confidence_score' => round((float) $row->confidence_score, 4),
                'logged_at' => Carbon::parse($row->logged_at)->format('Y-m-d H:i:s'),
            ]);

        // ── Flagged Low-Confidence Check-ins (Confidence < 0.70) ─────────────

        $flaggedQuery = DB::table('attendances as a')
            ->join('students as s', 's.student_id', '=', 'a.student_id')
            ->where('a.event_id', $event->event_id)
            ->where('a.confidence_score', '<', 0.70);

        $flaggedCount = (clone $flaggedQuery)->count();

        $flaggedRoster = $flaggedQuery
            ->select(
                's.student_id',
                DB::raw("CONCAT(s.firstname, ' ', s.surname) as name"),
                's.degree as course',
                'a.status',
                'a.confidence_score',
                'a.logged_at'
            )
            ->orderBy('a.confidence_score', 'asc')
            ->limit(50)
            ->get()
            ->map(fn ($row) => [
                'student_id' => $row->student_id,
                'name' => $row->name,
                'course' => $row->course ?? 'Unspecified',
                'status' => $row->status,
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
                'created_at' => $event->created_at?->toIso8601String(),
                'schedules' => $event->days->map(fn ($d) => [
                    'date' => $d->event_date instanceof Carbon
                        ? $d->event_date->format('Y-m-d')
                        : $d->event_date,
                    'slots' => $d->slots,
                ]),
            ],

            'analytics' => [
                'totalAttendees' => $totalAttendees,
                'successfulCheckins' => $successfulCheckins,
                'eventSuccessRate' => $eventSuccessRate,
                'avgConfidence' => round($avgConfidence, 4),
                'dailyBreakdown' => $dailyBreakdown,
                'departmentBreakdown' => $departmentBreakdown,
                'checkinTimeline' => $checkinTimeline,
                'roster' => $roster,
                'flaggedRoster' => $flaggedRoster,
                'flaggedCount' => $flaggedCount,
            ],
        ]);
    }
}