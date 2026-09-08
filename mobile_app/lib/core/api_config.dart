class ApiConfig {
  ApiConfig._();

  /*
  |--------------------------------------------------------------------------
  | LARAVEL API URL
  |--------------------------------------------------------------------------
  |
  | Android emulator reaches your Mac through 10.0.2.2.
  |
  | Flutter API requests:
  |
  | Flutter
  |   ↓
  | http://10.0.2.2:8000
  |   ↓
  | Laravel
  |
  */

  static const String baseUrl = 'http://10.0.2.2:8000';

  /*
  |--------------------------------------------------------------------------
  | LARAVEL WEB URL FOR WEBVIEW
  |--------------------------------------------------------------------------
  |
  | Stage 14 reuses your existing Laravel/React verify-face.tsx.
  |
  | Because we run:
  |
  | adb reverse tcp:8000 tcp:8000
  |
  | Android WebView can open:
  |
  | http://localhost:8000
  |
  */

  static const String webBaseUrl = 'http://localhost:8000';

  /*
  |--------------------------------------------------------------------------
  | DIO TIMEOUTS
  |--------------------------------------------------------------------------
  |
  | Your ApiService already expects these values.
  |
  */

  static const Duration connectTimeout = Duration(seconds: 20);

  static const Duration receiveTimeout = Duration(seconds: 60);

  static const Duration sendTimeout = Duration(seconds: 60);
}
