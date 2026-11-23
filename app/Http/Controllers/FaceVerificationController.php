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
    ) {}

    public function show(Request $request): Response|RedirectResponse
    {
        $student = $request->user()?->student;
        abort_unless($student, 403, 'Student record not found.');

        if ($student->verification_status === 'verified') {
            return redirect()->route('dashboard');
        }

        return Inertia::render('auth/verify-face', [
            'student'   => $student->only(['student_id', 'firstname', 'surname']),
            'challenge' => fn () => $this->challenges->issue(
                $student->student_id,
                $request->session()->getId(),
            ),
        ]);
    }

    public function verifyFace(VerifyFaceRequest $request): RedirectResponse
    {
        $student = $request->user()?->student;

        if (! $student) {
            return $this->fail('Student record not found.');
        }

        if (! $student->face_photo_path) {
            return $this->fail('No selfie reference photo found. Please complete initial registration.');
        }

        $limiterKey = 'face-verify:' . $student->student_id;

        if (RateLimiter::tooManyAttempts($limiterKey, (int) config('face_verification.max_attempts', 5))) {
            $minutes = max(1, (int) ceil(RateLimiter::availableIn($limiterKey) / 60));
            $this->record('rate_limited', $student, $request);

            return $this->fail("Too many verification attempts. Please try again in {$minutes} minute(s).");
        }

        RateLimiter::hit($limiterKey, (int) config('face_verification.attempt_decay_seconds', 600));

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

        $direction = $challenge['direction'] ?? 'left';
        $flashColors = $challenge['flash_colors'] ?? ['red', 'green', 'blue'];

        try {
            $liveness = $this->biometrics->verifyLiveness(
                $direction,
                $request->file('live_camera_frame'),
                $request->file('turn_peak_frame'),
                $request->file('flash_frames') ?? [],
                $flashColors,
                cameraLabel: $request->input('camera_label'),
            );
        } catch (BiometricServiceException $e) {
            $this->record('service_error', $student, $request, [
                'direction' => $direction,
                'metrics'   => ['error' => $e->getMessage()],
            ]);

            return $this->fail('Unable to reach the biometric verification service. Please try again.');
        }

        if (! ($liveness['passed'] ?? false)) {
            $this->record('liveness_failed', $student, $request, [
                'direction'   => $direction,
                'reason_code' => $liveness['reason_code'] ?? null,
                'metrics'     => [
                    'checks'       => $liveness['checks'] ?? null,
                    'review_flags' => $liveness['review_flags'] ?? [],
                ],
            ], storeFrames: true);

            return $this->fail($liveness['detail'] ?? 'The liveness check failed. Please try again.');
        }

        $liveEmbedding = $liveness['frontal_embedding'];

        $profileEmbedding = $this->biometrics->profileEmbedding($student);
        $profileSimilarity = null;

        if ($profileEmbedding === null) {
            if (config('face_verification.require_profile_match', true)) {
                $this->record('profile_unavailable', $student, $request, ['direction' => $direction]);

                return $this->fail('We could not read your registered profile photo. Please contact staff.');
            }
        } else {
            $profileSimilarity = BiometricService::cosineSimilarity($liveEmbedding, $profileEmbedding);

            if ($profileSimilarity < (float) config('face_verification.profile_match_threshold', 0.50)) {
                $this->record('profile_mismatch', $student, $request, [
                    'direction' => $direction,
                    'metrics'   => [
                        'profile_similarity' => round($profileSimilarity, 4),
                        'checks'             => $liveness['checks'] ?? null,
                    ],
                ], storeFrames: true);

                return $this->fail('Live face does not match your registered profile selfie.');
            }
        }

        $duplicateThreshold = (float) config('face_verification.duplicate_threshold', 0.50);

        $existingStudents = Student::query()
            ->whereNotNull('face_embedding')
            ->where('student_id', '!=', $student->student_id)
            ->where('verification_status', 'verified')
            ->select(['student_id', 'face_embedding'])
            ->cursor();

        foreach ($existingStudents as $existing) {
            $similarity = BiometricService::cosineSimilarity($liveEmbedding, (array) $existing->face_embedding);

            if ($similarity >= $duplicateThreshold) {
                $this->record('duplicate', $student, $request, [
                    'direction' => $direction,
                    'metrics'   => [
                        'matched_student_id'   => $existing->student_id,
                        'duplicate_similarity' => round($similarity, 4),
                    ],
                ], storeFrames: true);

                return $this->fail('This face is already registered to another account.');
            }
        }

        $student->face_embedding = $liveEmbedding;
        $student->verification_status = 'verified';
        $student->save();

        $this->record('passed', $student, $request, [
            'direction' => $direction,
            'metrics'   => [
                'profile_similarity' => $profileSimilarity !== null ? round($profileSimilarity, 4) : null,
                'checks'             => $liveness['checks'] ?? null,
            ],
        ]);

        RateLimiter::clear($limiterKey);

        return redirect()->route('dashboard')->with('success', 'Biometric face verification completed successfully!');
    }

    private function fail(string $message): RedirectResponse
    {
        return back()->withErrors(['face' => $message]);
    }

    private function record(string $outcome, Student $student, Request $request, array $extra = [], bool $storeFrames = false): void
    {
        rescue(function () use ($outcome, $student, $request, $extra, $storeFrames) {
            FaceVerificationAttempt::create([
                'student_id'  => $student->student_id,
                'user_id'     => $request->user()?->getKey(),
                'outcome'     => $outcome,
                'reason_code' => $extra['reason_code'] ?? null,
                'direction'   => $extra['direction'] ?? null,
                'ip_address'  => $request->ip(),
                'user_agent'  => Str::limit((string) $request->userAgent(), 255, ''),
                'metrics'     => $extra['metrics'] ?? null,
                'frame_paths' => $storeFrames ? $this->storeFrames($request, $student) : null,
            ]);
        });
    }

    private function storeFrames(Request $request, Student $student): ?array
    {
        if (! config('face_verification.store_failed_frames', false)) {
            return null;
        }

        $directory = "face-attempts/{$student->student_id}/" . Str::uuid();
        $paths = [];

        foreach (['live_camera_frame' => 'frontal', 'turn_peak_frame' => 'turn_peak'] as $field => $label) {
            if ($file = $request->file($field)) {
                $paths[$label] = $file->storeAs($directory, "{$label}.jpg", 'private');
            }
        }

        foreach ($request->file('flash_frames', []) ?? [] as $index => $file) {
            $paths["flash_{$index}"] = $file->storeAs($directory, "flash_{$index}.jpg", 'private');
        }

        return $paths ?: null;
    }
}