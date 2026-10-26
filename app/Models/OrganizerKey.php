<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class OrganizerKey extends Model
{
    use HasFactory;

    protected $fillable = [
        'key_name',
        'org_code',
        'secret_key',
        'department',
        'max_uses',
        'uses_count',
        'expires_at',
        'is_active',
        'created_by',
    ];

    protected $hidden = [
        'secret_key',
    ];

    public function creator()
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    public function applications()
    {
        return $this->hasMany(OrganizerApplication::class);
    }
}