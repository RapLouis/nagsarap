import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/api_endpoints.dart';
import 'api_service.dart';

class AuthResult {
  final bool success;
  final String message;

  final Map<String, dynamic>? user;
  final Map<String, dynamic>? student;

  final bool offline;

  const AuthResult({
    required this.success,
    required this.message,
    this.user,
    this.student,
    this.offline = false,
  });
}

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  final ApiService _api = ApiService.instance;

  static const FlutterSecureStorage _storage =
      FlutterSecureStorage();

  static const String _cachedUserKey =
      'ccis_cached_user';

  static const String _cachedStudentKey =
      'ccis_cached_student';

  static const String _cachedSessionKey =
      'ccis_offline_session_enabled';

  // ===========================================================================
  // LOGIN
  //
  // First authentication MUST happen online.
  //
  // We intentionally do NOT store the password.
  //
  // After Laravel successfully authenticates the student:
  //
  // Laravel
  //   ↓
  // Sanctum token
  //   ↓
  // user/student profile cached securely
  //   ↓
  // future offline app launches can restore the verified session
  // ===========================================================================

  Future<AuthResult> login({
    required String studentNumber,
    required String password,
  }) async {
    try {
      final response = await _api.dio.post(
        ApiEndpoints.login,
        data: {
          'student_number':
              studentNumber.trim(),
          'password': password,
        },
      );

      final root = _asMap(
        response.data,
      );

      if (root == null) {
        return const AuthResult(
          success: false,
          message:
              'Invalid response from server.',
        );
      }

      if (root['success'] == false) {
        return AuthResult(
          success: false,
          message:
              root['message']
                  ?.toString() ??
              'Login failed.',
        );
      }

      final payload =
          _payload(root);

      final token =
          payload['token'] ??
          payload['access_token'] ??
          root['token'] ??
          root['access_token'];

      if (token == null ||
          token
              .toString()
              .trim()
              .isEmpty) {
        return AuthResult(
          success: false,
          message:
              root['message']
                  ?.toString() ??
              'Login failed. No authentication token was returned.',
        );
      }

      await _api.saveToken(
        token.toString(),
      );

      final parsed =
          _extractUserAndStudent(
        root,
      );

      final user = parsed.$1;
      final student = parsed.$2;

      await _saveOfflineSession(
        user: user,
        student: student,
      );

      return AuthResult(
        success: true,
        message:
            root['message']
                ?.toString() ??
            'Login successful.',
        user: user,
        student: student,
        offline: false,
      );
    } on DioException catch (e) {
      // A typed username/password login must not silently bypass Laravel.
      //
      // If the server cannot be contacted, the existing verified cached
      // session can still be restored by AuthGate/me().
      if (e.response == null) {
        return const AuthResult(
          success: false,
          message:
              'Internet is unavailable. '
              'If this device was previously signed in, reopen the app '
              'to restore the saved offline session.',
        );
      }

      return AuthResult(
        success: false,
        message:
            _extractErrorMessage(e),
      );
    } catch (_) {
      return const AuthResult(
        success: false,
        message:
            'Unable to log in. Please try again.',
      );
    }
  }

  // ===========================================================================
  // CURRENT USER / SESSION RESTORE
  //
  // ONLINE:
  // saved token
  //    ↓
  // Laravel /me
  //    ↓
  // refresh secure cache
  //
  // OFFLINE:
  // saved token
  //    ↓
  // Laravel unreachable
  //    ↓
  // restore last SERVER-VERIFIED local identity
  // ===========================================================================

  Future<AuthResult> me() async {
    final token =
        await _api.getToken();

    if (token == null ||
        token.isEmpty) {
      return const AuthResult(
        success: false,
        message:
            'No saved login session.',
      );
    }

    try {
      final response =
          await _api.dio.get(
        ApiEndpoints.me,
      );

      if (response.statusCode == 401) {
        await _clearLocalSession();

        return const AuthResult(
          success: false,
          message:
              'Your login session has expired.',
        );
      }

      final root =
          _asMap(response.data);

      if (root == null) {
        return const AuthResult(
          success: false,
          message:
              'Invalid response from server.',
        );
      }

      if (root['success'] == false) {
        return AuthResult(
          success: false,
          message:
              root['message']
                  ?.toString() ??
              'Unable to restore session.',
        );
      }

      final parsed =
          _extractUserAndStudent(
        root,
      );

      final user = parsed.$1;
      final student = parsed.$2;

      // Refresh the last known server-verified identity.
      await _saveOfflineSession(
        user: user,
        student: student,
      );

      return AuthResult(
        success: true,
        message:
            root['message']
                ?.toString() ??
            'Authenticated.',
        user: user,
        student: student,
        offline: false,
      );
    } on DioException catch (e) {
      // ==============================================================
      // SERVER REJECTED TOKEN
      // ==============================================================

      if (e.response?.statusCode == 401) {
        await _clearLocalSession();

        return const AuthResult(
          success: false,
          message:
              'Your login session has expired.',
        );
      }

      // ==============================================================
      // INTERNET / SERVER UNAVAILABLE
      //
      // No HTTP response means the app was unable to contact Laravel.
      //
      // Restore only a session that Laravel authenticated earlier.
      // ==============================================================

      if (e.response == null) {
        final cached =
            await restoreOfflineSession();

        if (cached.success) {
          return cached;
        }
      }

      return AuthResult(
        success: false,
        message:
            _extractErrorMessage(e),
      );
    } catch (_) {
      // Last fallback:
      // if networking itself failed unexpectedly, attempt trusted cache.
      final cached =
          await restoreOfflineSession();

      if (cached.success) {
        return cached;
      }

      return const AuthResult(
        success: false,
        message:
            'Unable to restore your login session.',
      );
    }
  }

  // ===========================================================================
  // RESTORE OFFLINE SESSION
  // ===========================================================================

  Future<AuthResult>
      restoreOfflineSession() async {
    try {
      final token =
          await _api.getToken();

      if (token == null ||
          token.isEmpty) {
        return const AuthResult(
          success: false,
          message:
              'No saved login session.',
        );
      }

      final enabled =
          await _storage.read(
        key: _cachedSessionKey,
      );

      if (enabled != 'true') {
        return const AuthResult(
          success: false,
          message:
              'Offline login has not been initialized on this device.',
        );
      }

      final userJson =
          await _storage.read(
        key: _cachedUserKey,
      );

      final studentJson =
          await _storage.read(
        key: _cachedStudentKey,
      );

      if ((userJson == null ||
              userJson.isEmpty) &&
          (studentJson == null ||
              studentJson.isEmpty)) {
        return const AuthResult(
          success: false,
          message:
              'No cached student session is available.',
        );
      }

      Map<String, dynamic>? user;
      Map<String, dynamic>? student;

      if (userJson != null &&
          userJson.isNotEmpty) {
        final decoded =
            jsonDecode(userJson);

        if (decoded is Map) {
          user =
              Map<String, dynamic>.from(
            decoded,
          );
        }
      }

      if (studentJson != null &&
          studentJson.isNotEmpty) {
        final decoded =
            jsonDecode(studentJson);

        if (decoded is Map) {
          student =
              Map<String, dynamic>.from(
            decoded,
          );
        }
      }

      if (user == null &&
          student == null) {
        return const AuthResult(
          success: false,
          message:
              'Saved offline session is invalid.',
        );
      }

      return AuthResult(
        success: true,
        message:
            'Offline session restored.',
        user: user,
        student: student,
        offline: true,
      );
    } catch (_) {
      return const AuthResult(
        success: false,
        message:
            'Unable to restore the offline session.',
      );
    }
  }

  // ===========================================================================
  // SAVE SERVER-VERIFIED SESSION
  // ===========================================================================

  Future<void> _saveOfflineSession({
    required Map<String, dynamic>? user,
    required Map<String, dynamic>? student,
  }) async {
    if (user != null) {
      await _storage.write(
        key: _cachedUserKey,
        value: jsonEncode(user),
      );
    }

    if (student != null) {
      await _storage.write(
        key: _cachedStudentKey,
        value: jsonEncode(student),
      );
    }

    // Do not enable offline session restoration unless at least one identity
    // object actually exists.
    if (user != null ||
        student != null) {
      await _storage.write(
        key: _cachedSessionKey,
        value: 'true',
      );
    }
  }

  // ===========================================================================
  // LOGOUT
  //
  // Explicit logout removes BOTH:
  // - Sanctum token
  // - offline identity cache
  //
  // Therefore a person cannot log out and then bypass authentication offline.
  // ===========================================================================

  Future<void> logout() async {
    try {
      await _api.dio.post(
        ApiEndpoints.logout,
      );
    } catch (_) {
      // Local logout must still complete even while offline.
    } finally {
      await _clearLocalSession();
    }
  }

  Future<void> _clearLocalSession() async {
    await _api.removeToken();

    await _storage.delete(
      key: _cachedUserKey,
    );

    await _storage.delete(
      key: _cachedStudentKey,
    );

    await _storage.delete(
      key: _cachedSessionKey,
    );
  }

  // ===========================================================================
  // SESSION STATE
  // ===========================================================================

  Future<bool> hasSavedSession() {
    return _api.hasToken();
  }

  Future<bool> hasOfflineSession() async {
    final token =
        await _api.getToken();

    if (token == null ||
        token.isEmpty) {
      return false;
    }

    final enabled =
        await _storage.read(
      key: _cachedSessionKey,
    );

    return enabled == 'true';
  }

  // ===========================================================================
  // RESPONSE PARSING
  // ===========================================================================

  Map<String, dynamic> _payload(
    Map<String, dynamic> root,
  ) {
    if (root['data'] is Map) {
      return Map<String, dynamic>.from(
        root['data'] as Map,
      );
    }

    return root;
  }

  (
    Map<String, dynamic>?,
    Map<String, dynamic>?
  ) _extractUserAndStudent(
    Map<String, dynamic> root,
  ) {
    final payload =
        _payload(root);

    Map<String, dynamic>? user;
    Map<String, dynamic>? student;

    if (payload['user'] is Map) {
      user =
          Map<String, dynamic>.from(
        payload['user'] as Map,
      );
    }

    if (payload['student'] is Map) {
      student =
          Map<String, dynamic>.from(
        payload['student'] as Map,
      );
    }

    if (student == null &&
        user != null &&
        user['student'] is Map) {
      student =
          Map<String, dynamic>.from(
        user['student'] as Map,
      );
    }

    if (user == null &&
        (payload.containsKey('id') ||
            payload.containsKey('email') ||
            payload.containsKey('name'))) {
      user =
          Map<String, dynamic>.from(
        payload,
      );
    }

    return (
      user,
      student,
    );
  }

  Map<String, dynamic>? _asMap(
    dynamic value,
  ) {
    if (value is Map) {
      return Map<String, dynamic>.from(
        value,
      );
    }

    return null;
  }

  // ===========================================================================
  // ERROR PARSING
  // ===========================================================================

  String _extractErrorMessage(
    DioException exception,
  ) {
    final response =
        exception.response;

    if (response == null) {
      return 'Unable to connect to the server.';
    }

    if (response.data is Map) {
      final data =
          Map<String, dynamic>.from(
        response.data as Map,
      );

      if (data['message'] != null) {
        return data['message']
            .toString();
      }

      if (data['error'] != null) {
        return data['error']
            .toString();
      }

      if (data['errors'] is Map) {
        final errors =
            Map<String, dynamic>.from(
          data['errors'] as Map,
        );

        if (errors.isNotEmpty) {
          final first =
              errors.values.first;

          if (first is List &&
              first.isNotEmpty) {
            return first.first
                .toString();
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

      case 429:
        return 'Too many requests. Please wait.';

      case 500:
        return 'The server encountered an error.';

      default:
        return 'Unable to complete the request.';
    }
  }
}