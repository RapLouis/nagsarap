<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Python biometric microservice
    |--------------------------------------------------------------------------
    | BIOMETRIC_SERVICE_TOKEN must equal INTERNAL_API_TOKEN on the Python side.
    */
    'python_url' => env('BIOMETRIC_SERVICE_URL', 'http://127.0.0.1:5000'),
    'python_token' => env('BIOMETRIC_SERVICE_TOKEN'),
    'python_timeout' => (int) env('BIOMETRIC_SERVICE_TIMEOUT', 30), // seconds; 3 frames on CPU need more than 10

    /*
    |--------------------------------------------------------------------------
    | Challenge (server-issued, one-time use)
    |--------------------------------------------------------------------------
    */
    'challenge_ttl' => (int) env('FACE_CHALLENGE_TTL', 120), // seconds

    /*
    |--------------------------------------------------------------------------
    | Rate limiting (per student)
    |--------------------------------------------------------------------------
    */
    'max_attempts' => (int) env('FACE_MAX_ATTEMPTS', 5),
    'attempt_decay_seconds' => (int) env('FACE_ATTEMPT_DECAY', 600),

    /*
    |--------------------------------------------------------------------------
    | Matching thresholds (cosine similarity)
    |--------------------------------------------------------------------------
    */
    'profile_match_threshold' => (float) env('FACE_PROFILE_MATCH_THRESHOLD', 0.50),
    'duplicate_threshold' => (float) env('FACE_DUPLICATE_THRESHOLD', 0.60),

    // true  = verification fails if the profile photo is missing or unreadable (recommended).
    // false = old behaviour: skip the profile-photo match in that case.
    'require_profile_match' => (bool) env('FACE_REQUIRE_PROFILE_MATCH', true),

    /*
    |--------------------------------------------------------------------------
    | Audit
    |--------------------------------------------------------------------------
    | Camera frames are biometric data. Keep this off unless you have a reason,
    | a retention period, and the consent to hold them.
    */
    'store_failed_frames' => (bool) env('FACE_STORE_FAILED_FRAMES', false),
];