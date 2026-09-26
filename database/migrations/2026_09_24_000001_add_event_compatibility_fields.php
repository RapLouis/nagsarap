<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::table('events', function (Blueprint $table) {
            if (!Schema::hasColumn('events', 'event_date')) $table->date('event_date')->nullable()->after('description');
            if (!Schema::hasColumn('events', 'event_end_date')) $table->date('event_end_date')->nullable()->after('event_date');
        });
    }
    public function down(): void
    {
        Schema::table('events', function (Blueprint $table) {
            foreach (['event_end_date','event_date'] as $column) if (Schema::hasColumn('events',$column)) $table->dropColumn($column);
        });
    }
};
