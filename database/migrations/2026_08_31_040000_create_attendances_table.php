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

            // Slot-Aware Tracking Columns (added directly to creation)
            // YYYY-MM-DD of the event day this record belongs to.
            // IMPORTANT: do NOT add a date cast for this column in the Attendance model[cite: 1].
            $table->date('event_date')->nullable();

            // Position of the slot inside event_days.slots (0-based)[cite: 1].
            $table->unsignedSmallInteger('slot_index')->nullable();

            // 'in' (Time-In) or 'out' (Time-Out)[cite: 1].
            $table->string('type', 3)->nullable();

            // Attendance Log Data
            $table->timestamp('logged_at');
            $table->enum('status', ['present', 'late', 'excused'])->default('present');
            $table->float('confidence_score', 5, 4)->nullable(); // Stores similarity score (e.g., 0.8542)

            $table->timestamps();

            // Slot-Aware Unique Constraint: One record per student / event / day / slot / type[cite: 1]
            $table->unique(
                ['student_id', 'event_id', 'event_date', 'slot_index', 'type'],
                'attendances_student_slot_type_unique'
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