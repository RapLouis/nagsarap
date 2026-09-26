class ApiConfig {
  ApiConfig._();

  /// --------------------------------------------------------------------------
  /// API BASE URL
  /// --------------------------------------------------------------------------
  ///
  /// Android emulator:
  ///   http://10.0.2.2:8000
  ///
  /// Physical phone / current ngrok testing:
  ///   https://femur-sulfur-capricorn.ngrok-free.dev
  ///
  /// You can always override this at runtime:
  ///
  /// flutter run \
  ///   --dart-define=API_BASE_URL=https://your-domain.com
  ///
  /// Flutter communicates with Laravel only.
  /// The Python biometric service must NOT be placed here.
  /// --------------------------------------------------------------------------

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://femur-sulfur-capricorn.ngrok-free.dev',
  );

  /// Laravel connection timeout.
  static const Duration connectTimeout = Duration(seconds: 20);

  /// Upload timeout for biometric frames.
  static const Duration sendTimeout = Duration(seconds: 60);

  /// Laravel/Python biometric processing can take longer.
  static const Duration receiveTimeout = Duration(seconds: 120);
}