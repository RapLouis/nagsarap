<?php

namespace App\Http\Controllers;

use App\Models\Student;
use Illuminate\Http\Client\Pool;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\ValidationException;
use Inertia\Inertia;
use Inertia\Response;

class StudentRegistrationController extends Controller
{
    /**
     * Display the liveness verification view.
     */
    public function showRegistrationForm(): Response
    {
        return Inertia::render('auth/register');
    }

    /**
     * Process live camera snapshot and compare against the registered profile photo.
     */
    public function verifyFace(Request $request)
    {
        // 1. Validate request parameters
        $request->validate([
            'student_id'        => 'required|exists:students,student_id',
            'live_camera_frame' => 'required',
        ]);

        $student = Student::findOrFail($request->student_id);

        // 2. Ensure student record contains a saved photo path from initial registration
        if (!$student->face_photo_path) {
            throw ValidationException::withMessages([
                'face' => 'No uploaded profile picture found for this student account. Please re-register.'
            ]);
        }

        // 3. Resolve path on private/public disk cleanly
        $relativePath = ltrim(str_replace(['/storage/', 'storage/'], '', $student->face_photo_path), '/');

        // Check disk availability (handles both private and public setups)
        $disk = Storage::disk('private')->exists($relativePath) ? 'private' : 'public';

        if (!Storage::disk($disk)->exists($relativePath)) {
            throw ValidationException::withMessages([
                'face' => 'Registered profile picture file is missing on the server.'
            ]);
        }

        $photoAbsolutePath = Storage::disk($disk)->path($relativePath);
        $photoBase64 = base64_encode(file_get_contents($photoAbsolutePath));

        // 4. Extract Base64 from the uploaded live webcam file or string payload
        if ($request->hasFile('live_camera_frame')) {
            $liveBase64 = base64_encode(file_get_contents($request->file('live_camera_frame')->getRealPath()));
        } else {
            $liveBase64 = preg_replace('#^data:image/\w+;base64,#i', '', $request->input('live_camera_frame'));
        }

        // 5. Query Python microservice (Port 5000) concurrently for fast extraction
        try {
            $responses = Http::pool(fn (Pool $pool) => [
                $pool->as('photo')->timeout(10)->post('http://127.0.0.1:5000/extract-embedding', [
                    'image_base64' => $photoBase64,
                ]),
                $pool->as('live')->timeout(10)->post('http://127.0.0.1:5000/extract-embedding', [
                    'image_base64' => $liveBase64,
                ]),
            ]);

            $photoResponse = $responses['photo'];
            $liveResponse = $responses['live'];

            if ($photoResponse->failed()) {
                $detail = $photoResponse->json()['detail'] ?? 'Unable to detect a clear face in profile picture.';
                throw ValidationException::withMessages([
                    'face' => "Profile Photo Error: {$detail}"
                ]);
            }

            if ($liveResponse->failed()) {
                $detail = $liveResponse->json()['detail'] ?? 'Unable to detect a clear face in camera frame.';
                throw ValidationException::withMessages([
                    'face' => "Live Camera Error: {$detail}"
                ]);
            }

            $photoEmbedding = $photoResponse->json()['embedding'] ?? null;
            $liveEmbedding = $liveResponse->json()['embedding'] ?? null;

            if (empty($photoEmbedding) || empty($liveEmbedding)) {
                throw ValidationException::withMessages([
                    'face' => 'Facial feature extraction incomplete. Ensure your face is fully lit and unobscured.'
                ]);
            }

        } catch (\Exception $e) {
            if ($e instanceof ValidationException) throw $e;

            Log::error('Biometrics Service Connection Failure: ' . $e->getMessage());
            throw ValidationException::withMessages([
                'face' => 'Unable to connect to Python biometric service on port 5000. Ensure app.py is running.'
            ]);
        }

        // 6. CALCULATE COSINE SIMILARITY SCORE
        $similarity = $this->calculateCosineSimilarity($photoEmbedding, $liveEmbedding);

        Log::info("Face Verification Match Score for Student ID {$student->student_id}: {$similarity}");

        // STRICT MATCH ENFORCEMENT: Block if similarity score < 0.60
        if ($similarity < 0.60) {
            throw ValidationException::withMessages([
                'face' => "Face mismatch detected! The person in front of the camera does not match the uploaded profile picture."
            ]);
        }

        // 7. Duplicate Face Check: Ensure live face is not already assigned to another student
        $existingStudents = Student::whereNotNull('face_embedding')
            ->where('student_id', '!=', $student->student_id)
            ->where('verification_status', 'verified')
            ->get();

        foreach ($existingStudents as $existingStudent) {
            $existingEmbedding = is_string($existingStudent->face_embedding)
                ? json_decode($existingStudent->face_embedding, true)
                : $existingStudent->face_embedding;

            if (is_array($existingEmbedding)) {
                $dupSimilarity = $this->calculateCosineSimilarity($liveEmbedding, $existingEmbedding);

                if ($dupSimilarity >= 0.60) {
                    throw ValidationException::withMessages([
                        'face' => "Duplicate face detected! Face is already registered to student number: {$existingStudent->student_number}"
                    ]);
                }
            }
        }

        // 8. Save embedding vector & set verification status to 'verified' ONLY when matched
        $student->face_embedding = $liveEmbedding;
        $student->verification_status = 'verified';
        $student->save();

        return redirect()->route('dashboard')->with('success', 'Biometric verification complete!');
    }

    /**
     * Calculate Cosine Similarity between two 512-D float vectors.
     */
    private function calculateCosineSimilarity(array $vecA, array $vecB): float
    {
        $dotProduct = 0.0;
        $normA = 0.0;
        $normB = 0.0;

        $count = min(count($vecA), count($vecB));

        for ($i = 0; $i < $count; $i++) {
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