<?php

namespace App\Models;

use Carbon\Carbon;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Event extends Model
{
    use HasFactory;

    protected $primaryKey = 'event_id';

    protected $fillable = [
        'title',
        'description',
        'location',
        'is_geofenced',
        'geofence_type',
        'latitude',
        'longitude',
        'radius_meters',
        'geofence_polygon',
        'is_active',
        'approval_status',
    ];

    protected $casts = [
        'event_id'         => 'integer',
        'is_active'        => 'boolean',
        'is_geofenced'     => 'boolean',
        'latitude'         => 'float',
        'longitude'        => 'float',
        'radius_meters'    => 'integer',
        'geofence_polygon' => 'array',
    ];

    // =========================================================================
    // HYBRID GEOFENCE VERIFICATION
    // =========================================================================

    public function isWithinGeofence(float $userLat, float $userLng): bool
    {
        if (!$this->is_geofenced) {
            return true;
        }

        if ($this->geofence_type === 'polygon' && !empty($this->geofence_polygon)) {
            return $this->isPointInPolygon($userLat, $userLng, $this->geofence_polygon);
        }

        return $this->isPointInRadius($userLat, $userLng);
    }

    protected function isPointInRadius(float $userLat, float $userLng): bool
    {
        if (is_null($this->latitude) || is_null($this->longitude)) {
            return true;
        }

        $earthRadius = 6371000;

        $latFrom = deg2rad($userLat);
        $lngFrom = deg2rad($userLng);
        $latTo   = deg2rad($this->latitude);
        $lngTo   = deg2rad($this->longitude);

        $latDelta = $latTo - $latFrom;
        $lngDelta = $lngTo - $lngFrom;

        $angle = 2 * asin(sqrt(
            pow(sin($latDelta / 2), 2) +
            cos($latFrom) * cos($latTo) * pow(sin($lngDelta / 2), 2)
        ));

        return ($angle * $earthRadius) <= $this->radius_meters;
    }

    protected function isPointInPolygon(float $userLat, float $userLng, array $polygon): bool
    {
        $verticesCount = count($polygon);
        if ($verticesCount < 3) {
            return false;
        }

        $inside = false;

        for ($i = 0, $j = $verticesCount - 1; $i < $verticesCount; $j = $i++) {
            $xi = $polygon[$i]['lng'] ?? $polygon[$i][1];
            $yi = $polygon[$i]['lat'] ?? $polygon[$i][0];
            $xj = $polygon[$j]['lng'] ?? $polygon[$j][1];
            $yj = $polygon[$j]['lat'] ?? $polygon[$j][0];

            $denom = ($yj - $yi);
            if ($denom == 0) {
                continue;
            }

            $intersect = (($yi > $userLat) !== ($yj > $userLat)) &&
                ($userLng < ($xj - $xi) * ($userLat - $yi) / $denom + $xi);

            if ($intersect) {
                $inside = !$inside;
            }
        }

        return $inside;
    }

    // =========================================================================
    // DYNAMIC TIME WINDOW ACCESSORS (Child Table Aware)
    // =========================================================================

    public function getWindowStartAttribute(): Carbon
    {
        $days = $this->relationLoaded('days') ? $this->days : $this->days()->get();
        
        $earliest = null;
        foreach ($days as $day) {
            $slots = $day->slots ?? [];
            foreach ($slots as $slot) {
                if (!empty($slot['time_in_start'])) {
                    $dateStr = $day->event_date instanceof Carbon ? $day->event_date->format('Y-m-d') : $day->event_date;
                    $dateTime = "{$dateStr} {$slot['time_in_start']}";
                    if (!$earliest || $dateTime < $earliest) {
                        $earliest = $dateTime;
                    }
                }
            }
        }

        if ($earliest) {
            return Carbon::parse($earliest)->subHours(2);
        }

        return now()->subHours(2);
    }

    public function getWindowEndAttribute(): Carbon
    {
        $days = $this->relationLoaded('days') ? $this->days : $this->days()->get();
        
        $latest = null;
        foreach ($days as $day) {
            $slots = $day->slots ?? [];
            foreach ($slots as $slot) {
                $time = $slot['time_out_end'] ?? $slot['time_out_start'] ?? null;
                if ($time) {
                    $dateStr = $day->event_date instanceof Carbon ? $day->event_date->format('Y-m-d') : $day->event_date;
                    $dateTime = "{$dateStr} {$time}";
                    if (!$latest || $dateTime > $latest) {
                        $latest = $dateTime;
                    }
                }
            }
        }

        if ($latest) {
            return Carbon::parse($latest)->addHours(2);
        }

        return now()->addHours(2);
    }

    // =========================================================================
    // ELOQUENT QUERY SCOPES (Child Table Date-Range Aware)
    // =========================================================================

    public function scopeOngoing(Builder $query): Builder
    {
        $today = now()->toDateString();

        return $query->where('approval_status', 'approved')
            ->whereHas('days', function ($q) use ($today) {
                $q->where('event_date', '=', $today);
            });
    }

    public function scopeUpcoming(Builder $query): Builder
    {
        $today = now()->toDateString();

        return $query->where('approval_status', 'approved')
            ->whereHas('days', function ($q) use ($today) {
                $q->where('event_date', '>', $today);
            });
    }

    public function scopeCompleted(Builder $query): Builder
    {
        $today = now()->toDateString();

        return $query->where('approval_status', 'approved')
            ->whereHas('days', function ($q) use ($today) {
                $q->where('event_date', '<', $today);
            });
    }

    public function scopePending(Builder $query): Builder
    {
        return $query->where('approval_status', 'pending');
    }

    public function scopeDeclined(Builder $query): Builder
    {
        return $query->where('approval_status', 'declined');
    }

    // =========================================================================
    // RELATIONSHIPS
    // =========================================================================

    public function days(): HasMany
    {
        return $this->hasMany(EventDay::class, 'event_id', 'event_id');
    }

    public function attendances(): HasMany
    {
        return $this->hasMany(Attendance::class, 'event_id', 'event_id');
    }

    public function students(): BelongsToMany
    {
        return $this->belongsToMany(Student::class, 'attendances', 'event_id', 'student_id')
            ->withPivot('status', 'confidence_score', 'logged_at')
            ->withTimestamps();
    }
}