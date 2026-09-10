import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/student_profile.dart';
import 'api_service.dart';

class ProfileResult {
  final bool success;
  final String message;
  final StudentProfile? profile;

  const ProfileResult({
    required this.success,
    required this.message,
    required this.profile,
  });
}

class ProfileService {
  ProfileService._();

  static final ProfileService instance = ProfileService._();

  final ApiService _api = ApiService.instance;

  Future<ProfileResult> getProfile() async {
    try {
      final response = await _api.dio.get('/api/v1/me');

      final raw = response.data;

      if (raw is! Map) {
        return const ProfileResult(
          success: false,
          message: 'Invalid response from the server.',
          profile: null,
        );
      }

      final body = Map<String, dynamic>.from(raw);

      if (body['success'] == false) {
        return ProfileResult(
          success: false,
          message: body['message']?.toString() ?? 'Unable to load profile.',
          profile: null,
        );
      }

      final dynamic rawData = body['data'];

      Map<String, dynamic> data;

      if (rawData is Map) {
        data = Map<String, dynamic>.from(rawData);
      } else {
        data = body;
      }

      final profile = StudentProfile.fromJson(data);

      return ProfileResult(
        success: true,
        message: body['message']?.toString() ?? 'Profile loaded successfully.',
        profile: profile,
      );
    } on DioException catch (e) {
      return ProfileResult(
        success: false,
        message: _errorMessage(e),
        profile: null,
      );
    } catch (e) {
      debugPrint('PROFILE ERROR: $e');

      return const ProfileResult(
        success: false,
        message: 'Unable to load your profile.',
        profile: null,
      );
    }
  }

  String _errorMessage(DioException exception) {
    final response = exception.response;

    if (response == null) {
      return 'Unable to connect to Laravel.';
    }

    final raw = response.data;

    if (raw is Map) {
      final body = Map<String, dynamic>.from(raw);

      final message = body['message']?.toString();

      if (message != null && message.trim().isNotEmpty) {
        return message;
      }
    }

    if (response.statusCode == 401) {
      return 'Your session has expired. Please log in again.';
    }

    return 'Unable to load your profile.';
  }
}
