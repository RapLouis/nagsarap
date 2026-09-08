<?php

use App\Http\Controllers\Api\AttendanceController;
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\EventController;
use App\Http\Controllers\Api\RegistrationController;
use Illuminate\Support\Facades\Route;

Route::prefix('v1')->group(function () {

    /*
    |--------------------------------------------------------------------------
    | AUTH
    |--------------------------------------------------------------------------
    */

    Route::post(
        '/auth/login',
        [
            AuthController::class,
            'login',
        ]
    )->middleware(
        'throttle:10,1'
    );

    /*
    |--------------------------------------------------------------------------
    | REGISTRATION
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
    | PROTECTED STUDENT API
    |--------------------------------------------------------------------------
    */

    Route::middleware(
        'auth:sanctum'
    )->group(function () {

        /*
        |--------------------------------------------------------------------------
        | AUTHENTICATED USER
        |--------------------------------------------------------------------------
        */

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
        )->middleware(
            'throttle:60,1'
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

        /*
        |--------------------------------------------------------------------------
        | EVENTS
        |--------------------------------------------------------------------------
        */

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

        /*
        |--------------------------------------------------------------------------
        | ATTENDANCE
        |--------------------------------------------------------------------------
        */

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