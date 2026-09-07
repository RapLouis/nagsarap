<?php

use App\Http\Controllers\Api\AttendanceController;
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\EventController;
use App\Http\Controllers\Api\RegistrationController;
use Illuminate\Support\Facades\Route;

Route::prefix('v1')->group(function () {
    /*
    |--------------------------------------------------------------------------
    | Public authentication
    |--------------------------------------------------------------------------
    */

    Route::post(
        '/auth/login',
        [AuthController::class, 'login']
    )->middleware(
        'throttle:10,1'
    );

    /*
    |--------------------------------------------------------------------------
    | Public registration
    |--------------------------------------------------------------------------
    */

    Route::post(
        '/register',
        [
            RegistrationController::class,
            'register',
        ]
    )->middleware(
        'throttle:5,1'
    );

    Route::post(
        '/register/validate-photo',
        [
            RegistrationController::class,
            'validatePhoto',
        ]
    )->middleware(
        'throttle:20,1'
    );

    /*
    |--------------------------------------------------------------------------
    | Sanctum protected API
    |--------------------------------------------------------------------------
    */

    Route::middleware(
        'auth:sanctum'
    )->group(function () {
        Route::get(
            '/me',
            [
                AuthController::class,
                'me',
            ]
        );

        Route::post(
            '/auth/logout',
            [
                AuthController::class,
                'logout',
            ]
        );

        Route::post(
            '/register/liveness-frame',
            [
                RegistrationController::class,
                'analyzeLivenessFrame',
            ]
        )->middleware(
            'throttle:180,1'
        );
        
        Route::post(
            '/register/verify-face',
            [
                RegistrationController::class,
                'verifyFace',
            ]
        )->middleware(
            'throttle:10,1'
        );

        Route::get(
            '/events',
            [
                EventController::class,
                'index',
            ]
        );

        Route::get(
            '/events/{event}',
            [
                EventController::class,
                'show',
            ]
        );

        Route::get(
            '/attendance/history',
            [
                AttendanceController::class,
                'history',
            ]
        );

        Route::post(
            '/attendance/check-in',
            [
                AttendanceController::class,
                'checkIn',
            ]
        )->middleware(
            'throttle:30,1'
        );

        Route::post(
            '/attendance/sync',
            [
                AttendanceController::class,
                'sync',
            ]
        )->middleware(
            'throttle:60,1'
        );
    });
});