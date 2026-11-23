<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Python biometric microservice
    |--------------------------------------------------------------------------
    */
    'python_url'     => env('BIOMETRIC_SERVICE_URL', 'http://127.0.0.1:5000'),
    'python_token'   => env('BIOMETRIC_SERVICE_TOKEN'),
    'python_timeout' => (int) env('BIOMETRIC_SERVICE_TIMEOUT', 60),

    /*
    |--------------------------------------------------------------------------
    | Challenge TTL (server-issued, single-use nonces)
    |--------------------------------------------------------------------------
    | Long enough for the flashes and a 20 s head turn. The page also asks for a
    | fresh challenge when the student presses "start", so the clock starts then.
    */
    'challenge_ttl' => (int) env('FACE_CHALLENGE_TTL', 300),

    /*
    |--------------------------------------------------------------------------
    | Rate limiting
    |--------------------------------------------------------------------------
    */
    'max_attempts'          => (int) env('FACE_MAX_ATTEMPTS', 5),
    'attempt_decay_seconds' => (int) env('FACE_ATTEMPT_DECAY', 600),

    /*
    |--------------------------------------------------------------------------
    | Cosine similarity thresholds
    |--------------------------------------------------------------------------
    */
    'profile_match_threshold' => (float) env('FACE_PROFILE_MATCH_THRESHOLD', 0.50),
    'duplicate_threshold'     => (float) env('FACE_DUPLICATE_THRESHOLD', 0.50),
    'require_profile_match'   => (bool) env('FACE_REQUIRE_PROFILE_MATCH', true),

    /*
    |--------------------------------------------------------------------------
    | Audit logging
    |--------------------------------------------------------------------------
    | Failed frames are biometric data. Keep them only while calibrating and
    | delete them on a schedule.
    */
    'store_failed_frames'  => (bool) env('FACE_STORE_FAILED_FRAMES', false),
    'frame_retention_days' => (int) env('FACE_FRAME_RETENTION_DAYS', 7),
];