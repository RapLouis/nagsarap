<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('face_verification_attempts', function (Blueprint $table) {
            $table->id();
            // Plain indexed columns (no foreign keys) so this works whatever your students table uses.
            $table->unsignedBigInteger('student_id')->index();
            $table->unsignedBigInteger('user_id')->nullable();
            // passed | liveness_failed | profile_mismatch | profile_unavailable | duplicate
            // | challenge_invalid | rate_limited | service_error
            $table->string('outcome', 40)->index();
            $table->string('reason_code', 60)->nullable();
            $table->string('direction', 10)->nullable();
            $table->string('ip_address', 45)->nullable();
            $table->string('user_agent')->nullable();
            $table->json('metrics')->nullable();     // Python "checks", similarity scores, matched student on duplicates
            $table->json('frame_paths')->nullable(); // only when FACE_STORE_FAILED_FRAMES=true
            $table->timestamps();

            $table->index(['student_id', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('face_verification_attempts');
    }
};