<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('sanctions', function (Blueprint $table) {
            $table->id('sanction_id');

            $table->unsignedInteger('student_id');

            $table->string('title', 150)
                ->default('Attendance Sanction');

            $table->text('reason');

            $table->string('status', 30)
                ->default('pending');

            $table->timestamp('issued_at')
                ->nullable();

            $table->timestamp('resolved_at')
                ->nullable();

            $table->timestamps();

            $table->index('student_id');
            $table->index('status');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('sanctions');
    }
};