import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api_endpoints.dart';
import 'api_service.dart';

class ReferencePhotoValidationResult {
  final bool success;
  final String message;
  final String? code;

  const ReferencePhotoValidationResult({
    required this.success,
    required this.message,
    this.code,
  });
}

class RegistrationResult {
  final bool success;
  final String message;
  final String? code;
  final Map<String, dynamic>? data;

  const RegistrationResult({
    required this.success,
    required this.message,
    this.code,
    this.data,
  });
}

class LivenessFrameResult {
  final bool success;
  final String message;
  final String? code;

  final bool faceDetected;

  final double? yaw;
  final double? eyeOpenness;
  final double? mouthWidth;

  final double? blurScore;
  final double? detectionScore;

  final Map<String, dynamic>? data;

  const LivenessFrameResult({
    required this.success,
    required this.message,
    this.code,
    this.faceDetected = false,
    this.yaw,
    this.eyeOpenness,
    this.mouthWidth,
    this.blurScore,
    this.detectionScore,
    this.data,
  });
}

class BiometricVerificationResult {
  final bool success;
  final String message;
  final String? code;
  final Map<String, dynamic>? data;

  const BiometricVerificationResult({
    required this.success,
    required this.message,
    this.code,
    this.data,
  });
}

class RegistrationService {
  RegistrationService._();

  static final RegistrationService instance = RegistrationService._();

  final ApiService _api = ApiService.instance;

  // ===========================================================================
  // REFERENCE PHOTO
  // ===========================================================================

  Future<ReferencePhotoValidationResult> validateReferencePhoto({
    required XFile profilePhoto,
  }) async {
    try {
      final formData = FormData.fromMap({
        'profile_photo': await MultipartFile.fromFile(
          profilePhoto.path,
          filename: profilePhoto.name,
        ),
      });

      final response = await _api.dio.post(
        ApiEndpoints.validateReferencePhoto,
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );

      final map = _asMap(response.data);

      if (map == null) {
        return const ReferencePhotoValidationResult(
          success: false,
          message: 'Invalid response from the server.',
        );
      }

      return ReferencePhotoValidationResult(
        success: map['success'] == true,
        code: map['code']?.toString(),
        message: map['message']?.toString() ?? 'Photo validation completed.',
      );
    } on DioException catch (e) {
      return ReferencePhotoValidationResult(
        success: false,
        code: _extractCode(e),
        message: _extractErrorMessage(e),
      );
    } catch (e) {
      debugPrint('REFERENCE PHOTO ERROR: $e');

      return const ReferencePhotoValidationResult(
        success: false,
        message: 'Unable to validate the reference photo.',
      );
    }
  }

  // ===========================================================================
  // REGISTER
  // ===========================================================================

  Future<RegistrationResult> register({
    required String studentNumber,
    required String surname,
    required String firstname,
    required String middlename,
    required String ext,
    required String email,
    required String password,
    required String passwordConfirmation,
    required XFile profilePhoto,
    required XFile form5,
  }) async {
    try {
      final formData = FormData.fromMap({
        'student_number': studentNumber.trim(),

        'surname': surname.trim(),

        'firstname': firstname.trim(),

        'middlename': middlename.trim().isEmpty ? null : middlename.trim(),

        'ext': ext.trim().isEmpty ? null : ext.trim(),

        'email': email.trim(),

        'password': password,

        'password_confirmation': passwordConfirmation,

        'device_name': 'Flutter Android',

        'profile_photo': await MultipartFile.fromFile(
          profilePhoto.path,
          filename: profilePhoto.name,
        ),

        'form_5': await MultipartFile.fromFile(
          form5.path,
          filename: form5.name,
        ),
      });

      final response = await _api.dio.post(
        ApiEndpoints.register,
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );

      final responseMap = _asMap(response.data);

      if (responseMap == null) {
        return const RegistrationResult(
          success: false,
          message: 'Invalid response from server.',
        );
      }

      final data = _asMap(responseMap['data']) ?? <String, dynamic>{};

      final token = data['token']?.toString();

      if (token != null && token.isNotEmpty) {
        await _api.saveToken(token);
      }

      final success =
          responseMap['success'] == true || response.statusCode == 201;

      return RegistrationResult(
        success: success,
        code: responseMap['code']?.toString(),
        message:
            responseMap['message']?.toString() ??
            (success ? 'Registration successful.' : 'Registration failed.'),
        data: data,
      );
    } on DioException catch (e) {
      return RegistrationResult(
        success: false,
        code: _extractCode(e),
        message: _extractErrorMessage(e),
      );
    } catch (e) {
      debugPrint('REGISTRATION ERROR: $e');

      return const RegistrationResult(
        success: false,
        message: 'Unable to register. Please try again.',
      );
    }
  }

  // ===========================================================================
  // ANALYZE LIVE FRAME
  // ===========================================================================

