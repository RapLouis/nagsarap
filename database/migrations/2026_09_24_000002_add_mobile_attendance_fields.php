<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::table('attendances', function (Blueprint $table) {
            if (!Schema::hasColumn('attendances','attendance_uuid')) $table->uuid('attendance_uuid')->nullable()->unique()->after('attendance_id');
            if (!Schema::hasColumn('attendances','attendance_time')) $table->timestamp('attendance_time')->nullable()->index()->after('logged_at');
            if (!Schema::hasColumn('attendances','sync_time')) $table->timestamp('sync_time')->nullable()->index()->after('attendance_time');
            if (!Schema::hasColumn('attendances','sync_status')) $table->string('sync_status',20)->default('online')->after('status');
            if (!Schema::hasColumn('attendances','source')) $table->string('source',30)->default('web')->after('sync_status');
            if (!Schema::hasColumn('attendances','liveness_passed')) $table->boolean('liveness_passed')->default(false)->after('confidence_score');
            if (!Schema::hasColumn('attendances','liveness_method')) $table->string('liveness_method',80)->nullable()->after('liveness_passed');
            if (!Schema::hasColumn('attendances','latitude')) $table->decimal('latitude',10,7)->nullable()->after('liveness_method');
            if (!Schema::hasColumn('attendances','longitude')) $table->decimal('longitude',10,7)->nullable()->after('latitude');
            if (!Schema::hasColumn('attendances','location_accuracy')) $table->decimal('location_accuracy',10,2)->nullable()->after('longitude');
            if (!Schema::hasColumn('attendances','distance_from_event')) $table->decimal('distance_from_event',10,2)->nullable()->after('location_accuracy');
            if (!Schema::hasColumn('attendances','location_verified_at')) $table->timestamp('location_verified_at')->nullable()->after('distance_from_event');
        });
    }
    public function down(): void
    {
        Schema::table('attendances', function (Blueprint $table) {
            foreach (['location_verified_at','distance_from_event','location_accuracy','longitude','latitude','liveness_method','liveness_passed','source','sync_status','sync_time','attendance_time','attendance_uuid'] as $column) if (Schema::hasColumn('attendances',$column)) $table->dropColumn($column);
        });
    }
};
