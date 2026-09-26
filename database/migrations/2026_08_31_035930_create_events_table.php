<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('events', function (Blueprint $table) {
            $table->id('event_id');
            $table->string('title', 150);
            $table->text('description')->nullable();
            
            // VENUE & LOCATION INFO
            $table->string('location', 100)->nullable();
            
            // HYBRID GEOFENCING CONFIGURATION
            $table->boolean('is_geofenced')->default(false);
            $table->enum('geofence_type', ['radius', 'polygon'])->default('radius');
            $table->decimal('latitude', 10, 8)->nullable();
            $table->decimal('longitude', 11, 8)->nullable();
            $table->unsignedInteger('radius_meters')->default(100);
            $table->json('geofence_polygon')->nullable();
            
            // ADMINISTRATIVE APPROVAL STATUS
            $table->enum('approval_status', ['approved', 'pending', 'declined'])->default('approved');
            $table->boolean('is_active')->default(true);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('events');
    }
};