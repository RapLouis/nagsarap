<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::table('students', function (Blueprint $table) {
            if (!Schema::hasColumn('students','college_code')) $table->string('college_code',10)->nullable()->index();
            if (!Schema::hasColumn('students','college')) $table->string('college',150)->nullable();
        });
    }
    public function down(): void
    {
        Schema::table('students', function (Blueprint $table) {
            if (Schema::hasColumn('students','college')) $table->dropColumn('college');
            if (Schema::hasColumn('students','college_code')) $table->dropColumn('college_code');
        });
    }
};
