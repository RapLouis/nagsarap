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

    // Explicitly define custom primary key to match migration
    protected $primaryKey = 'event_id';

    protected $fillable = [
        'title',
        'description',
        'event_date',
        'event_end_date', // <--- Added for "from-to" date range
        'location',
        'is_geofenced',
        'geofence_type',
        'latitude',
        'longitude',
        'radius_meters',
        'geofence_polygon',
        'time_in_start',
        'time_in_end',
        'time_out_start',
        'time_out_end',
        'is_active',
        'approval_status',
    ];

    protected $casts = [
        'event_id'         => 'integer',
        'event_date'       => 'date:Y-m-d',
        'event_end_date'   => 'date:Y-m-d', // <--- Added cast
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

    /**
     * Check if user coordinates fall within the event's geofence.
     * Routes automatically to Polygon or Radius check based on configuration.
     */
    public function isWithinGeofence(float $userLat, float $userLng): bool
    {
        if (!$this->is_geofenced) {
            return true; // Access granted automatically if geofencing is disabled
        }

        // Polygon Check (Custom Area Boundary)
        if ($this->geofence_type === 'polygon' && !empty($this->geofence_polygon)) {
            return $this->isPointInPolygon($userLat, $userLng, $this->geofence_polygon);
        }

        // Radius Check (Haversine Formula)
        return $this->isPointInRadius($userLat, $userLng);
    }

    /**
     * Radius Check: Haversine distance calculation in meters.
     */
    protected function isPointInRadius(float $userLat, float $userLng): bool
    {
        if (is_null($this->latitude) || is_null($this->longitude)) {
            return true;
        }

        $earthRadius = 6371000; // Radius of Earth in meters

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

        $distance = $angle * $earthRadius;

        return $distance <= $this->radius_meters;
    }

    /**
     * Polygon Check: Ray-Casting Algorithm for 2D Point-in-Polygon validation.
     * $polygon format: [ ['lat' => x, 'lng' => y], ... ]
     */
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
                continue; // Skip horizontal collinear segments to prevent division by zero
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
    // DYNAMIC TIME WINDOW ACCESSORS
    // =========================================================================

    public function getWindowStartAttribute(): Carbon
    {
        $dateStr = $this->event_date instanceof Carbon 
            ? $this->event_date->format('Y-m-d') 
            : $this->event_date;

        return Carbon::parse("{$dateStr} {$this->time_in_start}")->subHours(2);
    }

    public function getWindowEndAttribute(): Carbon
    {
        // Use event_end_date if available, otherwise fall back to event_date
        $endDate = $this->event_end_date 
            ? ($this->event_end_date instanceof Carbon ? $this->event_end_date->format('Y-m-d') : $this->event_end_date)
            : ($this->event_date instanceof Carbon ? $this->event_date->format('Y-m-d') : $this->event_date);

        if ($this->time_out_end) {
            return Carbon::parse("{$endDate} {$this->time_out_end}")->addHours(2);
        }

        if ($this->time_out_start) {
            return Carbon::parse("{$endDate} {$this->time_out_start}")->addHours(2);
        }

        return Carbon::parse("{$endDate} 23:59:59");
    }

    // =========================================================================
    // ELOQUENT QUERY SCOPES
    // =========================================================================

    public function scopeOngoing(Builder $query): Builder
    {
        $nowStr = now()->toDateTimeString();
        $today = now()->toDateString();

        return $query->where('approval_status', 'approved')
            // Check if today falls within event_date and event_end_date range
            ->where('event_date', '<=', $today)
            ->where(function ($q) use ($today) {
                $q->whereNull('event_end_date')
                  ->orWhere('event_end_date', '>=', $today);
            })
            ->where(function ($q) use ($nowStr) {
                $q->whereRaw("DATE_SUB(CONCAT(event_date, ' ', time_in_start), INTERVAL 2 HOUR) <= ?", [$nowStr])
                  ->where(function ($sub) use ($nowStr) {
                      $sub->where(function ($out) use ($nowStr) {
                          $out->whereNotNull('time_out_end')
                              ->whereRaw("DATE_ADD(CONCAT(COALESCE(event_end_date, event_date), ' ', time_out_end), INTERVAL 2 HOUR) >= ?", [$nowStr])
                              ->orWhere(function ($outStart) use ($nowStr) {
                                  $outStart->whereNull('time_out_end')
                                           ->whereNotNull('time_out_start')
                                           ->whereRaw("DATE_ADD(CONCAT(COALESCE(event_end_date, event_date), ' ', time_out_start), INTERVAL 2 HOUR) >= ?", [$nowStr]);
                              });
                      })->orWhere(function ($noOut) {
                          $noOut->whereNull('time_out_end')
                                ->whereNull('time_out_start');
                      });
                  });
            });
    }

    public function scopeUpcoming(Builder $query): Builder
    {
        $nowStr = now()->toDateTimeString();

        return $query->where('approval_status', 'approved')
            ->where(function ($q) use ($nowStr) {
                $q->whereRaw("DATE_SUB(CONCAT(event_date, ' ', time_in_start), INTERVAL 2 HOUR) > ?", [$nowStr]);
            });
    }

    public function scopeCompleted(Builder $query): Builder
    {
        $nowStr = now()->toDateTimeString();

        return $query->where('approval_status', 'approved')
            ->where(function ($q) use ($nowStr) {
                $q->whereRaw("DATE_ADD(CONCAT(COALESCE(event_end_date, event_date), ' ', COALESCE(time_out_end, time_out_start, '23:59:59')), INTERVAL 2 HOUR) < ?", [$nowStr]);
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