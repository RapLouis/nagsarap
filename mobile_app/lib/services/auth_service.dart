import 'package:dio/dio.dart';

import '../core/api_endpoints.dart';
import 'api_service.dart';

class AuthResult {
  final bool success;
  final String message;

  final Map<String, dynamic>? user;
  final Map<String, dynamic>? student;

  AuthResult({
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

  /*
  |--------------------------------------------------------------------------
  | LOGIN
  |--------------------------------------------------------------------------
  */

  Future<AuthResult> login({
    required String studentNumber,
    required String password,
  }) async {
    try {
      final response = await _api.dio.post(
        ApiEndpoints.login,
        data: {'student_number': studentNumber.trim(), 'password': password},
      );

      final dynamic raw = response.data;

      if (raw is! Map) {
        return AuthResult(
          success: false,
          message: 'Invalid response from server.',
        );
      }

      final data = Map<String, dynamic>.from(raw);

      final dynamic tokenValue = data['token'] ?? data['access_token'];

      if (tokenValue == null || tokenValue.toString().isEmpty) {
        return AuthResult(
          success: false,
          message:
              data['message']?.toString() ??
              'Login failed. No authentication token was returned.',
        );
      }

      await _api.saveToken(tokenValue.toString());

      final parsed = _extractUserAndStudent(data);

      return AuthResult(
        success: true,
        message: data['message']?.toString() ?? 'Login successful.',
        user: parsed.$1,
        student: parsed.$2,
      );
    } on DioException catch (e) {
      return AuthResult(success: false, message: _extractErrorMessage(e));
    } catch (e) {
      return AuthResult(
        success: false,
        message: 'Unable to log in. Please try again.',
      );
    }
  }

  /*
  |--------------------------------------------------------------------------
  | CURRENT AUTHENTICATED USER
  |--------------------------------------------------------------------------
  */

  Future<AuthResult> me() async {
    try {
      final token = await _api.getToken();

      if (token == null || token.isEmpty) {
        return AuthResult(success: false, message: 'No saved login session.');
      }

      final response = await _api.dio.get(ApiEndpoints.me);

      final dynamic raw = response.data;

      if (raw is! Map) {
        return AuthResult(
          success: false,
          message: 'Invalid response from server.',
        );
      }

      final data = Map<String, dynamic>.from(raw);

      final parsed = _extractUserAndStudent(data);

      return AuthResult(
        success: true,
        message: data['message']?.toString() ?? 'Authenticated.',
        user: parsed.$1,
        student: parsed.$2,
      );
    } on DioException catch (e) {
      /*
       * If token is invalid/expired,
       * delete it so the user is sent
       * back to login.
       */
      if (e.response?.statusCode == 401) {
        await _api.removeToken();
      }

      return AuthResult(success: false, message: _extractErrorMessage(e));
    } catch (e) {
      return AuthResult(
        success: false,
        message: 'Unable to restore your login session.',
      );
    }
  }

  /*
  |--------------------------------------------------------------------------
  | LOGOUT
  |--------------------------------------------------------------------------
  */

  Future<void> logout() async {
    try {
      await _api.dio.post(ApiEndpoints.logout);
    } catch (_) {
      /*
       * Logout locally even if
       * Laravel cannot be reached.
       */
    } finally {
      await _api.removeToken();
    }
  }

  /*
  |--------------------------------------------------------------------------
  | HAS TOKEN
  |--------------------------------------------------------------------------
  */

  Future<bool> hasSavedSession() async {
    return _api.hasToken();
  }

  /*
  |--------------------------------------------------------------------------
  | RESPONSE PARSING
  |--------------------------------------------------------------------------
  */

  (Map<String, dynamic>?, Map<String, dynamic>?) _extractUserAndStudent(
    Map<String, dynamic> data,
  ) {
    Map<String, dynamic>? user;
    Map<String, dynamic>? student;

    /*
     * API may return:
     *
     * {
     *   user: {...},
     *   student: {...}
     * }
     */

    if (data['user'] is Map) {
      user = Map<String, dynamic>.from(data['user'] as Map);
    }

    if (data['student'] is Map) {
      student = Map<String, dynamic>.from(data['student'] as Map);
    }

    /*
     * Or:
     *
     * {
     *   user: {
     *     ...,
     *     student: {...}
     *   }
     * }
     */

    if (student == null && user != null && user['student'] is Map) {
      student = Map<String, dynamic>.from(user['student'] as Map);
    }

    /*
     * Or /me may directly return:
     *
     * {
     *   id: ...,
     *   email: ...,
     *   student: {...}
     * }
     */

    if (user == null && (data.containsKey('id') || data.containsKey('email'))) {
      user = Map<String, dynamic>.from(data);

      if (data['student'] is Map) {
        student = Map<String, dynamic>.from(data['student'] as Map);
      }
    }

    return (user, student);
  }

  /*
  |--------------------------------------------------------------------------
  | ERROR PARSING
  |--------------------------------------------------------------------------
  */

  String _extractErrorMessage(DioException exception) {
    final response = exception.response;

    if (response == null) {
      return 'Unable to connect to the server.';
    }

    final dynamic raw = response.data;

    if (raw is Map) {
      final data = Map<String, dynamic>.from(raw);

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
