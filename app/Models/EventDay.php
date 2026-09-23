<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class EventDay extends Model
{
    use HasFactory;

    protected $primaryKey = 'event_day_id';

    protected $fillable = [
        'event_id',
        'event_date',
        'slots',
    ];

    protected $casts = [
        'event_day_id' => 'integer',
        'event_id'     => 'integer',
        'event_date'   => 'date:Y-m-d',
        'slots'        => 'array', // Automatically casts JSON slots array
    ];

    public function event(): BelongsTo
    {
        return $this->belongsTo(Event::class, 'event_id', 'event_id');
    }
}