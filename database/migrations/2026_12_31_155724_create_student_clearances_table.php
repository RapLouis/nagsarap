<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('student_clearances', function (Blueprint $table) {
            $table->id('clearance_id');
            
            // Match students table primary key type exactly
            $table->unsignedInteger('student_id');
            $table->unsignedBigInteger('event_id');
            
            $table->enum('status', ['pending', 'review', 'cleared'])->default('pending');
            $table->text('remarks')->nullable();
            $table->timestamps();

            // Explicit foreign keys referencing the 'students' and 'events' tables
            $table->foreign('student_id')
                  ->references('student_id')
                  ->on('students')
                  ->onDelete('cascade');

            $table->foreign('event_id')
                  ->references('event_id')
                  ->on('events')
                  ->onDelete('cascade');

            $table->unique(['student_id', 'event_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('student_clearances');
    }
};