<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Student;
use App\Models\Event;
use App\Models\Attendance;
use Inertia\Inertia;
use Inertia\Response;
use Carbon\Carbon;

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

            $degrees[$degree] ??= [
                'total' => 0,
                'sections' => [],
            ];

            $degrees[$degree]['total']++;

            if ($section === '') {
                continue;
            }

            $degrees[$degree]['sections'][$section] = ($degrees[$degree]['sections'][$section] ?? 0) + 1;
        }

        $today = now()->toDateString();
        
        // Calculate today's attendance rate
        $expectedToday = Attendance::whereDate('created_at', $today)->count();
        $presentToday = Attendance::whereDate('created_at', $today)
            ->whereIn('status', ['present', 'verified'])
            ->count();
        
        $attendanceRate = $expectedToday > 0 ? round(($presentToday / $expectedToday) * 100, 1) : 0;

        // Fetch ALL ongoing active events for today with telemetry data
        $ongoingEvents = Event::withCount(['attendances' => function ($query) {
                $query->whereIn('status', ['present', 'verified']);
            }])
            ->with(['attendances' => function ($query) use ($today) {
                $query->whereDate('created_at', $today);
            }])
            ->where('is_active', true)
            ->where(function ($q) use ($today) {
                $q->whereDate('event_date', $today)
                  ->orWhereHas('days', function ($sub) use ($today) {
                      $sub->whereDate('event_date', $today);
                  });
            })
            ->get()
            ->map(function ($event) {
                $attendances = $event->attendances;
                $avgConfidence = $attendances->count() > 0 
                    ? round($attendances->avg('confidence_score') * 100, 1) 
                    : 98.4; // Default baseline mockup if no logs yet

                return [
                    'event_id' => $event->event_id,
                    'title' => $event->title,
                    'location' => $event->location ?? 'Location TBA',
                    'start_time' => '08:00 AM',
                    'attendances_count' => $event->attendances_count,
                    'is_geofenced' => $event->is_geofenced,
                    'radius_meters' => $event->radius_meters,
                    'avg_confidence' => $avgConfidence,
                ];
            });

        $activeEventsCount = Event::whereHas('days', function ($query) use ($today) {
            $query->where('event_date', '>=', $today);
        })->count();
        
        $pendingClearancesCount = 0; 
        $pendingClearancesList = [];

        $recentActivities = Attendance::with(['student', 'event'])
            ->latest('logged_at')
            ->take(6)
            ->get()
            ->map(fn($att) => [
                'text' => "Student {$att->student?->student_number} checked in for {$att->event?->title}",
                'time' => $att->logged_at ? Carbon::parse($att->logged_at)->diffForHumans() : 'Just now',
            ]);

        return Inertia::render('admin/admindashboard', [
            'totalStudents'            => $totalStudents,
            'degrees'                  => $degrees,
            'activeEventsCount'        => $activeEventsCount,
            'todayAttendanceRate'      => $attendanceRate,
            'pendingClearancesCount'   => $pendingClearancesCount,
            'pendingClearancesList'    => $pendingClearancesList,
            'ongoingEvents'            => $ongoingEvents,
            'recentActivities'         => $recentActivities,
        ]);
    }

    private function splitDegreeAndSection(string $rawDegree, ?string $rawSection): array
    {
        $degree = trim($rawDegree);
        $section = trim((string) $rawSection);

        if ($section === '' && str_contains($degree, 'Year / Section:')) {
            [$degreePart, $sectionPart] = explode('Year / Section:', $degree, 2);
            $degree = trim($degreePart);
            $section = trim($sectionPart);
        }

        $degree = preg_replace('/\s+/', ' ', $degree);
        $section = preg_replace('/\s+/', ' ', $section);

        return [$degree, $section];
    }
}