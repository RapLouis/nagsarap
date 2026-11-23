<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // 1. Dynamic sanction settings (Admin configures fine rates from the UI)
        Schema::create('sanction_settings', function (Blueprint $table) {
            $table->string('key')->primary();$table->string('value')->nullable();
            $table->string('description')->nullable();$table->timestamps();
        });

        // 2. Clean Sanctions table
        Schema::create('sanctions', function (Blueprint $table) {$table->id('sanction_id');

            // Student & Event context
            $table->unsignedInteger('student_id')->index();
            $table->unsignedBigInteger('event_id')->index();$table->date('event_date');
            $table->unsignedInteger('slot_index');$table->string('slot_label', 100)->nullable();

            // Granular missing Time-In / Time-Out infraction & dynamic fine amount
            $table->string('infraction_type', 50);
            $table->decimal('fine_amount', 8, 2)->default(0.00);

            // Descriptive metadata
            $table->string('title', 150)->default('Attendance Sanction');$table->text('reason')->nullable();

            // Student resolution preference & verification workflow
            $table->enum('preferred_mode', ['unselected', 'cash', 'community_service', 'excuse'])
                  ->default('unselected')
                  ->index();
            $table->enum('status', ['unsettled', 'pending_verification', 'settled', 'excused'])
                  ->default('unsettled')
                  ->index();

            // Excuse submission & photo proof attachment
            $table->string('excuse_category', 100)->nullable();
            $table->text('student_notes')->nullable();$table->string('excuse_proof_path')->nullable();

            // Admin F2F verification (Official Receipt #, Comm. Service hours, remarks)
            $table->string('official_receipt_no', 100)->nullable();$table->decimal('comm_service_hours', 5, 2)->nullable();
            $table->text('admin_remarks')->nullable();$table->unsignedBigInteger('settled_by')->nullable();

            // Lifecycle timestamps
            $table->timestamp('issued_at')->nullable();
            $table->timestamp('resolved_at')->nullable();$table->timestamps();

            // Prevent duplicate sanctions for the exact same student, event, date, slot, and missing log
            $table->unique(
                ['student_id', 'event_id', 'event_date', 'slot_index', 'infraction_type'],
                'unique_student_slot_infraction'
            );

            // Foreign keys
            $table->foreign('student_id')
                  ->references('student_id')
                  ->on('students')
                  ->onDelete('cascade');

            $table->foreign('event_id')
                  ->references('event_id')
                  ->on('events')
                  ->onDelete('cascade');

            $table->foreign('settled_by')
                  ->references('id')
                  ->on('users')
                  ->onDelete('set null');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('sanctions');
        Schema::dropIfExists('sanction_settings');
    }
};