<?php

use App\Http\Controllers\Api\AttendanceController;
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\EventController;
use App\Http\Controllers\Api\RegistrationController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| API Routes
|--------------------------------------------------------------------------
|
| CCIS Attendance System API
|
| Base URL:
| /api/v1
|
*/

Route::prefix('v1')->group(function () {

    /*
    |--------------------------------------------------------------------------
    | Public Authentication
    |--------------------------------------------------------------------------
    */

    Route::post('/auth/login', [AuthController::class, 'login'])
        ->middleware('throttle:10,1');

    /*
    |--------------------------------------------------------------------------
    | Student Registration
    |--------------------------------------------------------------------------
    |
    | Initial registration is public because the student does not have
    | a Sanctum token yet.
    |
    */

    Route::post('/register', [RegistrationController::class, 'register'])
        ->middleware('throttle:5,1');

    Route::post(
    '/register/validate-photo',
    [RegistrationController::class, 'validatePhoto']
);

    /*
    |--------------------------------------------------------------------------
    | Protected Student API
    |--------------------------------------------------------------------------
    */

    Route::middleware('auth:sanctum')->group(function () {

        /*
        |----------------------------------------------------------------------
        | Authentication
        |----------------------------------------------------------------------
        */

        Route::get('/me', [AuthController::class, 'me']);

        Route::post('/auth/logout', [AuthController::class, 'logout']);


        /*
        |----------------------------------------------------------------------
        | Registration / Face Verification
        |----------------------------------------------------------------------
        */

        Route::post(
            '/register/verify-face',
            [RegistrationController::class, 'verifyFace']
        )->middleware('throttle:10,1');


        /*
        |----------------------------------------------------------------------
        | Events
        |----------------------------------------------------------------------
        */

        Route::get('/events', [EventController::class, 'index']);

        Route::get('/events/{event}', [EventController::class, 'show']);


        /*
        |----------------------------------------------------------------------
        | Attendance
        |----------------------------------------------------------------------
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
            '/attendance/sync',
            [AttendanceController::class, 'sync']
        )->middleware('throttle:60,1');
    });
});