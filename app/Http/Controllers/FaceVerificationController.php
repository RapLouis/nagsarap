<?php

namespace App\Http\Controllers;

use App\Exceptions\BiometricServiceException;
use App\Http\Requests\VerifyFaceRequest;
use App\Models\FaceVerificationAttempt;
use App\Models\Student;
use App\Services\BiometricService;
use App\Services\FaceChallengeService;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Str;
use Inertia\Inertia;
use Inertia\Response;

class FaceVerificationController extends Controller
{
    public function __construct(
        private readonly FaceChallengeService $challenges,
        private readonly BiometricService $biometrics,
    ) {
    }

    /**
     * Render the verification page with a fresh server-issued challenge.
     * Replaces the closure that used to live in routes/web.php.
     */
    public function show(Request $request): Response|RedirectResponse
    {
        $student = $request->user()?->student;
        abort_unless($student, 403, 'Student record not found.');

        // Skip verification if already verified
        if ($student->verification_status === 'verified') {
            return redirect()->route('dashboard');
        }

        return Inertia::render('auth/verify-face', [
            // Only the fields the page needs. The old closure sent the whole Student
            // model to the browser, which can include the face embedding.
            'student' => $student->only(['student_id', 'firstname', 'surname']),

            // A closure, so the challenge is only created when the prop is actually sent
            // (page load and the page's retry reload), not on unrelated partial reloads.
            'challenge' => fn () => $this->challenges->issue(
                $student->student_id,
                $request->session()->getId(),
            ),
        ]);
    }

    /**
     * Verify liveness and identity, then store the 512-D InsightFace embedding.
     */
    public function verifyFace(VerifyFaceRequest $request): RedirectResponse
    {
        $student = $request->user()->student;

        if (! $student) {
            return $this->fail('Student record not found.');
        }

        // Rate limit per student. Every attempt counts, pass or fail.
        $limiterKey = 'face-verify:' . $student->student_id;

        if (RateLimiter::tooManyAttempts($limiterKey, (int) config('face_verification.max_attempts'))) {
            $minutes = max(1, (int) ceil(RateLimiter::availableIn($limiterKey) / 60));
            $this->record('rate_limited', $student, $request);

            return $this->fail("Too many attempts. Please try again in {$minutes} minute(s).");
        }

        RateLimiter::hit($limiterKey, (int) config('face_verification.attempt_decay_seconds'));

        // One verification per student at a time. This also makes the one-time challenge
        // and the duplicate check race-free. The TTL must be longer than the Python timeout.
        $lock = Cache::lock('face-verify-lock:' . $student->student_id, 60);

        if (! $lock->get()) {
            return $this->fail('A verification is already in progress. Please wait a moment.');
        }

        try {
            return $this->processVerification($request, $student, $limiterKey);
        } finally {
            $lock->release();
        }
    }

