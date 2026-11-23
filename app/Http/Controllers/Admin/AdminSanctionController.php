<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Sanction;
use App\Models\SanctionSetting;
use App\Models\Student;
use App\Models\StudentClearance;
use App\Models\StudentNotification;
use App\Services\SanctionSyncService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Inertia\Inertia;

class AdminSanctionController extends Controller
{
    public function __construct(
        protected SanctionSyncService $syncService
    ) {}

    public function index(Request $request)
    {
        // Automatically audit past completed events for all verified students
        $this->syncService->syncAllStudents();

        $search  = trim((string) $request->input('search', ''));
        $degree  = $request->input('degree', 'all');
        $section = $request->input('section', 'all');
        $status  = $request->input('status', 'all');
        $mode    = $request->input('mode', 'all');

        // Fetch all verified students so the directory lists students even before filtering
        $studentsQuery = Student::with(['sanctions.event'])
            ->where('verification_status', 'verified');

        if ($search !== '') {
            $studentsQuery->where(function ($q) use ($search) {
                $q->where('student_id', 'like', "%{$search}%")
                  ->orWhere('student_number', 'like', "%{$search}%")
                  ->orWhere('firstname', 'like', "%{$search}%")
                  ->orWhere('surname', 'like', "%{$search}%");
            });
        }

        if ($degree !== 'all') {
            $studentsQuery->where('degree', $degree);
        }

        if ($section !== 'all') {
            $studentsQuery->where('year_section', $section);
        }

        $students = $studentsQuery
            ->orderBy('surname')
            ->orderBy('firstname')
            ->get()
            ->map(function ($student) use ($status, $mode) {
                $sanctions = $student->sanctions->sortByDesc('event_date')->values();

                if ($status !== 'all') {
                    $sanctions = $sanctions->where('status', $status)->values();
                }
                if ($mode !== 'all') {
                    $sanctions = $sanctions->where('preferred_mode', $mode)->values();
                }

                $unsettledSanctions = $sanctions->whereIn('status', ['unsettled', 'pending_verification']);

                $fullName = collect([
                    $student->firstname,
                    $student->middlename,
                    $student->surname,
                    $student->ext,
                ])->filter()->implode(' ');

                return [
                    'student_id'          => $student->student_id,
                    'student_number'      => $student->student_number,
                    'full_name'           => $fullName ?: "Student #{$student->student_id}",
                    'degree'              => $student->degree,
                    'year_section'        => $student->year_section,
                    'clearance_status'    => $unsettledSanctions->isEmpty() ? 'cleared' : 'pending',
                    'unsettled_balance'   => (float) $unsettledSanctions->sum('fine_amount'),
                    'unsettled_count'     => $unsettledSanctions->count(),
                    'pending_cash_count'  => $sanctions->where('status', 'pending_verification')->where('preferred_mode', 'cash')->count(),
                    'pending_serv_count'  => $sanctions->where('status', 'pending_verification')->where('preferred_mode', 'community_service')->count(),
                    'pending_exc_count'   => $sanctions->where('status', 'pending_verification')->where('preferred_mode', 'excuse')->count(),
                    'sanctions'           => $sanctions->map(function ($s) {
                        return [
                            'sanction_id'         => $s->sanction_id,
                            'event_title'         => $s->event?->title ?? $s->title,
                            'event_date'          => $s->event_date?->format('Y-m-d'),
                            'slot_label'          => $s->slot_label,
                            'infraction_type'     => $s->infraction_type,
                            'fine_amount'         => (float) $s->fine_amount,
                            'status'              => $s->status,
                            'preferred_mode'      => $s->preferred_mode,
                            'excuse_category'     => $s->excuse_category,
                            'student_notes'       => $s->student_notes,
                            'has_proof'           => (bool) $s->excuse_proof_path,
                            'proof_url'           => $s->excuse_proof_path
                                ? route('sanctions.proof', ['sanction' => $s->sanction_id])
                                : null,
                            'official_receipt_no' => $s->official_receipt_no,
                            'comm_service_hours'  => $s->comm_service_hours ? (float) $s->comm_service_hours : null,
                            'admin_remarks'       => $s->admin_remarks,
                            'resolved_at'         => $s->resolved_at?->format('M d, Y h:i A'),
                        ];
                    }),
                ];
            });

        if ($status !== 'all' || $mode !== 'all') {
            $students = $students->filter(fn ($s) => count($s['sanctions']) > 0)->values();
        }

        $degrees = Student::where('verification_status', 'verified')->distinct()->pluck('degree')->filter()->sort()->values();
        $sections = Student::where('verification_status', 'verified')->distinct()->pluck('year_section')->filter()->sort()->values();

        $allSanctions = Sanction::all();
        $metrics = [
            'total_collectible'  => (float) $allSanctions->whereIn('status', ['unsettled', 'pending_verification'])->sum('fine_amount'),
            'total_collected'    => (float) $allSanctions->where('status', 'settled')->where('preferred_mode', 'cash')->sum('fine_amount'),
            'total_service_hrs'  => (float) $allSanctions->where('status', 'settled')->where('preferred_mode', 'community_service')->sum('comm_service_hours'),
            'pending_cash'       => $allSanctions->where('status', 'pending_verification')->where('preferred_mode', 'cash')->count(),
            'pending_service'    => $allSanctions->where('status', 'pending_verification')->where('preferred_mode', 'community_service')->count(),
            'pending_excuses'    => $allSanctions->where('status', 'pending_verification')->where('preferred_mode', 'excuse')->count(),
        ];

        return Inertia::render('admin/StudentSanctions', [
            'students'       => $students,
            'metrics'        => $metrics,
            'fineRatePerLog' => SanctionSetting::getFinePerLog(),
            'filterOptions'  => [
                'degrees'  => $degrees,
                'sections' => $sections,
            ],
            'filters'        => [
                'search'  => $search,
                'degree'  => $degree,
                'section' => $section,
                'status'  => $status,
                'mode'    => $mode,
            ],
        ]);
    }

