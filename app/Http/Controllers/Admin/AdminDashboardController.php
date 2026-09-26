<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Student;
use App\Models\Event;
use App\Models\Attendance;
use Inertia\Inertia;
use Inertia\Response;

class AdminDashboardController extends Controller
{
    public function index(): Response
    {
        $totalStudents = Student::count();

        $rows = Student::select('degree', 'year_section')
            ->whereNotNull('degree')
            ->get();

        $degrees = [];

        foreach ($rows as $row) {
            [$degree, $section] = $this->splitDegreeAndSection($row->degree, $row->year_section);

            if ($degree === '') {
                continue;
            }

            // Initialize degree grouping
            $degrees[$degree] ??= [
                'total' => 0,
                'sections' => [],
            ];

            $degrees[$degree]['total']++;

            if ($section === '') {
                continue;
            }

            // Map counts directly under section keys (e.g., "1 - A", "4A")
            $degrees[$degree]['sections'][$section] = ($degrees[$degree]['sections'][$section] ?? 0) + 1;
        }

        // --- Dynamic Metrics & System Data ---
        $today = now()->toDateString();
        
        // Calculate today's attendance rate
        $expectedToday = Attendance::whereDate('created_at', $today)->count();
        $presentToday = Attendance::whereDate('created_at', $today)
            ->whereIn('status', ['present', 'verified'])
            ->count();
        
        $attendanceRate = $expectedToday > 0 ? round(($presentToday / $expectedToday) * 100, 1) : 0;

        // Fetch ongoing active event with attendance count
        $ongoingEvent = Event::withCount(['attendances' => function ($query) {
                $query->whereIn('status', ['present', 'verified']);
            }])
            ->where('is_active', true)
            ->first();

        // Event counts using the child event_days table relationship
        $activeEventsCount = Event::whereHas('days', function ($query) use ($today) {
            $query->where('event_date', '>=', $today);
        })->count();
        
        $pendingClearancesCount = 0; // Stubbed until clearance system is built

        // Recent activity feed based on latest check-ins
        $recentActivities = Attendance::with(['student', 'event'])
            ->latest('logged_at')
            ->take(4)
            ->get()
            ->map(fn($att) => [
                'text' => "Student {$att->student?->student_number} checked in for {$att->event?->title}",
                'time' => $att->logged_at ? \Carbon\Carbon::parse($att->logged_at)->diffForHumans() : 'Just now',
            ]);

        return Inertia::render('admin/admindashboard', [
            'totalStudents'          => $totalStudents,
            'degrees'                => $degrees,
            'activeEventsCount'      => $activeEventsCount,
            'todayAttendanceRate'    => $attendanceRate,
            'pendingClearancesCount' => $pendingClearancesCount,
            'ongoingEvent'           => $ongoingEvent,
            'recentActivities'       => $recentActivities,
        ]);
    }

    /**
     * Normalizes a raw (degree, year_section) pair.
     */
    private function splitDegreeAndSection(string $rawDegree, ?string $rawSection): array
    {
        $degree = trim($rawDegree);
        $section = trim((string) $rawSection);

        if ($section === '' && str_contains($degree, 'Year / Section:')) {
            [$degreePart, $sectionPart] = explode('Year / Section:', $degree, 2);
            $degree = trim($degreePart);
            $section = trim($sectionPart);
        }

        // Collapse internal whitespace
        $degree = preg_replace('/\s+/', ' ', $degree);
        $section = preg_replace('/\s+/', ' ', $section);

        return [$degree, $section];
    }
}