<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller; // <-- Add this import
use App\Models\Event;
use App\Models\Student;
use App\Models\StudentClearance;
use App\Models\Attendance;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Inertia\Inertia;
use Inertia\Response;

class ClearanceController extends Controller
{
    public function index(Request $request): Response
    {
        $search = $request->input('search');
        $selectedEventId = $request->input('event_id');
        $statusFilter = $request->input('status', 'all');

        $events = Event::orderBy('event_date', 'desc')->get();
        $currentEvent = $events->firstWhere('event_id', $selectedEventId) ?? $events->first();

        $records = ['data' => [], 'links' => []];
        $counts = ['pending' => 0, 'review' => 0, 'cleared' => 0];

        if ($currentEvent) {
            // Identify students who didn't attend this event and seed clearance records
            $attendedStudentIds = Attendance::where('event_id', $currentEvent->event_id)->pluck('student_id');
            $absentStudents = Student::whereNotIn('student_id', $attendedStudentIds)->get();

            foreach ($absentStudents as $absentStudent) {
                StudentClearance::firstOrCreate(
                    [
                        'student_id' => $absentStudent->student_id,
                        'event_id' => $currentEvent->event_id,
                    ],
                    ['status' => 'pending']
                );
            }

            $query = StudentClearance::with('student')
                ->where('event_id', $currentEvent->event_id)
                ->when($statusFilter !== 'all', function ($q) use ($statusFilter) {
                    $q->where('status', $statusFilter);
                })
                ->when($search, function ($q) use ($search) {
                    $q->whereHas('student', function ($sub) use ($search) {
                        $sub->where('firstname', 'like', "%{$search}%")
                            ->orWhere('surname', 'like', "%{$search}%")
                            ->orWhere('student_number', 'like', "%{$search}%");
                    });
                });

            $paginated = $query->paginate(10)->withQueryString();

            $paginated->getCollection()->transform(function ($clearance) {
                $student = $clearance->student;
                return [
                    'id' => $clearance->clearance_id,
                    'studentNumber' => $student->student_number ?? 'N/A',
                    'name' => $student ? "{$student->firstname} {$student->surname}" : 'Unknown',
                    'program' => $student->program ?? 'BS Computer Science',
                    'yearSection' => $student->year_section ?? '4-A',
                    'status' => $clearance->status,
                    'updatedAt' => $clearance->updated_at ? $clearance->updated_at->diffForHumans() : 'Recently',
                ];
            });

            $records = [
                'data' => $paginated->items(),
                'links' => $paginated->linkCollection()->toArray(),
            ];

            $counts = [
                'pending' => StudentClearance::where('event_id', $currentEvent->event_id)->where('status', 'pending')->count(),
                'review' => StudentClearance::where('event_id', $currentEvent->event_id)->where('status', 'review')->count(),
                'cleared' => StudentClearance::where('event_id', $currentEvent->event_id)->where('status', 'cleared')->count(),
            ];
        }

        return Inertia::render('admin/Clearance', [
            'events' => $events,
            'currentEventId' => $currentEvent ? $currentEvent->event_id : null,
            'records' => $records,
            'counts' => $counts,
            'filters' => [
                'search' => $search ?? '',
                'event_id' => $currentEvent ? $currentEvent->event_id : '',
                'status' => $statusFilter,
            ],
        ]);
    }

    public function updateStatus(Request $request, StudentClearance $clearance)
    {
        $validated = $request->validate([
            'status' => ['required', Rule::in(['pending', 'review', 'cleared'])],
        ]);

        $clearance->update(['status' => $validated['status']]);

        return back()->with('message', 'Clearance status updated successfully.');
    }
}