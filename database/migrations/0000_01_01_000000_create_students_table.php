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
        Schema::create('students', function (Blueprint $table) {
            $table->increments('student_id');

            // Student Identity
            $table->string('student_number')->unique();
            $table->string('surname');
            $table->string('firstname');
            $table->string('middlename')->nullable();
            $table->string('ext')->nullable();
            $table->string('email')->unique()->nullable();

            // Academic Details
            $table->string('department')->nullable();
            $table->string('degree')->nullable();
            $table->string('year_level')->nullable();
            $table->string('section')->nullable();
            $table->string('year_section')->nullable();
            $table->string('semester')->nullable();
            $table->string('academic_year')->nullable();

            // Document & Biometric Storage
            $table->string('face_photo_path')->nullable();
            $table->string('form_5_path')->nullable();
            $table->longText('face_embedding')->nullable();
            $table->longText('face_descriptor')->nullable();

            // Verification & Account Status
            $table->string('verification_status')->default('pending_face_verification');
            $table->string('status')->default('active');

            $table->timestamps();

            // Indexes
            $table->index('student_number');
            $table->index('verification_status');
            $table->index('degree');
            $table->index('year_section');
            $table->index('semester');
            $table->index('academic_year');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('students');
    }
};