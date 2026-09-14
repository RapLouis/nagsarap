class ApiConfig {
  ApiConfig._();

  /// Local Android emulator:
  ///   flutter run
  ///
  /// Production / real phones:
  ///   flutter build apk --release \
  ///     --dart-define=API_BASE_URL=https://api.yourdomain.com
  ///
  /// Never put the Python biometric service URL here.
  /// Flutter communicates only with Laravel.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static const Duration connectTimeout = Duration(seconds: 20);

  static const Duration sendTimeout = Duration(seconds: 60);

  static const Duration receiveTimeout = Duration(seconds: 120);
}
