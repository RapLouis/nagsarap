<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Student;
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

        return Inertia::render('admin/admindashboard', [
            'totalStudents' => $totalStudents,
            'degrees'       => $degrees,
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