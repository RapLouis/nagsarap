<?php

namespace App\Http\Controllers\Organizer;

use App\Exceptions\AttendanceException;
use App\Http\Controllers\Controller;
use App\Models\Attendance;
use App\Models\Event;
use App\Models\Student;
use App\Services\BiometricService;
use App\Services\SlotResolver;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Inertia\Inertia;

class KioskController extends Controller
{
    /**
     * Display the organizer kiosk interface.
     */
    public function index(Request $request)
    {
        $events = Event::where('user_id', $request->user()->id)
            ->where('approval_status', 'approved')
            ->get()
            ->transform(function ($event) {
                $event->id = $event->event_id; // Normalize key for frontend select components
                return $event;
            });

        return Inertia::render('organizer/Kiosk', [
            'events' => $events,
        ]);
    }

    /**
     * Issue a liveness challenge nonce for the kiosk scan.
     */
    public function challenge()
    {
        $direction = rand(0, 1) === 0 ? 'left' : 'right';
        $availableColors = ['red', 'green', 'blue'];
        shuffle($availableColors);
        $flashColors = array_slice($availableColors, 0, 3);
        $nonce = Str::random(40);

        session([
            'kiosk_liveness_challenge' => [
                'nonce' => $nonce,
                'direction' => $direction,
                'flash_colors' => $flashColors,
                'expires_at' => now()->addMinutes(2),
            ]
        ]);

        return response()->json([
            'nonce' => $nonce,
            'direction' => $direction,
            'flash_colors' => $flashColors,
        ]);
    }

    /**
     * Verify live face scan against database embeddings using liveness anti-spoofing.
     */
    public function verifyFace(Request $request, BiometricService $biometricService, SlotResolver $slotResolver)
    {
        $request->validate([
            'event_id' => ['required'],
            'challenge_nonce' => ['required', 'string'],
            'live_camera_frame' => ['required', 'file', 'image', 'max:5120'],
            'flash_frames' => ['required', 'array', 'size:3'],
            'flash_frames.*' => ['required', 'file', 'image', 'max:5120'],
            'turn_peak_frame' => ['required', 'file', 'image', 'max:5120'],
        ]);

        // 1. Locate event by custom event_id column
        $event = Event::where('event_id', $request->event_id)->first();

        if (!$event) {
            return response()->json([
                'success' => false,
                'message' => 'The selected event could not be found.',
            ], 404);
        }

        if (!$event->is_active) {
            return response()->json([
                'success' => false,
                'message' => 'Attendance for this event is currently closed.',
            ], 422);
        }

        // Validate Challenge Session Nonce
        $sessionChallenge = session('kiosk_liveness_challenge');
        if (!$sessionChallenge || 
            $sessionChallenge['nonce'] !== $request->input('challenge_nonce') || 
            now()->isAfter($sessionChallenge['expires_at'])) {
            return response()->json([
                'success' => false,
                'message' => 'Liveness session expired. Please restart scan.',
            ], 422);
        }
        session()->forget('kiosk_liveness_challenge');

        // 2. Extract live embedding & validate anti-spoofing via BiometricService
        try {
            $liveEmbedding = $biometricService->verifyLivenessAndExtractEmbedding(
                $request->file('live_camera_frame'),
                $request->file('flash_frames'),
                $request->file('turn_peak_frame'),
                $sessionChallenge['direction'],
                $sessionChallenge['flash_colors']
            );
        } catch (\Throwable $e) {
            return response()->json([
                'success' => false,
                'message' => $e->getMessage() ?: 'Anti-spoofing or liveness check failed.',
            ], 422);
        }

        // 3. Match embedding against verified database students
        $students = Student::where('verification_status', 'verified')
            ->whereNotNull('face_embedding')
            ->get();

        $bestMatch = null;
        $highestSimilarity = 0.0;
        $threshold = (float) config('face_verification.profile_match_threshold', 0.50);

        foreach ($students as $student) {
            if (empty($student->face_embedding)) {
                continue;
            }

            $similarity = BiometricService::cosineSimilarity($liveEmbedding, $student->face_embedding);

            if ($similarity > $highestSimilarity) {
                $highestSimilarity = $similarity;
                $bestMatch = $student;
            }
        }

        if (!$bestMatch || $highestSimilarity < $threshold) {
            return response()->json([
                'success' => false,
                'message' => 'Facial recognition failed: No matching student record found.',
            ], 404);
        }

        // 4. Target Scope check
        if ($event->target_scope === 'section') {
            $studentSection = trim("{$bestMatch->degree} - {$bestMatch->year_section}");
            $allowedSections = $event->target_sections ?? [];
            if (!in_array($studentSection, $allowedSections)) {
                return response()->json([
                    'success' => false,
                    'message' => "Student {$bestMatch->firstname} is not included in the target section scope for this event.",
                ], 422);
            }
        }

        $now = Carbon::now(config('app.timezone', 'UTC'));

        // 5. Resolve slot and record attendance
        try {
            $resolved = $slotResolver->resolveOrInfer($event, $now, null, null);
            $slotResolver->guard($bestMatch->student_id, $event->event_id, $resolved);

            $attendance = DB::transaction(function () use ($bestMatch, $event, $resolved, $highestSimilarity, $now) {
                return Attendance::create([
                    'attendance_uuid' => (string) Str::uuid(),
                    'student_id' => $bestMatch->student_id,
                    'event_id' => $event->event_id,
                    'event_date' => $resolved['date'] ?? $now->toDateString(),
                    'slot_index' => $resolved['index'] ?? 0,
                    'type' => $resolved['type'] ?? 'in',
                    'logged_at' => $now,
                    'attendance_time' => $now,
                    'sync_time' => $now,
                    'status' => $resolved['status'] ?? 'present',
                    'sync_status' => 'synced',
                    'source' => 'kiosk_liveness',
                    'confidence_score' => round($highestSimilarity, 4),
                    'liveness_passed' => true,
                    'liveness_method' => 'kiosk_flash_and_turn_challenge',
                ]);
            });
        } catch (AttendanceException $e) {
            return response()->json([
                'success' => false,
                'message' => $e->getMessage(),
            ], $e->getCode() ?: 422);
        }

        return response()->json([
            'success' => true,
            'message' => 'Attendance successfully recorded!',
            'student' => [
                'name' => trim("{$bestMatch->firstname} {$bestMatch->surname}"),
                'student_number' => $bestMatch->student_number,
                'course' => $bestMatch->degree ?? 'N/A',
            ],
            'type' => strtoupper($attendance->type),
            'time_in' => Carbon::parse($attendance->attendance_time)->format('h:i A'),
        ]);
    }

