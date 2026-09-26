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
        'title','description','event_date','event_end_date','location','is_geofenced','geofence_type',
        'latitude','longitude','radius_meters','geofence_polygon','is_active','approval_status',
    ];

    protected $casts = [
        'event_id' => 'integer', 'event_date' => 'date:Y-m-d', 'event_end_date' => 'date:Y-m-d',
        'is_active' => 'boolean', 'is_geofenced' => 'boolean', 'latitude' => 'float',
        'longitude' => 'float', 'radius_meters' => 'integer', 'geofence_polygon' => 'array',
    ];

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

    public function getWindowStartAttribute(): Carbon
    {
        $earliest=null;
        foreach (($this->relationLoaded('days')?$this->days:$this->days()->get()) as $day) foreach (($day->slots ?? []) as $slot) if (!empty($slot['time_in_start'])) {
            $dt=Carbon::parse($day->event_date->format('Y-m-d').' '.$slot['time_in_start']); if (!$earliest || $dt->lt($earliest)) $earliest=$dt;
        }
        return ($earliest ?: now()->copy())->subHours(2);
    }

    public function getWindowEndAttribute(): Carbon
    {
        $latest=null;
        foreach (($this->relationLoaded('days')?$this->days:$this->days()->get()) as $day) foreach (($day->slots ?? []) as $slot) {
            $time=$slot['time_out_end'] ?? $slot['time_out_start'] ?? $slot['time_in_end'] ?? $slot['time_in_start'] ?? null;
            if ($time) { $dt=Carbon::parse($day->event_date->format('Y-m-d').' '.$time); if (!$latest || $dt->gt($latest)) $latest=$dt; }
        }
        return ($latest ?: now()->copy())->addHours(2);
    }

    public function scopeOngoing(Builder $query): Builder
    {
        $today=now()->toDateString();
        return $query->where('approval_status','approved')->where('is_active',true)->whereHas('days',fn($q)=>$q->whereDate('event_date',$today));
    }
    public function scopeUpcoming(Builder $query): Builder
    {
        $today=now()->toDateString();
        return $query->where('approval_status','approved')->whereHas('days',fn($q)=>$q->whereDate('event_date','>',$today));
    }
    public function scopeCompleted(Builder $query): Builder
    {
        $today=now()->toDateString();
        return $query->where('approval_status','approved')->whereHas('days',fn($q)=>$q->whereDate('event_date','<',$today));
    }
    public function scopePending(Builder $query): Builder { return $query->where('approval_status','pending'); }
    public function scopeDeclined(Builder $query): Builder { return $query->where('approval_status','declined'); }
}
