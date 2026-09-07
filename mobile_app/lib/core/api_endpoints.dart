class ApiEndpoints {
  ApiEndpoints._();

  /*
  |--------------------------------------------------------------------------
  | AUTHENTICATION
  |--------------------------------------------------------------------------
  */

  static const String login =
      '/api/v1/auth/login';

  static const String logout =
      '/api/v1/auth/logout';

  static const String me =
      '/api/v1/me';

  /*
  |--------------------------------------------------------------------------
  | REGISTRATION
  |--------------------------------------------------------------------------
  */

  static const String register =
      '/api/v1/register';

  static const String validateReferencePhoto =
      '/api/v1/register/validate-photo';

  static const String verifyRegistrationFace =
      '/api/v1/register/verify-face';

  /*
  |--------------------------------------------------------------------------
  | EVENTS
  |--------------------------------------------------------------------------
  */

  static const String events =
      '/api/v1/events';

  /*
  |--------------------------------------------------------------------------
  | ATTENDANCE
  |--------------------------------------------------------------------------
  */

  static const String attendanceCheckIn =
      '/api/v1/attendance/check-in';

  static const String attendanceSync =
      '/api/v1/attendance/sync';

  static const String attendanceHistory =
      '/api/v1/attendance/history';

  /*
  |--------------------------------------------------------------------------
  | SANCTIONS
  |--------------------------------------------------------------------------
  */

  static const String sanctions =
      '/api/v1/sanctions';
}