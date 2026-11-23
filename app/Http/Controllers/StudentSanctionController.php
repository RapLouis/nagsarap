<?php

namespace App\Http\Controllers;

use App\Models\Sanction;
use App\Models\SanctionSetting;
use App\Services\SanctionSyncService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Storage;
use Inertia\Inertia;

class StudentSanctionController extends Controller
{
    public function __construct(
        protected SanctionSyncService $syncService
    ) {}

    /**
     * Render the student Sanctions & Attendance History page.
     */
    public function index(Request $request)
    {
        $user = Auth::user();

        if ($user->role === 'admin') {
            return redirect()->route('admin.sanctions.index');
        }
        if ($user->role === 'organizer') {
            return redirect()->route('organizer.dashboard');
        }

        $student = $user->load(['student.attendances.event'])->student;

        if (!$student) {
            return redirect()->route('dashboard');
        }

        // 1. Audit past event slots and ensure any missed 4-checkpoint logs are recorded
        $this->syncService->syncForStudent($student);

        // 2. Fetch all sanctions for this student, newest first
        $sanctions = Sanction::with('event')
            ->where('student_id', $student->student_id)
            ->orderByDesc('event_date')
            ->orderBy('slot_index')
            ->get()
            ->map(function ($sanction) {
                return [
                    'sanction_id'         => $sanction->sanction_id,
                    'event_id'            => $sanction->event_id,
                    'event_title'         => $sanction->event?->title ?? $sanction->title,
                    'event_date'          => $sanction->event_date?->format('Y-m-d'),
                    'slot_index'          => $sanction->slot_index,
                    'slot_label'          => $sanction->slot_label,
                    'infraction_type'     => $sanction->infraction_type,
                    'fine_amount'         => (float) $sanction->fine_amount,
                    'status'              => $sanction->status,
                    'preferred_mode'      => $sanction->preferred_mode,
                    'excuse_category'     => $sanction->excuse_category,
                    'student_notes'       => $sanction->student_notes,
                    'has_proof'           => (bool) $sanction->excuse_proof_path,
                    'proof_url'           => $sanction->excuse_proof_path
                        ? route('sanctions.proof', ['sanction' => $sanction->sanction_id])
                        : null,
                    'official_receipt_no' => $sanction->official_receipt_no,
                    'comm_service_hours'  => $sanction->comm_service_hours ? (float) $sanction->comm_service_hours : null,
                    'admin_remarks'       => $sanction->admin_remarks,
                    'resolved_at'         => $sanction->resolved_at?->format('M d, Y h:i A'),
                ];
            });

        // 3. Calculate KPIs across the 4 checkpoints
        $activeSanctions = $sanctions->whereIn('status', ['unsettled', 'pending_verification']);
        $unsettledBalance = $activeSanctions->sum('fine_amount');

        $missingMorningIn    = $activeSanctions->where('infraction_type', 'missing_morning_time_in')->count();
        $missingMorningOut   = $activeSanctions->where('infraction_type', 'missing_morning_time_out')->count();
        $missingAfternoonIn  = $activeSanctions->where('infraction_type', 'missing_afternoon_time_in')->count();
        $missingAfternoonOut = $activeSanctions->where('infraction_type', 'missing_afternoon_time_out')->count();

        // 4. Full attendance log history for the history tab
        $attendanceLogs = $student->attendances
            ->sortByDesc('event_date')
            ->values()
            ->map(function ($att) {
                return [
                    'attendance_id'  => $att->attendance_id ?? $att->id,
                    'event_title'    => $att->event?->title ?? 'Campus Event',
                    'event_date'     => $att->event_date,
                    'slot_index'     => $att->slot_index,
                    'type'           => $att->type,
                    'checkpoint_key' => $att->checkpoint_key,
                    'logged_at'      => $att->created_at?->format('M d, Y h:i A'),
                ];
            });

        return Inertia::render('Sanctions', [
            'student'          => $student,
            'sanctions'        => $sanctions->values(),
            'attendanceLogs'   => $attendanceLogs,
            'fineRatePerLog'   => SanctionSetting::getFinePerLog(),
            'summary'          => [
                'unsettled_balance'   => $unsettledBalance,
                'active_count'        => $activeSanctions->count(),
                'missing_morning_in'  => $missingMorningIn,
                'missing_morning_out' => $missingMorningOut,
                'missing_aft_in'      => $missingAfternoonIn,
                'missing_aft_out'     => $missingAfternoonOut,
                'is_cleared'          => $activeSanctions->isEmpty(),
                'clearance_status'    => $activeSanctions->isEmpty() ? 'cleared' : 'pending',
            ],
        ]);
    }

    /**
     * Declare student preference for settling sanctions (Cash or Community Service).
     */
    public function declareResolution(Request $request)
    {
        $validated = $request->validate([
            'sanction_ids'   => ['required', 'array', 'min:1'],
            'sanction_ids.*' => ['integer', 'exists:sanctions,sanction_id'],
            'preferred_mode' => ['required', 'in:cash,community_service'],
        ]);

        $student = Auth::user()->student;
        abort_unless($student, 403);

        Sanction::where('student_id', $student->student_id)
            ->whereIn('sanction_id', $validated['sanction_ids'])
            ->whereIn('status', ['unsettled', 'pending_verification'])
            ->update([
                'preferred_mode' => $validated['preferred_mode'],
                'status'         => 'pending_verification',
            ]);

        return back()->with('success', 'Settlement preference submitted. Please proceed to the SASC/CCIS office for verification.');
    }

    /**
     * Submit an excuse letter and proof for a specific missed checkpoint infraction.
     */
    public function submitExcuse(Request $request, Sanction $sanction)
    {
        $student = Auth::user()->student;
        abort_unless($student && $sanction->student_id === $student->student_id, 403);
        abort_unless(in_array($sanction->status, ['unsettled', 'pending_verification']), 422);

        $validated = $request->validate([
            'excuse_category' => ['required', 'string', 'max:100'],
            'student_notes'   => ['required', 'string', 'min:10', 'max:1000'],
            'excuse_proof'    => ['required', 'file', 'mimes:jpg,jpeg,png,webp,pdf', 'max:5120'],
        ]);

        if ($sanction->excuse_proof_path && Storage::disk('private')->exists($sanction->excuse_proof_path)) {
            Storage::disk('private')->delete($sanction->excuse_proof_path);
        }

        $path = $request->file('excuse_proof')->store(
            'excuse-proofs/' . now()->format('Y-m'),
            'private'
        );

        $sanction->update([
            'preferred_mode'    => 'excuse',
            'status'            => 'pending_verification',
            'excuse_category'   => $validated['excuse_category'],
            'student_notes'     => $validated['student_notes'],
            'excuse_proof_path' => $path,
            'admin_remarks'     => null,
        ]);

        return back()->with('success', 'Excuse letter and proof submitted for SASC review.');
    }

    /**
     * Stream secure private storage files for excuse proof attachments.
     */
    public function viewProof(Sanction $sanction)
    {
        $user = Auth::user();
        $isOwner = $user->student && $user->student->student_id === $sanction->student_id;
        $isAdmin = $user->role === 'admin';

        abort_unless($isOwner || $isAdmin, 403);
        abort_unless($sanction->excuse_proof_path && Storage::disk('private')->exists($sanction->excuse_proof_path), 404);

        return Storage::disk('private')->response($sanction->excuse_proof_path);
    }
}