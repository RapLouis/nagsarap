<?php

namespace Database\Seeders;

use App\Models\User;
use Illuminate\Database\Console\Seeds\WithoutModelEvents;
use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    use WithoutModelEvents;

    public function run(): void
    {
        $this->call([
            StudentSeeder::class,
        ]);

        User::updateOrCreate(
            ['email' => 'admin@ccis.edu.ph'],
            [
                'name' => 'CCIS Admin',
                'password' => bcrypt('password123'),
                'role' => 'admin',
            ]
        );

        User::updateOrCreate(
            ['email' => 'organizer@ccis.edu.ph'],
            [
                'name' => 'Event Organizer',
                'password' => bcrypt('password123'),
                'role' => 'organizer',
            ]
        );
    }
}