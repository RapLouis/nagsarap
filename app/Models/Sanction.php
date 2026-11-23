<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Sanction extends Model
{
    use HasFactory;

    protected $primaryKey = 'sanction_id';

    protected $fillable = [
        'student_id',
        'event_id',
        'event_date',
        'slot_index',
        'slot_label',
        'infraction_type',
        'fine_amount',
        'title',
        'reason',
        'status',
        'preferred_mode',
        'excuse_category',
        'student_notes',
        'excuse_proof_path',
        'official_receipt_no',
        'comm_service_hours',
        'admin_remarks',
        'settled_by',
        'issued_at',
        'resolved_at',
    ];

    protected $casts = [
        'event_date'         => 'date:Y-m-d',
        'fine_amount'        => 'decimal:2',
        'comm_service_hours' => 'decimal:2',
        'issued_at'          => 'datetime',
        'resolved_at'        => 'datetime',
    ];

    public function student(): BelongsTo
    {
        return $this->belongsTo(Student::class, 'student_id', 'student_id');
    }

    public function event(): BelongsTo
    {
        return $this->belongsTo(Event::class, 'event_id', 'event_id');
    }

    public function verifier(): BelongsTo
    {
        return $this->belongsTo(User::class, 'settled_by');
    }
}