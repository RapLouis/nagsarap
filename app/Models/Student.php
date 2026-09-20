<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Casts\Attribute;
use Illuminate\Database\Eloquent\Relations\HasOne;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;

class Student extends Model
{
    use HasFactory;

    protected $table = 'students';
    protected $primaryKey = 'student_id';
    public $incrementing = true;
    protected $keyType = 'int';

    protected $fillable = [
        'student_number',
        'surname',
        'firstname',
        'middlename',
        'ext',
        'email',
        'degree_id',
        'curricula_id',
        'entrance_status',
        'rfid',
        'degree',
        'year_section',
        'semester',
        'academic_year',
        'form_5_path',
        'face_photo_path',
        'face_embedding',
        'verification_status',
    ];

    /**
     * The attributes that should be cast.
     *
     * @var array<string, string>
     */
    protected $casts = [
        'face_embedding' => 'array', // Converts JSON 512-D vector to PHP array automatically
    ];

    /**
     * Automatically format and clean the firstname input.
     */
    protected function firstname(): Attribute
    {
        return Attribute::make(
            set: fn (?string $value) => $value ? ucwords(strtolower(trim($value))) : null,
        );
    }

    /**
     * Automatically format and clean the surname input.
     */
    protected function surname(): Attribute
    {
        return Attribute::make(
            set: fn (?string $value) => $value ? ucwords(strtolower(trim($value))) : null,
        );
    }

    /**
     * Automatically format and clean the middlename input.
     */
    protected function middlename(): Attribute
    {
        return Attribute::make(
            set: fn (?string $value) => $value ? ucwords(strtolower(trim($value))) : null,
        );
    }

    /**
     * Get the user account associated with the student profile.
     */
    public function user(): HasOne
    {
        return $this->hasOne(User::class, 'student_id', 'student_id');
    }

    /**
     * Get all attendance logs for the student.
     */
    public function attendances(): HasMany
    {
        return $this->hasMany(Attendance::class, 'student_id', 'student_id');
    }

    /**
     * Get all events attended by the student.
     */
    public function events(): BelongsToMany
    {
        return $this->belongsToMany(Event::class, 'attendances', 'student_id', 'event_id')
            ->withPivot('status', 'confidence_score', 'logged_at')
            ->withTimestamps();
    }
}