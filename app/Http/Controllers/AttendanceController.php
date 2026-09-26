<?php

namespace App\Http\Controllers;

use App\Models\Attendance;
use App\Models\Event;
use App\Models\Student;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Http;

class AttendanceController extends Controller
{
    /**
     * Mark attendance for an active event using face verification.
     */
    public function markAttendance(Request $request)
    {
        /** @var \App\Models\User $user */
        $user = Auth::user();
        $student = $user->student;

        if (!$student || $student->verification_status !== 'verified' || !$student->face_embedding) {
            return back()->withErrors([
                'attendance' => 'Your face biometrics are not registered or verified yet.'
            ]);
        }

        // 1. Validate payload
        $request->validate([
            'event_id'          => ['required', 'exists:events,event_id'],
            'live_camera_frame' => ['required', 'image', 'mimes:jpeg,png,jpg', 'max:5048'],
        ]);

        $event = Event::findOrFail($request->event_id);

        if (!$event->is_active) {
            return back()->withErrors([
                'attendance' => 'Attendance check-in for this event is currently closed.'
            ]);
        }

        // 2. Prevent duplicate check-in for the same event
        $alreadyCheckedIn = Attendance::where('student_id', $student->student_id)
            ->where('event_id', $event->event_id)
            ->exists();

        if ($alreadyCheckedIn) {
            return back()->withErrors([
                'attendance' => 'You have already checked in for this event.'
            ]);
        }

        // 3. Convert uploaded camera frame to Base64 for Python microservice
        $liveFrameFile = $request->file('live_camera_frame');
        $base64Image = 'data:image/jpeg;base64,' . base64_encode(file_get_contents($liveFrameFile->getRealPath()));

        // 4. Request 512-D vector extraction from Python AI Service
        try {
            $response = Http::timeout(10)->post('http://127.0.0.1:5000/extract-embedding', [
                'image_base64' => $base64Image,
            ]);

            if ($response->failed()) {
                return back()->withErrors([
                    'attendance' => $response->json()['detail'] ?? 'Face scan failed. Ensure proper camera lighting.'
                ]);
            }

            $scannedEmbedding = $response->json()['embedding'];

        } catch (\Exception $e) {
            return back()->withErrors([
                'attendance' => 'Unable to connect to biometric verification service.'
            ]);
        }

        // 5. Compare Scanned Vector against Stored Student Vector
        $similarity = $this->calculateCosineSimilarity($scannedEmbedding, $student->face_embedding);

        // Verification threshold (0.60 matches enrollment face)
        if ($similarity < 0.60) {
            return back()->withErrors([
                'attendance' => 'Face verification failed. Scanned face does not match your profile.'
            ]);
        }

        // 6. Record Attendance Entry
        Attendance::create([
            'student_id'       => $student->student_id,
            'event_id'         => $event->event_id,
            'logged_at'        => now(),
            'status'           => 'present',
            'confidence_score' => round($similarity, 4),
        ]);

        return back()->with('success', 'Attendance marked successfully!');
    }

    /**
     * Calculate Cosine Similarity between two 512-D vector arrays.
     */
    private function calculateCosineSimilarity(array $vecA, array $vecB): float
    {
        $dotProduct = 0.0;
        $normA = 0.0;
        $normB = 0.0;

        for ($i = 0; $i < count($vecA); $i++) {
            $dotProduct += $vecA[$i] * $vecB[$i];
            $normA += $vecA[$i] ** 2;
            $normB += $vecB[$i] ** 2;
        }

        if ($normA == 0 || $normB == 0) {
            return 0.0;
        }

        return $dotProduct / (sqrt($normA) * sqrt($normB));
    }
}