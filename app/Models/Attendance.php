<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Attendance extends Model
{
    use HasFactory;

    protected $primaryKey = 'attendance_id';

    // Supported Checkpoint Key Constants
    public const MORNING_TIME_IN = 'morning_time_in';
    public const MORNING_TIME_OUT = 'morning_time_out';
    public const AFTERNOON_TIME_IN = 'afternoon_time_in';
    public const AFTERNOON_TIME_OUT = 'afternoon_time_out';

    public const CHECKPOINTS = [
        self::MORNING_TIME_IN,
        self::MORNING_TIME_OUT,
        self::AFTERNOON_TIME_IN,
        self::AFTERNOON_TIME_OUT,
    ];

    protected $fillable = [
        'attendance_uuid',
        'student_id',
        'event_id',
        'event_date',
        'slot_index',
        'type',
        'checkpoint_key',
        'logged_at',
        'attendance_time',
        'sync_time',
        'status',
        'sync_status',
        'source',
        'confidence_score',
        'liveness_passed',
        'liveness_method',
        'latitude',
        'longitude',
        'location_accuracy',
        'distance_from_event',
        'location_verified_at',
    ];

    protected $casts = [
        'logged_at' => 'datetime',
        'attendance_time' => 'datetime',
        'sync_time' => 'datetime',
        'location_verified_at' => 'datetime',
        'liveness_passed' => 'boolean',
        'latitude' => 'float',
        'longitude' => 'float',
        'location_accuracy' => 'float',
        'distance_from_event' => 'float',
        'confidence_score' => 'float',
        // Note: intentionally omitting 'event_date' from date casts to prevent UTC timezone shifting
    ];

    public function student(): BelongsTo 
    { 
        return $this->belongsTo(Student::class, 'student_id', 'student_id'); 
    }

    public function event(): BelongsTo 
    { 
        return $this->belongsTo(Event::class, 'event_id', 'event_id'); 
    }
}