<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::create('attendances', function (Blueprint $table) {
            $table->id('attendance_id');
            $table->uuid('attendance_uuid')->nullable()->unique();

            // Foreign Key to Students Table
            $table->unsignedInteger('student_id');
            $table->foreign('student_id')
                ->references('student_id')
                ->on('students')
                ->cascadeOnDelete();

            // Foreign Key to Events Table
            $table->foreignId('event_id')
                ->constrained('events', 'event_id')
                ->cascadeOnDelete();

            // Slot-Aware & Checkpoint Tracking Columns
            $table->date('event_date')->nullable();
            $table->unsignedSmallInteger('slot_index')->nullable();
            $table->string('type', 3)->nullable(); // General classification: 'in' or 'out'
            $table->string('checkpoint_key', 50)->nullable(); // Authoritative checkpoint identifier

            // Attendance Log Data & Metadata
            $table->timestamp('logged_at');
            $table->timestamp('attendance_time')->nullable();
            $table->timestamp('sync_time')->nullable();
            $table->enum('status', ['present', 'late', 'excused'])->default('present');
            $table->string('sync_status')->nullable();
            $table->string('source')->nullable();
            $table->float('confidence_score', 5, 4)->nullable();

            // Liveness & Geolocation Verification Fields
            $table->boolean('liveness_passed')->nullable();
            $table->string('liveness_method')->nullable();
            $table->decimal('latitude', 10, 7)->nullable();
            $table->decimal('longitude', 10, 7)->nullable();
            $table->float('location_accuracy')->nullable();
            $table->float('distance_from_event')->nullable();
            $table->timestamp('location_verified_at')->nullable();

            $table->timestamps();

            // Checkpoint-Aware Unique Constraint
            $table->unique(
                ['student_id', 'event_id', 'event_date', 'slot_index', 'checkpoint_key'],
                'attendances_student_checkpoint_unique'
            );
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('attendances');
    }
};