    public function updateFineRate(Request $request)
    {
        $validated = $request->validate([
            'fine_per_log'       => ['required', 'numeric', 'min:0', 'max:10000'],
            'apply_to_unsettled' => ['boolean'],
        ]);

        $newRate = (float) $validated['fine_per_log'];
        SanctionSetting::setFinePerLog($newRate);

        if (!empty($validated['apply_to_unsettled'])) {
            Sanction::whereIn('status', ['unsettled', 'pending_verification'])
                ->update(['fine_amount' => $newRate]);
        }

        return back()->with('success', 'Sanction fine rate updated successfully.');
    }

    public function verifyCash(Request $request)
    {
        $validated = $request->validate([
            'student_id'          => ['required', 'exists:students,student_id'],
            'sanction_ids'        => ['required', 'array', 'min:1'],
            'sanction_ids.*'      => ['integer', 'exists:sanctions,sanction_id'],
            'official_receipt_no' => ['required', 'string', 'max:100'],
            'admin_remarks'       => ['nullable', 'string', 'max:500'],
        ]);

        DB::transaction(function () use ($validated) {
            $sanctions = Sanction::where('student_id', $validated['student_id'])
                ->whereIn('sanction_id', $validated['sanction_ids'])
                ->whereIn('status', ['unsettled', 'pending_verification'])
                ->get();

            $totalPaid = $sanctions->sum('fine_amount');

            Sanction::whereIn('sanction_id', $sanctions->pluck('sanction_id'))
                ->update([
                    'preferred_mode'      => 'cash',
                    'status'              => 'settled',
                    'official_receipt_no' => $validated['official_receipt_no'],
                    'admin_remarks'       => $validated['admin_remarks'] ?? 'Paid in cash at SASC/CCIS office.',
                    'settled_by'          => Auth::id(),
                    'resolved_at'         => now(),
                ]);

            $this->syncStudentClearanceAndNotify(
                $validated['student_id'],
                'Sanction Cash Payment Verified',
                "Your cash payment of ₱" . number_format($totalPaid, 2) . " (OR #{$validated['official_receipt_no']}) for {$sanctions->count()} infraction(s) has been verified."
            );
        });

        return back()->with('success', 'Cash payment verified and Official Receipt logged.');
    }

