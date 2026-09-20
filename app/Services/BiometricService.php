<?php

namespace App\Services;

use App\Exceptions\BiometricServiceException;
use App\Models\Student;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\PendingRequest;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;

/** Thin client for the Python (Flask + InsightFace) microservice. */
class BiometricService
{
    /**
     * Rotation liveness check over 2-3 frames.
     *
     * @param  string  $direction  "left" or "right" (from the server-issued challenge)
     * @return array  Python's JSON: passed, detail, reason_code, frontal_embedding, checks
     *
     * @throws BiometricServiceException when the service is down or answers unexpectedly
     */
    public function verifyLiveness(string $direction, string $frontalB64, string $peakB64, ?string $midB64): array
    {
        $payload = array_filter([
            'direction' => $direction,
            'frontal_image_base64' => $frontalB64,
            'peak_image_base64' => $peakB64,
            'mid_image_base64' => $midB64,
        ], fn ($value) => $value !== null);

        $data = $this->post('/verify-liveness', $payload);

        if (! array_key_exists('passed', $data)) {
            Log::error('Biometric service returned an unexpected liveness response.');
            throw new BiometricServiceException('Unexpected response from biometric service.');
        }

        return $data;
    }

    /**
     * 512-D embedding of the student's stored profile photo, cached so it is only
     * computed once per photo. Returns null if there is no usable photo.
     */
    public function profileEmbedding(Student $student): ?array
    {
        $disk = Storage::disk('private');

        if (! $student->face_photo_path) {
            return null;
        }

        // Same normalisation as the student.face-photo route in web.php: some stored
        // paths carry a "storage/" prefix that is not part of the private disk path.
        $path = ltrim(str_replace(['/storage/', 'storage/'], '', $student->face_photo_path), '/');

        if (! $disk->exists($path)) {
            return null;
        }

        // The key changes when the photo changes, so a new upload is never matched against a stale embedding.
        $cacheKey = 'face_profile_embedding:' . $student->student_id . ':' . md5($path . '|' . $disk->lastModified($path));

        $cached = Cache::get($cacheKey);
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

        Cache::put($cacheKey, $embedding, now()->addDays(30));

        return $embedding;
    }

    public static function cosineSimilarity(array $a, array $b): float
    {
        $count = count($a);
        if ($count === 0 || $count !== count($b)) {
            return 0.0;
        }

        $dot = 0.0;
        $normA = 0.0;
        $normB = 0.0;

        for ($i = 0; $i < $count; $i++) {
            $dot += $a[$i] * $b[$i];
            $normA += $a[$i] ** 2;
            $normB += $b[$i] ** 2;
        }

        if ($normA == 0.0 || $normB == 0.0) {
            return 0.0;
        }

        return $dot / (sqrt($normA) * sqrt($normB));
    }

    private function post(string $endpoint, array $payload): array
    {
        try {
            $response = $this->client()->post($endpoint, $payload);
        } catch (ConnectionException $e) {
            Log::error('Biometric service unreachable: ' . $e->getMessage());
            throw new BiometricServiceException('Biometric service unreachable.', 0, $e);
        }

        if ($response->failed()) {
            Log::warning('Biometric service error', [
                'endpoint' => $endpoint,
                'status' => $response->status(),
                'detail' => $response->json('detail'),
            ]);
            throw new BiometricServiceException('Biometric service returned an error.');
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
            ->timeout((int) config('face_verification.python_timeout'))
            ->acceptJson();

        if ($token = config('face_verification.python_token')) {
            $client = $client->withHeaders(['X-Internal-Token' => $token]);
        }

        return $client;
    }
}