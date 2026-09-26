<?php

use App\Http\Controllers\Api\AttendanceController;
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\EventController;
use App\Http\Controllers\Api\FaceChallengeController;
use App\Http\Controllers\Api\NotificationController;
use App\Http\Controllers\Api\RegistrationController;
use App\Http\Controllers\Api\SanctionController;
use App\Http\Controllers\Api\WebVerificationController;
use Illuminate\Support\Facades\Route;

Route::prefix('v1')->group(function () {

    Route::post(
        '/auth/login',
        [AuthController::class, 'login']
    )->middleware('throttle:10,1');

    Route::post(
        '/register',
        [RegistrationController::class, 'register']
    )->middleware('throttle:10,1');

    Route::post(
        '/register/validate-photo',
        [RegistrationController::class, 'validatePhoto']
    )->middleware('throttle:30,1');

    Route::middleware('auth:sanctum')->group(function () {

        Route::get(
            '/me',
            [AuthController::class, 'me']
        )->name('api.me');

        Route::get(
            '/me/photo',
            [AuthController::class, 'profilePhoto']
        )->name('api.me.photo');

        Route::post(
            '/auth/logout',
            [AuthController::class, 'logout']
        );

        /*
         * Registration
         */
        Route::post(
            '/register/analyze-liveness-frame',
            [RegistrationController::class, 'analyzeLivenessFrame']
        );

        Route::post(
            '/register/liveness-challenge',
            [FaceChallengeController::class, 'registration']
        );

        Route::post(
            '/register/verify-face',
            [RegistrationController::class, 'verifyFace']
        )->middleware('throttle:20,1');

        Route::get(
            '/register/web-verification-url',
            [WebVerificationController::class, 'create']
        )->middleware('throttle:10,1');

        /*
         * Events
         */
        Route::get(
            '/events',
            [EventController::class, 'index']
        );

        Route::get(
            '/events/{event}',
            [EventController::class, 'show']
        );

        /*
         * Attendance
         */
        Route::get(
            '/attendance/history',
            [AttendanceController::class, 'history']
        );

        Route::post(
            '/attendance/check-in',
            [AttendanceController::class, 'checkIn']
        )->middleware('throttle:20,1');

        Route::post(
            '/attendance/analyze-liveness-frame',
            [AttendanceController::class, 'analyzeLivenessFrame']
        );

        Route::post(
            '/attendance/liveness-challenge',
            [FaceChallengeController::class, 'attendance']
        );

        Route::post(
            '/attendance/mobile-check-in',
            [AttendanceController::class, 'mobileCheckIn']
        )->middleware('throttle:20,1');

        Route::post(
            '/attendance/sync',
            [AttendanceController::class, 'sync']
        )->middleware('throttle:60,1');

        /*
         * Other mobile data
         */
        Route::get(
            '/sanctions',
            [SanctionController::class, 'index']
        );

        Route::get(
            '/notifications',
            [NotificationController::class, 'index']
        );

        Route::patch(
            '/notifications/read-all',
            [NotificationController::class, 'markAllAsRead']
        );

        Route::patch(
            '/notifications/{notificationId}/read',
            [NotificationController::class, 'markAsRead']
        )->whereNumber('notificationId');
    });
});