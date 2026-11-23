<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class SanctionSetting extends Model
{
    protected $table = 'sanction_settings';
    protected $primaryKey = 'key';
    public $incrementing = false;
    protected $keyType = 'string';

    protected $fillable = [
        'key',
        'value',
        'description',
    ];

    public static function getValue(string $key, mixed $default = null): mixed
    {
        $setting = static::where('key', $key)->first();
        return $setting ? $setting->value : $default;
    }

    public static function setValue(string $key, mixed $value, ?string $description = null): void
    {
        static::updateOrCreate(
            ['key' => $key],
            array_filter([
                'value'       => (string) $value,
                'description' => $description,
            ], fn ($v) => !is_null($v))
        );
    }

    public static function getFinePerLog(): float
    {
        $val = static::getValue('fine_per_log', '50.00');
        return (float) $val;
    }

    public static function setFinePerLog(float $amount): void
    {
        static::setValue(
            'fine_per_log',
            number_format($amount, 2, '.', ''),
            'Peso fine charged per missing Time-In or Time-Out log'
        );
    }
}