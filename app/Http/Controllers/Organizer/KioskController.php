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
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Inertia\Inertia;

class KioskController extends Controller
{
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

    public function verifyFace(Request $request, BiometricService $biometricService, SlotResolver $slotResolver)
    {
        $request->validate([
            'event_id' => ['required'],
            'image' => ['required', 'string'], // Base64 data URL from canvas
        ]);

        // 1. Locate event by primary key
        $event = Event::where('event_id', $request->event_id)
            ->orWhere('id', $request->event_id)
            ->firstOrFail();

        if (!$event->is_active) {
            return response()->json([
                'success' => false,
                'message' => 'Attendance for this event is currently closed.',
            ], 422);
        }

        // 2. Convert base64 image data URL to a temporary UploadedFile
        $tempFile = $this->base64ToUploadedFile($request->image);
        if (!$tempFile) {
            return response()->json([
                'success' => false,
                'message' => 'Invalid or unreadable frame captured from camera.',
            ], 422);
        }

        // 3. Extract live facial embedding
        try {
            $liveEmbedding = $biometricService->profileEmbeddingFromFile($tempFile);
        } catch (\Throwable $e) {
            return response()->json([
                'success' => false,
                'message' => 'Could not detect a clear face. Please align face inside frame.',
            ], 422);
        } finally {
            if (file_exists($tempFile->getRealPath())) {
                @unlink($tempFile->getRealPath());
            }
        }

        // 4. Match against verified students with registered facial embeddings
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

        $now = Carbon::now(config('app.timezone', 'UTC'));

        // 5. Resolve active schedule slot (passing null, null for inferred slot/type)
        try {
            $resolved = $slotResolver->resolveOrInfer($event, $now, null, null);

            // Guard against duplicate check-in/check-out for this slot
            $slotResolver->guard($bestMatch->student_id, $event->event_id, $resolved);
        } catch (AttendanceException $e) {
            return response()->json([
                'success' => false,
                'message' => $e->getMessage(),
            ], $e->getCode() ?: 422);
        }

        // 6. Record attendance using standard schema
        try {
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
                    'source' => 'kiosk',
                    'confidence_score' => round($highestSimilarity, 4),
                    'liveness_passed' => true,
                    'liveness_method' => 'kiosk_facial_recognition',
                ]);
            });
        } catch (\Illuminate\Database\QueryException $e) {
            if (str_starts_with((string) $e->getCode(), '23')) {
                return response()->json([
                    'success' => false,
                    'message' => ($resolved['type'] ?? 'in') === 'out'
                        ? 'Student has already checked out for this slot.'
                        : 'Student has already checked in for this slot.',
                ], 409);
            }
            throw $e;
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
     * Helper to decode Base64 data URL into an UploadedFile instance.
     */
    private function base64ToUploadedFile(string $base64Data): ?UploadedFile
    {
        if (preg_match('/^data:image\/(\w+);base64,/', $base64Data, $type)) {
            $data = substr($base64Data, strpos($base64Data, ',') + 1);
            $type = strtolower($type[1]);

            $data = base64_decode($data);
            if ($data === false) return null;

            $tmpFilePath = sys_get_temp_dir() . '/' . Str::uuid() . '.' . $type;
            file_put_contents($tmpFilePath, $data);

            return new UploadedFile($tmpFilePath, "kiosk_frame.{$type}", "image/{$type}", null, true);
        }

        return null;
    }
}