    /**
     * Search students for manual fallback override.
     */
    public function searchStudents(Request $request)
    {
        $query = $request->input('q');
        $students = Student::where('verification_status', 'verified')
            ->where(function ($q) use ($query) {
                $q->where('firstname', 'like', "%{$query}%")
                  ->orWhere('surname', 'like', "%{$query}%")
                  ->orWhere('student_number', 'like', "%{$query}%");
            })
            ->limit(10)
            ->get();

        return response()->json(['students' => $students]);
    }

    /**
     * Force check-in a student manually via organizer override.
     */
    public function manualOverride(Request $request, SlotResolver $slotResolver)
    {
        $request->validate([
            'event_id' => 'required',
            'student_id' => 'required|exists:students,student_id',
        ]);

        $event = Event::where('event_id', $request->event_id)->first();
        if (!$event) {
            return response()->json(['success' => false, 'message' => 'Event not found.'], 404);
        }

        $student = Student::where('student_id', $request->student_id)->firstOrFail();
        $now = Carbon::now(config('app.timezone', 'UTC'));

        try {
            $resolved = $slotResolver->resolveOrInfer($event, $now, null, null);
            $slotResolver->guard($student->student_id, $event->event_id, $resolved);

            Attendance::create([
                'attendance_uuid' => (string) Str::uuid(),
                'student_id' => $student->student_id,
                'event_id' => $event->event_id,
                'event_date' => $resolved['date'] ?? $now->toDateString(),
                'slot_index' => $resolved['index'] ?? 0,
                'type' => $resolved['type'] ?? 'in',
                'logged_at' => $now,
                'attendance_time' => $now,
                'sync_time' => $now,
                'status' => $resolved['status'] ?? 'present',
                'sync_status' => 'synced',
                'source' => 'organizer_manual_override',
                'confidence_score' => 1.0000,
                'liveness_passed' => true,
                'liveness_method' => 'manual_organizer_override',
            ]);
        } catch (AttendanceException $e) {
            return response()->json(['success' => false, 'message' => $e->getMessage()], 422);
        }

        return response()->json([
            'success' => true,
            'message' => "Successfully force checked-in {$student->firstname} {$student->surname}!",
        ]);
    }
}