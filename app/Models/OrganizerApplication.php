<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class OrganizerApplication extends Model
{
    use HasFactory;

    protected $fillable = [
        'user_id',
        'organizer_key_id',
        'organization_name',
        'position',
        'justification',
        'status',
        'rejection_reason',
        'reviewed_by',
        'reviewed_at',
    ];

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function key()
    {
        return $this->belongsTo(OrganizerKey::class, 'organizer_key_id');
    }

    public function reviewer()
    {
        return $this->belongsTo(User::class, 'reviewed_by');
    }
}