    public function verifyService(Request $request)
    {
        $validated = $request->validate([
            'student_id'         => ['required', 'exists:students,student_id'],
            'sanction_ids'       => ['required', 'array', 'min:1'],
            'sanction_ids.*'     => ['integer', 'exists:sanctions,sanction_id'],
            'comm_service_hours' => ['required', 'numeric', 'min:0.25', 'max:500'],
            'admin_remarks'      => ['required', 'string', 'max:500'],
        ]);

        DB::transaction(function () use ($validated) {
            $count = count($validated['sanction_ids']);
            $hoursPerLog = round(((float) $validated['comm_service_hours']) / $count, 2);

            Sanction::where('student_id', $validated['student_id'])
                ->whereIn('sanction_id', $validated['sanction_ids'])
                ->whereIn('status', ['unsettled', 'pending_verification'])
                ->update([
                    'preferred_mode'     => 'community_service',
                    'status'             => 'settled',
                    'comm_service_hours' => $hoursPerLog,
                    'admin_remarks'      => $validated['admin_remarks'],
                    'settled_by'         => Auth::id(),
                    'resolved_at'        => now(),
                ]);

            $this->syncStudentClearanceAndNotify(
                $validated['student_id'],
                'Community Service Verified',
                "Your {$validated['comm_service_hours']} hr(s) of community service ({$validated['admin_remarks']}) has been verified for {$count} infraction(s)."
            );
        });

        return back()->with('success', 'Community service completion verified.');
    }

    public function reviewExcuse(Request $request, Sanction $sanction)
    {
        $validated = $request->validate([
            'decision'      => ['required', 'in:approve,reject'],
            'admin_remarks' => ['required', 'string', 'max:500'],
        ]);

        DB::transaction(function () use ($sanction, $validated) {
            if ($validated['decision'] === 'approve') {
                $sanction->update([
                    'preferred_mode' => 'excuse',
                    'status'         => 'excused',
                    'fine_amount'    => 0.00,
                    'admin_remarks'  => $validated['admin_remarks'],
                    'settled_by'     => Auth::id(),
                    'resolved_at'    => now(),
                ]);

                $this->syncStudentClearanceAndNotify(
                    $sanction->student_id,
                    'Excuse Appeal Approved',
                    "Your excuse for {$sanction->title} was approved. Remark: {$validated['admin_remarks']}"
                );
            } else {
                $sanction->update([
                    'preferred_mode' => 'unselected',
                    'status'         => 'unsettled',
                    'admin_remarks'  => "Excuse Rejected: {$validated['admin_remarks']}",
                ]);

                $this->syncStudentClearanceAndNotify(
                    $sanction->student_id,
                    'Excuse Appeal Rejected',
                    "Your excuse for {$sanction->title} was not approved ({$validated['admin_remarks']}). Please select Cash or Community Service."
                );
            }
        });

        return back()->with('success', $validated['decision'] === 'approve' ? 'Excuse approved.' : 'Excuse rejected.');
    }

    protected function syncStudentClearanceAndNotify(int|string $studentId, string $title, string $message): void
    {
        $remainingCount = Sanction::where('student_id', $studentId)
            ->whereIn('status', ['unsettled', 'pending_verification'])
            ->count();

        if ($remainingCount === 0) {
            StudentClearance::where('student_id', $studentId)
                ->update([
                    'status'     => 'cleared',
                    'updated_at' => now(),
                ]);
        }

        StudentNotification::create([
            'student_id' => $studentId,
            'title'      => $title,
            'message'    => $message,
            'type'       => 'sanction',
            'is_read'    => false,
        ]);
    }
}