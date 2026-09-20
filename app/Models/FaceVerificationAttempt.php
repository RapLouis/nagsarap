<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class FaceVerificationAttempt extends Model
{
    protected $fillable = [
        'student_id',
        'user_id',
        'outcome',
        'reason_code',
        'direction',
        'ip_address',
        'user_agent',
        'metrics',
        'frame_paths',
    ];

    protected $casts = [
        'metrics' => 'array',
        'frame_paths' => 'array',
    ];
}