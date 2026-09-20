<?php

namespace App\Services;

use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Str;

/**
 * Issues and validates the liveness challenge (random nonce + random turn direction).
 *
 * The direction that counts is always the one stored here on the server. Whatever
 * direction the browser reports is ignored.
 *
 * Needs a shared cache store (redis, database, or file on a single server), not "array".
 */
class FaceChallengeService
{
    /**
     * Create a new challenge for the student. Only one is active per student, so
     * issuing a new one invalidates the previous one.
     *
     * @return array{nonce: string, direction: string, expires_at: int}
     */
    public function issue(int $studentId, string $sessionId): array
    {
        $ttl = (int) config('face_verification.challenge_ttl');

        $challenge = [
            'nonce' => Str::random(40),
            'direction' => random_int(0, 1) === 0 ? 'left' : 'right',
            'expires_at' => now()->addSeconds($ttl)->timestamp,
        ];

        Cache::put(
            $this->key($studentId),
            $challenge + ['session_hash' => hash('sha256', $sessionId)],
            $ttl + 30,
        );

        return $challenge;
    }

    /**
     * Validate and CONSUME the challenge. It is deleted whether or not it is valid,
     * so every attempt needs a fresh challenge and a nonce can never be replayed.
     *
     * @return array{valid: bool, reason: ?string, direction: ?string}
     */
    public function consume(int $studentId, ?string $nonce, string $sessionId): array
    {
        $stored = Cache::pull($this->key($studentId));

        if (! is_array($stored)) {
            return $this->invalid('missing');
        }
        if (($stored['expires_at'] ?? 0) < now()->timestamp) {
            return $this->invalid('expired');
        }
        if (! is_string($nonce) || ! hash_equals($stored['nonce'], $nonce)) {
            return $this->invalid('nonce_mismatch');
        }
        if (! hash_equals($stored['session_hash'], hash('sha256', $sessionId))) {
            return $this->invalid('session_mismatch');
        }

        return ['valid' => true, 'reason' => null, 'direction' => $stored['direction']];
    }

    private function invalid(string $reason): array
    {
        return ['valid' => false, 'reason' => $reason, 'direction' => null];
    }

    private function key(int $studentId): string
    {
        return "face_challenge:{$studentId}";
    }
}