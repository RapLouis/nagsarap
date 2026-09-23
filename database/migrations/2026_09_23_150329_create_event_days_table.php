<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('event_days', function (Blueprint $table) {
            $table->id('event_day_id');
            $table->foreignId('event_id')
                  ->constrained('events', 'event_id')
                  ->cascadeOnDelete();
            
            $table->date('event_date');
            
            // JSON column holding multiple time slots (Morning, Afternoon, etc.) for this specific day
            $table->json('slots'); 
            
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('event_days');
    }
};