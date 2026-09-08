class ApiConfig {
  ApiConfig._();

  /// Android Emulator -> Laravel running on the Mac.
  static const String baseUrl = 'http://10.0.2.2:8000';

  static const Duration connectTimeout = Duration(seconds: 20);

  static const Duration receiveTimeout = Duration(seconds: 120);

  static const Duration sendTimeout = Duration(seconds: 120);
}
