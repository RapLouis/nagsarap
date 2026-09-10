<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Student;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

class StudentManagementController extends Controller
{
    public function index(Request $request): Response
    {
        $search      = $request->input('search');
        $degree      = $request->input('degree');
        $yearSection = $request->input('year_section');
        $status      = $request->input('status');

        // Strip non-alphanumeric characters for flexible student number matching
        $cleanSearch = preg_replace('/[^A-Za-z0-9]/', '', (string) $search);

        $students = Student::query()
            ->when($search, function ($query) use ($search, $cleanSearch) {
                $query->where(function ($q) use ($search, $cleanSearch) {
                    $q->where('student_number', 'like', "%{$search}%")
                      ->orWhere('firstname', 'like', "%{$search}%")
                      ->orWhere('surname', 'like', "%{$search}%")
                      ->orWhere('email', 'like', "%{$search}%");

                    if (!empty($cleanSearch)) {
                        $q->orWhereRaw("REPLACE(student_number, '-', '') LIKE ?", ["%{$cleanSearch}%"]);
                    }
                });
            })
            ->when($degree && $degree !== 'all', function ($query) use ($degree) {
                $query->where('degree', 'like', "%{$degree}%");
            })
            ->when($yearSection && $yearSection !== 'all', function ($query) use ($yearSection) {
                $query->where('year_section', $yearSection);
            })
            ->when($status && $status !== 'all', function ($query) use ($status) {
                $query->where('verification_status', $status);
            })
            ->latest()
            ->paginate(10)
            ->withQueryString();

        // Unique filter options
        $availableDegrees = Student::whereNotNull('degree')
            ->distinct()
            ->pluck('degree')
            ->map(fn($d) => trim(explode('Year / Section:', $d)[0]))
            ->unique()
            ->values();

        $availableSections = Student::whereNotNull('year_section')
            ->distinct()
            ->pluck('year_section')
            ->sort()
            ->values();

        // Renders directly to resources/js/Pages/admin/StudentManagement.tsx
        return Inertia::render('admin/StudentManagement', [
            'students'          => $students,
            'availableDegrees'  => $availableDegrees,
            'availableSections' => $availableSections,
            'filters'           => [
                'search'       => $search ?? '',
                'degree'       => $degree ?? 'all',
                'year_section' => $yearSection ?? 'all',
                'status'       => $status ?? 'all',
            ],
        ]);
    }

    public function destroy(Student $student)
    {
        $student->delete();

        return back()->with('message', 'Student record deleted successfully.');
    }
}