  Future<LivenessFrameResult> analyzeLivenessFrame({
    required XFile frame,
  }) async {
    try {
      final formData = FormData.fromMap({
        'frame': await MultipartFile.fromFile(
          frame.path,
          filename: 'liveness-frame.jpg',
        ),
      });

      final response = await _api.dio.post(
        ApiEndpoints.analyzeRegistrationLivenessFrame,
        data: formData,
        options: Options(
          contentType: 'multipart/form-data',
          sendTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 20),
        ),
      );

      final responseMap = _asMap(response.data);

      if (responseMap == null) {
        return const LivenessFrameResult(
          success: false,
          message: 'Invalid liveness response.',
        );
      }

      final data = _asMap(responseMap['data']) ?? <String, dynamic>{};

      final success = responseMap['success'] == true;

      final result = LivenessFrameResult(
        success: success,

        code: responseMap['code']?.toString(),

        message:
            responseMap['message']?.toString() ??
            (success ? 'Live frame analyzed.' : 'Unable to analyze frame.'),

        faceDetected: _boolValue(data['face_detected']),

        yaw: _doubleValue(data['yaw']),

        eyeOpenness: _doubleValue(data['eye_openness']),

        mouthWidth: _doubleValue(data['mouth_width']),

        blurScore: _doubleValue(data['blur_score']),

        detectionScore: _doubleValue(data['detection_score']),

        data: data,
      );

      debugPrint(
        'LIVENESS FRAME: '
        'face=${result.faceDetected} '
        'yaw=${result.yaw} '
        'eye=${result.eyeOpenness} '
        'mouth=${result.mouthWidth}',
      );

      return result;
    } on DioException catch (e) {
      return LivenessFrameResult(
        success: false,
        code: _extractCode(e),
        message: _extractErrorMessage(e),
      );
    } catch (e) {
      debugPrint('LIVENESS FRAME ERROR: $e');

      return const LivenessFrameResult(
        success: false,
        message: 'Unable to analyze the camera frame.',
      );
    }
  }

  // ===========================================================================
  // FINAL VERIFICATION
  // ===========================================================================

  Future<BiometricVerificationResult> verifyRegistrationFace({
    required XFile centerFrame,
    required XFile blinkFrame,
    required XFile turnedFrame,
    required XFile smileFrame,
    required XFile returnedFrame,
  }) async {
    try {
      /*
       * returnedFrame is also the final live_camera_frame.
       *
       * Laravel requires:
       *
       * center_frame
       * blink_frame
       * turned_frame
       * smile_frame
       * returned_frame
       * live_camera_frame
       */

      final formData = FormData.fromMap({
        'center_frame': await MultipartFile.fromFile(
          centerFrame.path,
          filename: 'center.jpg',
        ),

        'blink_frame': await MultipartFile.fromFile(
          blinkFrame.path,
          filename: 'blink.jpg',
        ),

        'turned_frame': await MultipartFile.fromFile(
          turnedFrame.path,
          filename: 'turned.jpg',
        ),

        'smile_frame': await MultipartFile.fromFile(
          smileFrame.path,
          filename: 'smile.jpg',
        ),

        'returned_frame': await MultipartFile.fromFile(
          returnedFrame.path,
          filename: 'returned.jpg',
        ),

        'live_camera_frame': await MultipartFile.fromFile(
          returnedFrame.path,
          filename: 'live-camera.jpg',
        ),
      });

      final response = await _api.dio.post(
        ApiEndpoints.verifyRegistrationFace,
        data: formData,
        options: Options(
          contentType: 'multipart/form-data',
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 120),
        ),
      );

      final responseMap = _asMap(response.data);

      if (responseMap == null) {
        return const BiometricVerificationResult(
          success: false,
          message: 'Invalid biometric verification response.',
        );
      }

      debugPrint('FINAL BIOMETRIC RESPONSE: $responseMap');

      return BiometricVerificationResult(
        success: responseMap['success'] == true,

        code: responseMap['code']?.toString(),

        message:
            responseMap['message']?.toString() ??
            'Biometric verification completed.',

        data: _asMap(responseMap['data']),
      );
    } on DioException catch (e) {
      debugPrint(
        'FINAL VERIFY HTTP ERROR: '
        '${e.response?.statusCode} '
        '${e.response?.data}',
      );

      return BiometricVerificationResult(
        success: false,
        code: _extractCode(e),
        message: _extractErrorMessage(e),
      );
    } catch (e) {
      debugPrint('FINAL VERIFY ERROR: $e');

      return const BiometricVerificationResult(
        success: false,
        message: 'Unable to complete biometric verification.',
      );
    }
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return null;
  }

  bool _boolValue(dynamic value) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    if (value is String) {
      final normalized = value.trim().toLowerCase();

      return normalized == 'true' || normalized == '1';
    }

    return false;
  }

  double? _doubleValue(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value);
    }

    return null;
  }

  String? _extractCode(DioException exception) {
    final raw = exception.response?.data;

    if (raw is Map) {
      return raw['code']?.toString();
    }

    return null;
  }

  String _extractErrorMessage(DioException exception) {
    final response = exception.response;

    if (response == null) {
      return 'Unable to connect to the server. Make sure Laravel and the Python biometric service are running.';
    }

    final raw = response.data;

    if (raw is Map) {
      final data = Map<String, dynamic>.from(raw);

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

      if (data['message'] != null) {
        return data['message'].toString();
      }

      if (data['detail'] != null) {
        return data['detail'].toString();
      }
    }

    return 'Request failed with HTTP ${response.statusCode}.';
  }
}
