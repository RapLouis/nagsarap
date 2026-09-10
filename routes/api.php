<?php

use App\Http\Controllers\Api\AttendanceController;
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\EventController;
use App\Http\Controllers\Api\NotificationController;
use App\Http\Controllers\Api\RegistrationController;
use App\Http\Controllers\Api\SanctionController;
use Illuminate\Support\Facades\Route;

Route::prefix('v1')->group(function () {

    /*
    |--------------------------------------------------------------------------
    | PUBLIC AUTHENTICATION
    |--------------------------------------------------------------------------
    */

    Route::post(
        '/auth/login',
        [AuthController::class, 'login']
    )->middleware('throttle:10,1');

    /*
    |--------------------------------------------------------------------------
    | REGISTRATION
    |--------------------------------------------------------------------------
    */

    Route::post(
        '/register',
        [RegistrationController::class, 'register']
    )->middleware('throttle:5,1');

    Route::post(
        '/register/validate-photo',
        [RegistrationController::class, 'validatePhoto']
    )->middleware('throttle:20,1');

    /*
    |--------------------------------------------------------------------------
    | AUTHENTICATED API
    |--------------------------------------------------------------------------
    */

    Route::middleware('auth:sanctum')->group(function () {

        /*
        |--------------------------------------------------------------------------
        | USER
        |--------------------------------------------------------------------------
        */

        Route::get(
            '/me',
            [AuthController::class, 'me']
        );

        Route::post(
            '/auth/logout',
            [AuthController::class, 'logout']
        );

        /*
        |--------------------------------------------------------------------------
        | REGISTRATION BIOMETRICS
        |--------------------------------------------------------------------------
        */

        Route::post(
            '/register/analyze-liveness-frame',
            [
                RegistrationController::class,
                'analyzeLivenessFrame',
            ]
        )->middleware('throttle:60,1');

        Route::post(
            '/register/verify-face',
            [
                RegistrationController::class,
                'verifyFace',
            ]
        )->middleware('throttle:10,1');

        /*
        |--------------------------------------------------------------------------
        | EVENTS
        |--------------------------------------------------------------------------
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
        |--------------------------------------------------------------------------
        | ATTENDANCE
        |--------------------------------------------------------------------------
        */

        Route::get(
            '/attendance/history',
            [AttendanceController::class, 'history']
        );

        Route::post(
            '/attendance/check-in',
            [AttendanceController::class, 'checkIn']
        )->middleware('throttle:30,1');

        Route::post(
            '/attendance/analyze-liveness-frame',
            [
                AttendanceController::class,
                'analyzeLivenessFrame',
            ]
        )->middleware('throttle:120,1');

        Route::post(
            '/attendance/mobile-check-in',
            [
                AttendanceController::class,
                'mobileCheckIn',
            ]
        )->middleware('throttle:30,1');

        Route::post(
            '/attendance/sync',
            [AttendanceController::class, 'sync']
        )->middleware('throttle:60,1');

        /*
        |--------------------------------------------------------------------------
        | SANCTIONS
        |--------------------------------------------------------------------------
        */

        Route::get(
            '/sanctions',
            [
                SanctionController::class,
                'index',
            ]
        );

        /*
        |--------------------------------------------------------------------------
        | NOTIFICATIONS
        |--------------------------------------------------------------------------
        */

        Route::get(
            '/notifications',
            [
                NotificationController::class,
                'index',
            ]
        );

        Route::patch(
            '/notifications/read-all',
            [
                NotificationController::class,
                'markAllAsRead',
            ]
        );

        Route::patch(
            '/notifications/{notificationId}/read',
            [
                NotificationController::class,
                'markAsRead',
            ]
        )->whereNumber('notificationId');
    });
});