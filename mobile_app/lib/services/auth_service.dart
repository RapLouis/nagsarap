import 'package:dio/dio.dart';

import '../core/api_endpoints.dart';
import 'api_service.dart';

class AuthResult {
  final bool success;
  final String message;
  final Map<String, dynamic>? user;
  final Map<String, dynamic>? student;

  const AuthResult({
    required this.success,
    required this.message,
    this.user,
    this.student,
  });
}

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  final ApiService _api = ApiService.instance;

  // ===========================================================================
  // LOGIN
  // ===========================================================================

  Future<AuthResult> login({
    required String studentNumber,
    required String password,
  }) async {
    try {
      final response = await _api.dio.post(
        ApiEndpoints.login,
        data: {'student_number': studentNumber.trim(), 'password': password},
      );

      final root = _asMap(response.data);

      if (root == null) {
        return const AuthResult(
          success: false,
          message: 'Invalid response from server.',
        );
      }

      if (root['success'] == false) {
        return AuthResult(
          success: false,
          message: root['message']?.toString() ?? 'Login failed.',
        );
      }

      final payload = _payload(root);

      final token =
          payload['token'] ??
          payload['access_token'] ??
          root['token'] ??
          root['access_token'];

      if (token == null || token.toString().trim().isEmpty) {
        return AuthResult(
          success: false,
          message:
              root['message']?.toString() ??
              'Login failed. No authentication token was returned.',
        );
      }

      await _api.saveToken(token.toString());

      final parsed = _extractUserAndStudent(root);

      return AuthResult(
        success: true,
        message: root['message']?.toString() ?? 'Login successful.',
        user: parsed.$1,
        student: parsed.$2,
      );
    } on DioException catch (e) {
      return AuthResult(success: false, message: _extractErrorMessage(e));
    } catch (_) {
      return const AuthResult(
        success: false,
        message: 'Unable to log in. Please try again.',
      );
    }
  }

  // ===========================================================================
  // CURRENT USER
  // ===========================================================================

  Future<AuthResult> me() async {
    try {
      final token = await _api.getToken();

      if (token == null || token.isEmpty) {
        return const AuthResult(
          success: false,
          message: 'No saved login session.',
        );
      }

      final response = await _api.dio.get(ApiEndpoints.me);

      if (response.statusCode == 401) {
        await _api.removeToken();

        return const AuthResult(
          success: false,
          message: 'Your login session has expired.',
        );
      }

      final root = _asMap(response.data);

      if (root == null) {
        return const AuthResult(
          success: false,
          message: 'Invalid response from server.',
        );
      }

      if (root['success'] == false) {
        return AuthResult(
          success: false,
          message: root['message']?.toString() ?? 'Unable to restore session.',
        );
      }

      final parsed = _extractUserAndStudent(root);

      return AuthResult(
        success: true,
        message: root['message']?.toString() ?? 'Authenticated.',
        user: parsed.$1,
        student: parsed.$2,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        await _api.removeToken();
      }

      return AuthResult(success: false, message: _extractErrorMessage(e));
    } catch (_) {
      return const AuthResult(
        success: false,
        message: 'Unable to restore your login session.',
      );
    }
  }

  // ===========================================================================
  // LOGOUT
  // ===========================================================================

  Future<void> logout() async {
    try {
      await _api.dio.post(ApiEndpoints.logout);
    } catch (_) {
      // Always remove the local token.
    } finally {
      await _api.removeToken();
    }
  }

  Future<bool> hasSavedSession() {
    return _api.hasToken();
  }

  // ===========================================================================
  // RESPONSE PARSING
  // ===========================================================================

  Map<String, dynamic> _payload(Map<String, dynamic> root) {
    if (root['data'] is Map) {
      return Map<String, dynamic>.from(root['data'] as Map);
    }

    return root;
  }

  (Map<String, dynamic>?, Map<String, dynamic>?) _extractUserAndStudent(
    Map<String, dynamic> root,
  ) {
    final payload = _payload(root);

    Map<String, dynamic>? user;
    Map<String, dynamic>? student;

    if (payload['user'] is Map) {
      user = Map<String, dynamic>.from(payload['user'] as Map);
    }

    if (payload['student'] is Map) {
      student = Map<String, dynamic>.from(payload['student'] as Map);
    }

    if (student == null && user != null && user['student'] is Map) {
      student = Map<String, dynamic>.from(user['student'] as Map);
    }

    if (user == null &&
        (payload.containsKey('id') ||
            payload.containsKey('email') ||
            payload.containsKey('name'))) {
      user = Map<String, dynamic>.from(payload);
    }

    return (user, student);
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return null;
  }

  // ===========================================================================
  // ERROR PARSING
  // ===========================================================================

  String _extractErrorMessage(DioException exception) {
    final response = exception.response;

    if (response == null) {
      return 'Unable to connect to the server.';
    }

    if (response.data is Map) {
      final data = Map<String, dynamic>.from(response.data as Map);

      if (data['message'] != null) {
        return data['message'].toString();
      }

      if (data['error'] != null) {
        return data['error'].toString();
      }

      if (data['errors'] is Map) {
        final errors = Map<String, dynamic>.from(data['errors'] as Map);

        if (errors.isNotEmpty) {
          final first = errors.values.first;

          if (first is List && first.isNotEmpty) {
            return first.first.toString();
          }

          return first.toString();
        }
      }
    }

    switch (response.statusCode) {
      case 401:
        return 'Your login session has expired.';
      case 403:
        return 'Your account is not authorized.';
      case 422:
        return 'Please check the information you entered.';
      case 500:
        return 'The server encountered an error.';
      default:
        return 'Unable to complete the request.';
    }
  }
}
