<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class EventDay extends Model
{
    protected $primaryKey = 'event_day_id';

    protected $fillable = ['event_id','event_date','slots'];

    protected $casts = ['event_date' => 'date:Y-m-d', 'slots' => 'array'];

    public function event(): BelongsTo { return $this->belongsTo(Event::class, 'event_id', 'event_id'); }
}
