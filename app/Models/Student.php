<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Casts\Attribute;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Student extends Model
{
    use HasFactory;

    protected $table = 'students';
    protected $primaryKey = 'student_id';
    public $incrementing = true;
    protected $keyType = 'int';

    protected $fillable = [
        'student_number','surname','firstname','middlename','ext','email',
        'degree_id','curricula_id','entrance_status','rfid','degree','year_section',
        'semester','academic_year','form_5_path','face_photo_path','face_embedding',
        'verification_status','college_code','college',
    ];

    protected $hidden = ['face_embedding', 'face_photo_path'];

    protected $casts = [
        'student_id' => 'integer',
        'degree_id' => 'integer',
        'curricula_id' => 'integer',
        'entrance_status' => 'integer',
        'face_embedding' => 'array',
    ];

    protected function firstname(): Attribute
    {
        return Attribute::make(set: fn (?string $value) => $value ? ucwords(strtolower(trim($value))) : null);
    }

    protected function surname(): Attribute
    {
        return Attribute::make(set: fn (?string $value) => $value ? ucwords(strtolower(trim($value))) : null);
    }

    protected function middlename(): Attribute
    {
        return Attribute::make(set: fn (?string $value) => $value ? ucwords(strtolower(trim($value))) : null);
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class, 'student_id', 'student_id');
    }

    public function attendances(): HasMany
    {
        return $this->hasMany(Attendance::class, 'student_id', 'student_id');
    }
}
