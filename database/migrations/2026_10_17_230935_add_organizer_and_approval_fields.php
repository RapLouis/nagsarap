<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            if (!Schema::hasColumn('users', 'role')) {
                $table->string('role')->default('organizer')->after('email');
            }
        });

        Schema::table('events', function (Blueprint $table) {
            if (!Schema::hasColumn('events', 'user_id')) {
                $table->foreignId('user_id')->nullable()->constrained('users')->nullOnDelete();
            }
            if (!Schema::hasColumn('events', 'approval_status')) {
                $table->string('approval_status')->default('pending');
            }
            if (!Schema::hasColumn('events', 'is_geofenced')) {
                $table->boolean('is_geofenced')->default(false);
            }
            if (!Schema::hasColumn('events', 'geofence_type')) {
                $table->string('geofence_type')->default('radius');
            }
            if (!Schema::hasColumn('events', 'latitude')) {
                $table->decimal('latitude', 10, 8)->nullable();
            }
            if (!Schema::hasColumn('events', 'longitude')) {
                $table->decimal('longitude', 11, 8)->nullable();
            }
            if (!Schema::hasColumn('events', 'radius_meters')) {
                $table->integer('radius_meters')->default(100);
            }
            if (!Schema::hasColumn('events', 'geofence_polygon')) {
                $table->json('geofence_polygon')->nullable();
            }
            if (!Schema::hasColumn('events', 'target_scope')) {
                $table->string('target_scope')->default('all');
            }
            if (!Schema::hasColumn('events', 'target_sections')) {
                $table->json('target_sections')->nullable();
            }
            if (!Schema::hasColumn('events', 'event_end_date')) {
                $table->date('event_end_date')->nullable();
            }
            if (!Schema::hasColumn('events', 'schedules')) {
                $table->json('schedules')->nullable();
            }
            if (!Schema::hasColumn('events', 'is_active')) {
                $table->boolean('is_active')->default(true);
            }
        });
    }

    public function down(): void
    {
        Schema::table('events', function (Blueprint $table) {
            $table->dropForeign(['user_id']);
            $table->dropColumn([
                'user_id',
                'approval_status',
                'is_geofenced',
                'geofence_type',
                'latitude',
                'longitude',
                'radius_meters',
                'geofence_polygon',
                'target_scope',
                'target_sections',
                'event_end_date',
                'schedules',
                'is_active',
            ]);
        });
    }
};