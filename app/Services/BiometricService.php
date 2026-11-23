<?php

namespace App\Services;

use App\Exceptions\BiometricServiceException;
use App\Models\Student;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\PendingRequest;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;

class BiometricService
{
    /**
     * @param UploadedFile[] $flashFrames frame i belongs to $flashColors[i]
     * @param string[]       $flashColors taken from the STORED challenge, never from the request
     */
    public function verifyLiveness(
        string $direction,
        UploadedFile $frontal,
        UploadedFile $turnPeak,
        array $flashFrames,
        array $flashColors,
        ?string $cameraLabel = null,
    ): array {
        ksort($flashFrames);
        $flashFrames = array_values($flashFrames);

        $payload = [
            'direction'             => $direction,
            'frontal_image_base64'   => $this->fileToDataUrl($frontal),
            'turn_peak_image_base64' => $this->fileToDataUrl($turnPeak),
            'flash_images_base64'    => array_map(fn (UploadedFile $f) => $this->fileToDataUrl($f), $flashFrames),
            'flash_colors'           => array_values($flashColors),
        ];

        if ($cameraLabel) {
            $payload['camera_label'] = $cameraLabel;
        }

        $data = $this->post('/verify-liveness', $payload);

        if (! array_key_exists('passed', $data)) {
            throw new BiometricServiceException('Unexpected liveness response.');
        }

        return $data;
    }

    /**
     * Verify liveness challenge frames and extract the facial embedding from the frontal frame.
     */
    public function verifyLivenessAndExtractEmbedding(
        UploadedFile $frontal,
        array $flashFrames,
        UploadedFile $turnPeak,
        string $direction,
        array $flashColors,
        ?string $cameraLabel = null
    ): array {
        // 1. Run liveness anti-spoofing check
        $livenessResult = $this->verifyLiveness(
            $direction,
            $frontal,
            $turnPeak,
            $flashFrames,
            $flashColors,
            $cameraLabel
        );

        if (empty($livenessResult['passed']) || $livenessResult['passed'] !== true) {
            throw new BiometricServiceException($livenessResult['message'] ?? 'Liveness anti-spoofing check failed.');
        }

        // 2. Extract facial embedding from the verified frontal frame
        try {
            $data = $this->post('/extract-embedding', [
                'image_base64' => base64_encode($frontal->get()),
            ]);
        } catch (\Throwable $e) {
            throw new BiometricServiceException('Failed to extract facial embedding after liveness verification.');
        }

        $embedding = $data['embedding'] ?? null;
        if (!is_array($embedding)) {
            throw new BiometricServiceException('Invalid embedding returned by biometric service.');
        }

        return $embedding;
    }

    public function profileEmbedding(Student $student): ?array
    {
        if (! $student->face_photo_path) {
            return null;
        }

        $disk = Storage::disk('private');
        $path = ltrim(str_replace(['/storage/', 'storage/'], '', $student->face_photo_path), '/');

        if (! $disk->exists($path)) {
            return null;
        }

        $key = 'face_profile_embedding:' . $student->student_id . ':' . md5($path . '|' . $disk->lastModified($path));
        $cached = Cache::get($key);

        if (is_array($cached)) {
            return $cached;
        }

        try {
            $data = $this->post('/extract-embedding', [
                'image_base64' => base64_encode($disk->get($path)),
            ]);
        } catch (BiometricServiceException) {
            return null;
        }

        $embedding = $data['embedding'] ?? null;
        if (! is_array($embedding)) {
            return null;
        }

        Cache::put($key, $embedding, now()->addDays(30));

        return $embedding;
    }

    public static function cosineSimilarity(array $a, array $b): float
    {
        if (! $a || count($a) !== count($b)) {
            return 0.0;
        }

        $dot = $na = $nb = 0.0;

        foreach ($a as $i => $v) {
            if (! is_numeric($v) || ! isset($b[$i]) || ! is_numeric($b[$i])) {
                return 0.0;
            }
            $x = (float) $v;
            $y = (float) $b[$i];
            $dot += $x * $y;
            $na += $x * $x;
            $nb += $y * $y;
        }

        return ($na <= 0.0 || $nb <= 0.0) ? 0.0 : $dot / (sqrt($na) * sqrt($nb));
    }

    private function fileToDataUrl(UploadedFile $file): string
    {
        $bytes = $file->get();
        if ($bytes === '') {
            throw new BiometricServiceException('The supplied image is empty.');
        }

        return 'data:image/jpeg;base64,' . base64_encode($bytes);
    }

    private function post(string $endpoint, array $payload): array
    {
        try {
            $response = $this->client()->post($endpoint, $payload);
        } catch (ConnectionException $e) {
            Log::error('Biometric service unreachable', ['error' => $e->getMessage()]);
            throw new BiometricServiceException('Biometric service unreachable.', 0, $e);
        }

        if ($response->failed()) {
            throw new BiometricServiceException($response->json('detail') ?? 'Biometric service returned an error.');
        }

        $data = $response->json();
        if (! is_array($data)) {
            throw new BiometricServiceException('Biometric service returned invalid JSON.');
        }

        return $data;
    }

    private function client(): PendingRequest
    {
        $client = Http::baseUrl(rtrim(config('face_verification.python_url'), '/'))
            ->connectTimeout(5)
            ->timeout((int) config('face_verification.python_timeout'))
            ->acceptJson();

        if ($token = config('face_verification.python_token')) {
            $client = $client->withHeader('X-Internal-Token', $token);
        }

        return $client;
    }
}