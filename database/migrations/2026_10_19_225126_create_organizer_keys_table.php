<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('organizer_keys', function (Blueprint $table) {
            $table->id();
            $table->string('key_name');                 // e.g., "CS Society 2026 Key"
            $table->string('org_code')->unique();       // e.g., "ORG-CS-2026"
            $table->string('secret_key');               // Security hash
            $table->string('department')->nullable();   // e.g., "College of Computing"
            $table->integer('max_uses')->default(1);    // Single-use or multi-use
            $table->integer('uses_count')->default(0);  // Tracking counter
            $table->timestamp('expires_at')->nullable();
            $table->boolean('is_active')->default(true);
            $table->foreignId('created_by')->constrained('users')->onDelete('cascade');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('organizer_keys');
    }
};