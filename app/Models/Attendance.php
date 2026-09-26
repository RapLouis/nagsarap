<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Attendance extends Model
{
    use HasFactory;

    protected $primaryKey = 'attendance_id';

    protected $fillable = [
        'attendance_uuid','student_id','event_id','logged_at','attendance_time','sync_time',
        'status','sync_status','source','confidence_score','liveness_passed','liveness_method',
        'latitude','longitude','location_accuracy','distance_from_event','location_verified_at',
    ];

    protected $casts = [
        'logged_at' => 'datetime', 'attendance_time' => 'datetime', 'sync_time' => 'datetime',
        'location_verified_at' => 'datetime', 'liveness_passed' => 'boolean',
        'latitude' => 'float', 'longitude' => 'float', 'location_accuracy' => 'float',
        'distance_from_event' => 'float', 'confidence_score' => 'float',
    ];

    public function student(): BelongsTo { return $this->belongsTo(Student::class, 'student_id', 'student_id'); }
    public function event(): BelongsTo { return $this->belongsTo(Event::class, 'event_id', 'event_id'); }
}
