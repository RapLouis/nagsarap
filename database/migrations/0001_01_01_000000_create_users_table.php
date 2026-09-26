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
        Schema::create('users', function (Blueprint $table) {
            $table->id();

            /*
            |--------------------------------------------------------------------------
            | Student Relationship
            |--------------------------------------------------------------------------
            | Linked to students.student_id. 
            | Only populated for student accounts; NULL for organizers and admins.
            |--------------------------------------------------------------------------
            */
            $table->unsignedInteger('student_id')
                ->nullable()
                ->unique();

            /*
            |--------------------------------------------------------------------------
            | User Account Information
            |--------------------------------------------------------------------------
            */
            $table->string('name');

            $table->string('email')
                ->unique();

            /*
            |--------------------------------------------------------------------------
            | Authentication Credentials
            |--------------------------------------------------------------------------
            */
            $table->timestamp('email_verified_at')
                ->nullable();

            $table->string('password');

            $table->rememberToken();

            /*
            |--------------------------------------------------------------------------
            | System Roles
            |--------------------------------------------------------------------------
            */
            $table->enum('role', [
                'student',
                'organizer',
                'admin',
            ])->default('student');

            $table->timestamps();

            /*
            |--------------------------------------------------------------------------
            | Foreign Key Constraints & Indexes
            |--------------------------------------------------------------------------
            */
            $table->foreign('student_id')
                ->references('student_id')
                ->on('students')
                ->nullOnDelete();

            $table->index('role');
        });

        /*
        |--------------------------------------------------------------------------
        | Password Reset Tokens
        |--------------------------------------------------------------------------
        */
        Schema::create('password_reset_tokens', function (Blueprint $table) {
            $table->string('email')->primary();
            $table->string('token');
            $table->timestamp('created_at')->nullable();
        });

        /*
        |--------------------------------------------------------------------------
        | Active Sessions
        |--------------------------------------------------------------------------
        */
        Schema::create('sessions', function (Blueprint $table) {
            $table->string('id')->primary();

            $table->foreignId('user_id')
                ->nullable()
                ->index();

            $table->string('ip_address', 45)
                ->nullable();

            $table->text('user_agent')
                ->nullable();

            $table->longText('payload');

            $table->integer('last_activity')
                ->index();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('sessions');
        Schema::dropIfExists('password_reset_tokens');
        Schema::dropIfExists('users');
    }
};