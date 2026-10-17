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
        'user_id',
        'title','description','event_date','target_scope','target_sections','event_end_date','location','is_geofenced','geofence_type',
        'latitude','longitude','radius_meters','geofence_polygon','is_active','approval_status',
    ];

    protected $casts = [
        'event_id' => 'integer', 'event_date' => 'date:Y-m-d', 'event_end_date' => 'date:Y-m-d',
        'is_active' => 'boolean', 'is_geofenced' => 'boolean', 'latitude' => 'float',
        'longitude' => 'float', 'radius_meters' => 'integer', 'geofence_polygon' => 'array', 'target_sections' => 'array', 
    ];

    public function user()
    {
        return $this->belongsTo(User::class, 'user_id', 'id');
    }

    public function days(): HasMany { return $this->hasMany(EventDay::class, 'event_id', 'event_id'); }
    public function attendances(): HasMany { return $this->hasMany(Attendance::class, 'event_id', 'event_id'); }

    public function students(): BelongsToMany
    {
        return $this->belongsToMany(Student::class, 'attendances', 'event_id', 'student_id', 'event_id', 'student_id')
            ->withPivot('status','confidence_score','logged_at')->withTimestamps();
    }

    public function isWithinGeofence(float $userLat, float $userLng): bool
    {
        if (!$this->is_geofenced) return true;
        if ($this->geofence_type === 'polygon' && !empty($this->geofence_polygon)) return $this->isPointInPolygon($userLat, $userLng, $this->geofence_polygon);
        return $this->isPointInRadius($userLat, $userLng);
    }

    protected function isPointInRadius(float $userLat, float $userLng): bool
    {
        if ($this->latitude === null || $this->longitude === null) return false;
        $r=6371000; $a=deg2rad($userLat); $b=deg2rad($userLng); $c=deg2rad((float)$this->latitude); $d=deg2rad((float)$this->longitude);
        $x=$c-$a; $y=$d-$b;
        $angle=2*asin(sqrt(pow(sin($x/2),2)+cos($a)*cos($c)*pow(sin($y/2),2)));
        return ($angle*$r) <= (float)$this->radius_meters;
    }

    protected function isPointInPolygon(float $lat, float $lng, array $polygon): bool
    {
        if (count($polygon) < 3) return false;
        $inside=false; $n=count($polygon);
        for ($i=0,$j=$n-1;$i<$n;$j=$i++) {
            $xi=(float)($polygon[$i]['lng'] ?? $polygon[$i][1] ?? 0); $yi=(float)($polygon[$i]['lat'] ?? $polygon[$i][0] ?? 0);
            $xj=(float)($polygon[$j]['lng'] ?? $polygon[$j][1] ?? 0); $yj=(float)($polygon[$j]['lat'] ?? $polygon[$j][0] ?? 0);
            if (($yi>$lat)!==($yj>$lat) && $lng < ($xj-$xi)*($lat-$yi)/(($yj-$yi) ?: 1e-12)+$xi) $inside=!$inside;
        }
        return $inside;
    }

    public function scopeOngoing(Builder $query): Builder
    {
        $today = now()->toDateString();
        return $query->where('approval_status', 'approved')
            ->where('is_active', true)
            ->where(function ($q) use ($today) {
                $q->where(function ($sub) use ($today) {
                    $sub->whereDate('event_date', '<=', $today)
                        ->where(fn($s) => $s->whereDate('event_end_date', '>=', $today)->orWhereNull('event_end_date'));
                })->orWhereHas('days', function ($sub) use ($today) {
                    $sub->whereDate('event_date', $today);
                });
            });
    }

    public function scopeUpcoming(Builder $query): Builder
    {
        $today = now()->toDateString();
        return $query->where('approval_status', 'approved')
            ->where(function ($q) use ($today) {
                $q->whereDate('event_date', '>', $today)
                  ->orWhereHas('days', function ($sub) use ($today) {
                      $sub->whereDate('event_date', '>', $today);
                  });
            });
    }

    public function scopeCompleted(Builder $query): Builder
    {
        $today = now()->toDateString();
        return $query->where('approval_status', 'approved')
            ->where(function ($q) use ($today) {
                $q->where(function ($sub) use ($today) {
                    $sub->whereDate('event_end_date', '<', $today)
                        ->orWhere(function ($inner) use ($today) {
                            $inner->whereNull('event_end_date')
                                  ->whereDate('event_date', '<', $today);
                        });
                })->whereDoesntHave('days', function ($sub) use ($today) {
                    $sub->whereDate('event_date', '>=', $today);
                });
            });
    }

    public function scopePending(Builder $query): Builder { return $query->where('approval_status','pending'); }
    public function scopeDeclined(Builder $query): Builder { return $query->where('approval_status','declined'); }

    public function scopeForStudents(Builder $query): Builder
    {
        return $query->where('approval_status', 'approved')->where('is_active', true);
    }

    public function scopeWithDaysBetween(Builder $query, string $from, string $to): Builder
    {
        $inRange = fn ($q) => $q->whereDate('event_date', '>=', $from)
            ->whereDate('event_date', '<=', $to);

        return $query->whereHas('days', $inRange)
            ->with(['days' => fn ($q) => $inRange($q)->orderBy('event_date')]);
    }
}