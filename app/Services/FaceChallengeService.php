<?php

namespace App\Services;

use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Str;

/**
 * Issues one-time server-controlled liveness challenges.
 *
 * The direction returned to the mobile app is the same direction consumed by
 * the final verification request. A challenge is single-use and bound to the
 * student, client session id, scope, and optional context (event id).
 */
class FaceChallengeService
{
    /**
     * @return array{nonce: string, direction: string, expires_at: int}
     */
    public function issue(
        int $studentId,
        string $sessionId,
        string $scope = 'registration',
        ?int $contextId = null,
    ): array {
        $ttl = (int) config('face_verification.challenge_ttl');

        $challenge = [
            'nonce' => Str::random(40),
            'direction' => random_int(0, 1) === 0 ? 'left' : 'right',
            'expires_at' => now()->addSeconds($ttl)->timestamp,
        ];

        Cache::put(
            $this->key($studentId, $scope, $contextId),
            $challenge + [
                'session_hash' => hash('sha256', $sessionId),
                'scope' => $scope,
                'context_id' => $contextId,
            ],
            $ttl + 30,
        );

        return $challenge;
    }

    /**
     * @return array{valid: bool, reason: ?string, direction: ?string}
     */
    public function consume(
        int $studentId,
        ?string $nonce,
        string $sessionId,
        string $scope = 'registration',
        ?int $contextId = null,
    ): array {
        $stored = Cache::pull($this->key($studentId, $scope, $contextId));

        if (! is_array($stored)) {
            return $this->invalid('missing');
        }
        if (($stored['expires_at'] ?? 0) < now()->timestamp) {
            return $this->invalid('expired');
        }
        if (! is_string($nonce) || ! isset($stored['nonce']) || ! hash_equals($stored['nonce'], $nonce)) {
            return $this->invalid('nonce_mismatch');
        }
        if (! isset($stored['session_hash']) || ! hash_equals($stored['session_hash'], hash('sha256', $sessionId))) {
            return $this->invalid('session_mismatch');
        }

        return [
            'valid' => true,
            'reason' => null,
            'direction' => $stored['direction'],
        ];
    }

    private function invalid(string $reason): array
    {
        return ['valid' => false, 'reason' => $reason, 'direction' => null];
    }

    private function key(int $studentId, string $scope, ?int $contextId): string
    {
        $context = $contextId === null ? 'none' : (string) $contextId;

        return "face_challenge:{$scope}:{$studentId}:{$context}";
    }
}
