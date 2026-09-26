# CCIS Attendance — merged architecture

This build uses **attendance-system** as the backend/admin baseline. The mobile functionality from `nagsarap` is limited to the `/api/v1/*` mobile API surface and `mobile_app/`.

## Backend responsibilities

- Admin/organization web UI: the attendance-system source.
- Event database model: attendance-system `events` + `event_days`.
- Student/attendance database: attendance-system schema, with mobile lifecycle/geolocation fields added by migrations.
- Registration/Form 5 processing: attendance-system implementation.
- Biometric/liveness: attendance-system Flask + InsightFace implementation in `python-services/face-verification/app.py`.
- Mobile authentication: Laravel Sanctum bearer tokens.
- Mobile API: `routes/api.php` and `app/Http/Controllers/Api/*`.
- Flutter application: `mobile_app/`.

## Event synchronization

Admin event creation/update writes to the same `events` and `event_days` tables read by `/api/v1/events`. Only approved active events are returned to the mobile app. The Flutter home screen already refreshes when the app resumes and when its dashboard reloads, so the mobile view does not maintain a second event database.

## Liveness

The server remains authoritative. Flutter only captures/guides the sequence. Laravel sends the captured center/turn/return frames to the attendance-system Python service, which performs face detection, pose/yaw checks, turn direction/size, progression, identity consistency, and optional anti-spoofing.

## Mobile student-number requirement

The mobile registration UI accepts exactly 12 alphanumeric characters and shows the requirement in green when satisfied and red when not satisfied. The mobile API enforces the same 12-character rule. The web registration flow was not changed to require 12 characters.

## Deployment

1. Configure `.env` from `.env.example` and never commit `.env`.
2. Install PHP dependencies with `composer install`.
3. Install/build web assets with `npm ci && npm run build`.
4. Run migrations against the production database with `php artisan migrate --force`.
5. Configure `BIOMETRIC_SERVICE_URL` and a matching `BIOMETRIC_SERVICE_TOKEN` on Laravel and the Python service.
6. Start the Python service behind a process manager using Gunicorn (not Flask development mode).
7. Serve Laravel through the normal production web server/PHP-FPM stack.
8. Build Flutter with `--dart-define=API_BASE_URL=https://<your-laravel-domain>`.

The Python biometric service is not exposed to Flutter. Flutter communicates only with Laravel.
