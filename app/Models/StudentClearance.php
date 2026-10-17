<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class StudentClearance extends Model
{
    use HasFactory;

    protected $table = 'student_clearances';
    protected $primaryKey = 'clearance_id';

    protected $fillable = [
        'student_id',
        'event_id',
        'status',
        'remarks',
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