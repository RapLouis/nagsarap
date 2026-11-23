<?php

use Illuminate\Support\Facades\Schedule;
use Illuminate\Support\Facades\Storage;

Schedule::call(function () {
    $disk = Storage::disk('private');
    $cutoff = now()->subDays((int) config('face_verification.frame_retention_days', 7))->timestamp;

    foreach ($disk->allFiles('face-attempts') as $file) {
        if ($disk->lastModified($file) < $cutoff) {
            $disk->delete($file);
        }
    }
})->daily()->name('purge-face-attempt-frames');