<?php

namespace Database\Seeders;

use App\Models\Event;
use Illuminate\Database\Seeder;

class EventSeeder extends Seeder
{
    public function run(): void
    {
        Event::create([
            'title'       => 'General Orientation 2026',
            'description' => 'Mandatory orientation for all enrolled students.',
            'event_date'  => '2026-09-01',
            'start_time'  => '08:00:00',
            'end_time'    => '12:00:00',
            'location'    => 'University Gymnasium',
            'is_active'   => true,
        ]);

        Event::create([
            'title'       => 'Tech Summit 2026',
            'description' => 'Annual biometrics and technology seminar.',
            'event_date'  => '2026-09-15',
            'start_time'  => '13:00:00',
            'end_time'    => '17:00:00',
            'location'    => 'Auditorium Hall A',
            'is_active'   => true,
        ]);
    }
}