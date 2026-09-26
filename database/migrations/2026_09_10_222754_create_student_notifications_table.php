<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('student_notifications', function (Blueprint $table) {
            $table->id('notification_id');

            $table->unsignedInteger('student_id');

            $table->string('type', 50)
                ->default('general');

            $table->string('title', 150);

            $table->text('message');

            $table->boolean('is_read')
                ->default(false);

            $table->timestamp('read_at')
                ->nullable();

            $table->timestamps();

            $table->index('student_id');
            $table->index(['student_id', 'is_read']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('student_notifications');
    }
};