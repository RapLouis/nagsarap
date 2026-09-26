<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
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

            // Attendance Log Data
            $table->timestamp('logged_at');
            $table->enum('status', ['present', 'late', 'excused'])->default('present');
            $table->float('confidence_score', 5, 4)->nullable(); // Stores similarity score (e.g., 0.8542)

            $table->timestamps();

            // Prevent duplicate check-ins for the same student in the same event
            $table->unique(['student_id', 'event_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('attendances');
    }
};