import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/api_config.dart';

class ApiService {
  ApiService._();

  static final ApiService instance = ApiService._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static const String _tokenKey = 'auth_token';

  late final Dio dio =
      Dio(
          BaseOptions(
            baseUrl: _normalizeBaseUrl(ApiConfig.baseUrl),
            connectTimeout: ApiConfig.connectTimeout,
            receiveTimeout: ApiConfig.receiveTimeout,
            sendTimeout: ApiConfig.sendTimeout,
            headers: const <String, dynamic>{'Accept': 'application/json'},

            // Keep Laravel validation responses available to the
            // service classes instead of converting every 4xx into
            // an unhandled Dio error.
            validateStatus: (int? status) {
              return status != null && status < 500;
            },
          ),
        )
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest:
                (
                  RequestOptions options,
                  RequestInterceptorHandler handler,
                ) async {
                  final token = await getToken();

                  if (token != null && token.isNotEmpty) {
                    options.headers['Authorization'] = 'Bearer $token';
                  }

                  options.headers['Accept'] = 'application/json';

                  handler.next(options);
                },
            onError: (DioException error, ErrorInterceptorHandler handler) {
              handler.next(error);
            },
          ),
        );

  static String _normalizeBaseUrl(String value) {
    final trimmed = value.trim();

    if (trimmed.isEmpty) {
      throw StateError('API_BASE_URL cannot be empty.');
    }

    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }

  Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<String?> getToken() {
    return _storage.read(key: _tokenKey);
  }

  Future<void> removeToken() {
    return _storage.delete(key: _tokenKey);
  }

  Future<bool> hasToken() async {
    final token = await getToken();

    return token != null && token.trim().isNotEmpty;
  }
}
