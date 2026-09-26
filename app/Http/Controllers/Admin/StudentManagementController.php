<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\UpdateStudentRequest;
use App\Models\Student;
use Illuminate\Http\Request;
use Illuminate\Http\RedirectResponse;
use Inertia\Inertia;
use Inertia\Response;

class StudentManagementController extends Controller
{
    /** Columns a request is allowed to sort by. Never build ORDER BY from raw input. */
    private const SORTABLE_COLUMNS = [
        'student_number',
        'firstname',
        'surname',
        'email',
        'degree',
        'year_section',
        'verification_status',
        'created_at',
    ];

    public function index(Request $request): Response
    {
        $search      = $request->input('search');
        $degree      = $request->input('degree');
        $yearSection = $request->input('year_section');
        $status      = $request->input('status');

        $sort      = in_array($request->input('sort'), self::SORTABLE_COLUMNS, true)
            ? $request->input('sort')
            : 'created_at';
        $direction = $request->input('direction') === 'asc' ? 'asc' : 'desc';

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
            ->orderBy($sort, $direction)
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

        $stats = [
            'total' => Student::count(),
            'verified' => Student::where('verification_status', 'verified')->count(),
            'pending' => Student::where('verification_status', '!=', 'verified')->count(),
        ];

        // Renders directly to resources/js/Pages/admin/StudentManagement.tsx
        return Inertia::render('admin/StudentManagement', [
            'students'          => $students,
            'availableDegrees'  => $availableDegrees,
            'availableSections' => $availableSections,
            'stats'             => $stats,
            'filters'           => [
                'search'       => $search ?? '',
                'degree'       => $degree ?? 'all',
                'year_section' => $yearSection ?? 'all',
                'status'       => $status ?? 'all',
                'sort'         => $sort,
                'direction'    => $direction,
            ],
        ]);
    }

    public function update(UpdateStudentRequest $request, Student $student): RedirectResponse
    {
        $student->update($request->validated());

        return back()->with('message', "Student {$student->firstname} {$student->surname} was updated successfully.");
    }

    /** Manually mark a student as verified, bypassing face verification. */
    public function verify(Student $student): RedirectResponse
    {
        $student->update(['verification_status' => 'verified']);

        return back()->with('message', "Student {$student->firstname} {$student->surname} was marked as verified.");
    }

    /** Send a verified (or otherwise flagged) student back to face verification. */
    public function reject(Student $student): RedirectResponse
    {
        $student->update(['verification_status' => 'pending_face_verification']);

        return back()->with('message', "Student {$student->firstname} {$student->surname} was sent back to pending verification.");
    }

    public function destroy(Student $student): RedirectResponse
    {
        // Delete the associated user account if the relationship exists
        if ($student->user) {
            $student->user->delete();
        }

        // Delete the student profile record
        $student->delete();

        return back()->with('message', 'Student and user account deleted successfully.');
    }
}