    private function processVerification(VerifyFaceRequest $request, Student $student, string $limiterKey): RedirectResponse
    {
        // 1. Server-issued, one-time challenge (this also fixes the direction to check).
        $challenge = $this->challenges->consume(
            $student->student_id,
            $request->input('challenge_nonce'),
            $request->session()->getId(),
        );

        if (! $challenge['valid']) {
            $this->record('challenge_invalid', $student, $request, ['reason_code' => $challenge['reason']]);

            return $this->fail(
                $challenge['reason'] === 'expired'
                    ? 'Your verification session expired. Please try again.'
                    : 'Your verification session is invalid. Please try again.'
            );
        }

        $direction = $challenge['direction'];

        // 2. Liveness (pose, direction, same person across frames, anti-spoof) in the Python service.
        try {
            $liveness = $this->biometrics->verifyLiveness(
                $direction,
                $request->file('live_camera_frame'),
                $request->file('turn_peak_frame'),
                $request->file('turn_mid_frame'),
            );
        } catch (BiometricServiceException) {
            $this->record('service_error', $student, $request, ['direction' => $direction]);

            return $this->fail('Unable to reach the biometric verification service. Please try again in a moment.');
        }

        if (! ($liveness['passed'] ?? false)) {
            $this->record('liveness_failed', $student, $request, [
                'direction' => $direction,
                'reason_code' => $liveness['reason_code'] ?? null,
                'metrics' => ['checks' => $liveness['checks'] ?? null],
            ], storeFrames: true);

            // "detail" is written by the Python service to be safe to show to the user.
            return $this->fail($liveness['detail'] ?? 'The liveness check failed. Please try again.');
        }

        $liveEmbedding = $liveness['frontal_embedding'];

        // 3. The straight-on frame must match the uploaded profile photo.
        $profileEmbedding = $this->biometrics->profileEmbedding($student);
        $profileSimilarity = null;

        if ($profileEmbedding !== null) {
            $profileSimilarity = BiometricService::cosineSimilarity($liveEmbedding, $profileEmbedding);

            if ($profileSimilarity < (float) config('face_verification.profile_match_threshold')) {
                $this->record('profile_mismatch', $student, $request, [
                    'direction' => $direction,
                    'metrics' => ['profile_similarity' => round($profileSimilarity, 4), 'checks' => $liveness['checks'] ?? null],
                ], storeFrames: true);

                return $this->fail('Live face does not match the uploaded profile picture. Please try again with proper lighting.');
            }
        } elseif (config('face_verification.require_profile_match')) {
            $this->record('profile_unavailable', $student, $request, ['direction' => $direction]);

            return $this->fail('We could not use your profile photo for comparison. Please contact support to update it.');
        }

        // 4. Duplicate check across all registered students.
        $duplicateThreshold = (float) config('face_verification.duplicate_threshold');

        $existingStudents = Student::query()
            ->whereNotNull('face_embedding')
            ->where('student_id', '!=', $student->student_id)
            ->select(['student_id', 'face_embedding'])
            ->cursor(); // streams rows instead of loading every embedding into memory

        foreach ($existingStudents as $existing) {
            $similarity = BiometricService::cosineSimilarity($liveEmbedding, $existing->face_embedding);

            if ($similarity >= $duplicateThreshold) {
                // The matched student goes to the audit log only. Showing their student number
                // to the user would let anyone look up who is registered.
                $this->record('duplicate', $student, $request, [
                    'direction' => $direction,
                    'metrics' => [
                        'matched_student_id' => $existing->student_id,
                        'duplicate_similarity' => round($similarity, 4),
                    ],
                ], storeFrames: true);

                return $this->fail('This face is already registered to another account. Please contact support if you think this is a mistake.');
            }
        }

        // 5. Save embedding and mark as verified.
        $student->face_embedding = $liveEmbedding;
        $student->verification_status = 'verified';
        $student->save();

        $this->record('passed', $student, $request, [
            'direction' => $direction,
            'metrics' => [
                'profile_similarity' => $profileSimilarity !== null ? round($profileSimilarity, 4) : null,
                'checks' => $liveness['checks'] ?? null,
            ],
        ]);

        RateLimiter::clear($limiterKey);

        return redirect()->route('dashboard')->with('success', 'Biometric registration completed successfully!');
    }

    private function fail(string $message): RedirectResponse
    {
        // The React page reads errors.face
        return back()->withErrors(['face' => $message]);
    }

    private function toBase64(UploadedFile $file): string
    {
        return base64_encode($file->get());
    }

    /**
     * Audit trail. A logging failure must never block or break a verification, so it is wrapped in rescue().
     *
     * @param  array{direction?: string, reason_code?: string, metrics?: array}  $extra
     */
    private function record(string $outcome, Student $student, Request $request, array $extra = [], bool $storeFrames = false): void
    {
        rescue(function () use ($outcome, $student, $request, $extra, $storeFrames) {
            FaceVerificationAttempt::create([
                'student_id' => $student->student_id,
                'user_id' => $request->user()?->getKey(),
                'outcome' => $outcome,
                'reason_code' => $extra['reason_code'] ?? null,
                'direction' => $extra['direction'] ?? null,
                'ip_address' => $request->ip(),
                'user_agent' => Str::limit((string) $request->userAgent(), 255, ''),
                'metrics' => $extra['metrics'] ?? null,
                'frame_paths' => $storeFrames ? $this->storeFrames($request, $student) : null,
            ]);
        });
    }

    /** Only stores anything when FACE_STORE_FAILED_FRAMES=true. Returns the stored paths. */
    private function storeFrames(Request $request, Student $student): ?array
    {
        if (! config('face_verification.store_failed_frames')) {
            return null;
        }

        $directory = "face-attempts/{$student->student_id}/" . Str::uuid();
        $paths = [];

        foreach (['live_camera_frame' => 'frontal', 'turn_mid_frame' => 'mid', 'turn_peak_frame' => 'peak'] as $field => $label) {
            if ($file = $request->file($field)) {
                $paths[$label] = $file->storeAs($directory, "{$label}.jpg", 'private');
            }
        }

        return $paths ?: null;
    }
}