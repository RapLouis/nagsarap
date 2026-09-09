<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Event extends Model
{
    protected $table = 'events';

    /*
    |--------------------------------------------------------------------------
    | IMPORTANT
    |--------------------------------------------------------------------------
    |
    | Your database uses event_id, not Laravel's default id.
    |
    */

    protected $primaryKey = 'event_id';

    public $incrementing = true;

    protected $keyType = 'int';

    protected $fillable = [
        'title',
        'description',
        'event_date',
        'start_time',
        'end_time',
        'location',
        'latitude',
        'longitude',
        'geofence_radius',
        'geofence_enabled',
        'late_after_minutes',
        'is_active',
    ];

    protected $casts = [
        'event_id' => 'integer',

        /*
         * Keep event_date as a date.
         * Flutter will safely normalize the JSON date value.
         */
        'event_date' => 'date:Y-m-d',

        'latitude' => 'float',
        'longitude' => 'float',

        'geofence_radius' => 'integer',

        'geofence_enabled' => 'boolean',

        'late_after_minutes' => 'integer',

        'is_active' => 'boolean',
    ];

    /*
    |--------------------------------------------------------------------------
    | Attendance relationship
    |--------------------------------------------------------------------------
    */

    public function attendances(): HasMany
    {
        return $this->hasMany(
            Attendance::class,
            'event_id',
            'event_id'
        );
    }

    /*
    |--------------------------------------------------------------------------
    | Students who attended this event
    |--------------------------------------------------------------------------
    */

    public function students(): BelongsToMany
    {
        return $this
            ->belongsToMany(
                Student::class,
                'attendances',
                'event_id',
                'student_id',
                'event_id',
                'student_id'
            )
            ->withPivot([
                'status',
                'confidence_score',
                'logged_at',
                'attendance_time',
                'sync_time',
            ])
            ->withTimestamps();
    }
}