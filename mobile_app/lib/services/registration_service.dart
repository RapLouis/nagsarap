import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../core/api_config.dart';
import '../core/api_endpoints.dart';
import '../models/liveness_challenge.dart';
import 'api_service.dart';
import 'image_compress_service.dart';

class LivenessChallengeResult {
  final LivenessChallenge? challenge;
  final bool success;
  final bool networkUnavailable;
  final String message;

  const LivenessChallengeResult({
    this.challenge,
    required this.success,
    required this.networkUnavailable,
    required this.message,
  });
}

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
  final double? faceCenterX;
  final double? faceCenterY;
  final bool faceInComfortableZone;
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
    this.faceCenterX,
    this.faceCenterY,
    this.faceInComfortableZone = true,
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

  Future<ReferencePhotoValidationResult> validateReferencePhoto({
    required XFile profilePhoto,
  }) async {
    try {
      final compressedPhoto = await ImageCompressService.compressFrame(
        profilePhoto,
        quality: 75,
        minWidth: 640,
        minHeight: 640,
      );

      final formData = FormData.fromMap({
        'profile_photo': await MultipartFile.fromFile(
          compressedPhoto.path,
          filename: compressedPhoto.name,
        ),
      });

      final response = await _api.dio.post(
        ApiEndpoints.validateReferencePhoto,
        data: formData,
        options: Options(
          contentType: 'multipart/form-data',
          sendTimeout: ApiConfig.sendTimeout,
          receiveTimeout: ApiConfig.receiveTimeout,
        ),
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
      debugPrint(
        'VALIDATE PHOTO DIO ERROR [${e.type}]: ${e.message} | URL: ${e.requestOptions.uri}',
      );
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
      final compressedPhoto = await ImageCompressService.compressFrame(
        profilePhoto,
        quality: 78,
        minWidth: 720,
        minHeight: 720,
      );

      final files = await Future.wait([
        MultipartFile.fromFile(
          compressedPhoto.path,
          filename: compressedPhoto.name,
        ),
        MultipartFile.fromFile(
          form5.path,
          filename: form5.name,
        ),
      ]);

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
        'profile_photo': files[0],
        'form_5': files[1],
      });

      final response = await _api.dio.post(
        ApiEndpoints.register,
        data: formData,
        options: Options(
          contentType: 'multipart/form-data',
          sendTimeout: ApiConfig.sendTimeout,
          receiveTimeout: ApiConfig.receiveTimeout,
        ),
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

  Future<LivenessChallengeResult> requestLivenessChallenge() async {
    final sessionId = const Uuid().v4();

    try {
      final response = await _api.dio.post(
        ApiEndpoints.registrationLivenessChallenge,
        data: {'session_id': sessionId},
        options: Options(
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

      final map = _asMap(response.data);
      final data = _asMap(map?['data']);
      final direction = data?['direction']?.toString();
      final nonce = data?['nonce']?.toString();

      final validDirection = direction == 'left' || direction == 'right';

      if (map?['success'] == true &&
          nonce != null &&
          nonce.isNotEmpty &&
          validDirection) {
        return LivenessChallengeResult(
          success: true,
          networkUnavailable: false,
          message: 'Liveness challenge issued.',
          challenge: LivenessChallenge(
            nonce: nonce,
            direction: direction!,
            sessionId: sessionId,
            expiresAt: data?['expires_at'] is num
                ? (data!['expires_at'] as num).toInt()
                : null,
          ),
        );
      }

      return LivenessChallengeResult(
        success: false,
        networkUnavailable: false,
        message:
            map?['message']?.toString() ??
            'Unable to start the liveness challenge.',
      );
    } on DioException catch (e) {
      return LivenessChallengeResult(
        success: false,
        networkUnavailable: e.response == null,
        message: _extractErrorMessage(e),
      );
    } catch (e) {
      debugPrint('REGISTRATION CHALLENGE ERROR: $e');
      return const LivenessChallengeResult(
        success: false,
        networkUnavailable: false,
        message: 'Unable to start the liveness challenge.',
      );
    }
  }

  Future<LivenessFrameResult> analyzeLivenessFrame({
    required XFile frame,
  }) async {
    try {
      final compressedFrame = await ImageCompressService.compressFrame(
        frame,
        quality: 65,
        minWidth: 480,
        minHeight: 640,
      );

      final formData = FormData.fromMap({
        'frame': await MultipartFile.fromFile(
          compressedFrame.path,
          filename: 'liveness-frame.jpg',
        ),
      });

      final response = await _api.dio.post(
        ApiEndpoints.analyzeRegistrationLivenessFrame,
        data: formData,
        options: Options(
          contentType: 'multipart/form-data',
          sendTimeout: const Duration(seconds: 15),
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

      return LivenessFrameResult(
        success: success,
        code: responseMap['code']?.toString(),
        message:
            responseMap['message']?.toString() ??
            (success ? 'Live frame analyzed.' : 'Unable to analyze frame.'),
        faceDetected: _boolValue(data['face_detected']),
        yaw: _doubleValue(data['yaw']),
        faceCenterX: _doubleValue(data['face_center_x']),
        faceCenterY: _doubleValue(data['face_center_y']),
        faceInComfortableZone: data['face_in_comfortable_zone'] == null
            ? true
            : _boolValue(data['face_in_comfortable_zone']),
        eyeOpenness: _doubleValue(data['eye_openness']),
        mouthWidth: _doubleValue(data['mouth_width']),
        blurScore: _doubleValue(data['blur_score']),
        detectionScore: _doubleValue(data['detection_score']),
        data: data,
      );
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

  Future<BiometricVerificationResult> verifyRegistrationFace({
    required XFile centerFrame,
    required XFile turnedFrame,
    required List<XFile> flashFrames,
    required List<String> flashColors,
    required String challengeNonce,
    required String sessionId,
  }) async {
    try {
      final compressedResults = await Future.wait([
        ImageCompressService.compressFrame(
          centerFrame,
          quality: 75,
          minWidth: 640,
          minHeight: 640,
        ),
        ImageCompressService.compressFrame(
          turnedFrame,
          quality: 75,
          minWidth: 640,
          minHeight: 640,
        ),
      ]);

      final compressedCenter = compressedResults[0];
      final compressedTurned = compressedResults[1];
      final compressedFlashFrames = await ImageCompressService.compressBatch(
        flashFrames,
        quality: 88,
      );

      final multipartCenter = await MultipartFile.fromFile(
        compressedCenter.path,
        filename: 'center.jpg',
      );
      final multipartTurned = await MultipartFile.fromFile(
        compressedTurned.path,
        filename: 'turned.jpg',
      );

      final flashMultiparts = await Future.wait(
        List.generate(
          compressedFlashFrames.length,
          (i) => MultipartFile.fromFile(
            compressedFlashFrames[i].path,
            filename: 'flash_$i.jpg',
          ),
        ),
      );

      final Map<String, dynamic> formMap = {
        'challenge_nonce': challengeNonce,
        'session_id': sessionId,
        'center_frame': multipartCenter,
        'turned_frame': multipartTurned,
      };

      for (int i = 0; i < flashMultiparts.length; i++) {
        formMap['flash_images_base64[$i]'] = flashMultiparts[i];
        formMap['flash_colors[$i]'] = flashColors[i];
      }

      final formData = FormData.fromMap(formMap);

      final response = await _api.dio.post(
        ApiEndpoints.verifyRegistrationFace,
        data: formData,
        options: Options(
          contentType: 'multipart/form-data',
          sendTimeout: ApiConfig.sendTimeout,
          receiveTimeout: ApiConfig.receiveTimeout,
        ),
      );

      final responseMap = _asMap(response.data);

      if (responseMap == null) {
        return const BiometricVerificationResult(
          success: false,
          message: 'Invalid biometric verification response.',
        );
      }

      return BiometricVerificationResult(
        success: responseMap['success'] == true,
        code: responseMap['code']?.toString(),
        message:
            responseMap['message']?.toString() ??
            'Biometric verification completed.',
        data: _asMap(responseMap['data']),
      );
    } on DioException catch (e) {
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

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }

  bool _boolValue(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1';
    }
    return false;
  }

  double? _doubleValue(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
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
      switch (exception.type) {
        case DioExceptionType.connectionTimeout:
          return 'Connection timed out while reaching ${ApiConfig.baseUrl}. Check your internet connection and try again.';
        case DioExceptionType.sendTimeout:
          return 'Photo upload timed out. Please check your network speed and try again.';
        case DioExceptionType.receiveTimeout:
          return 'The server took too long to analyze the photo. Please try again.';
        case DioExceptionType.badCertificate:
          return 'SSL certificate verification failed for ${ApiConfig.baseUrl}.';
        case DioExceptionType.cancel:
          return 'Request was cancelled.';
        default:
          return 'Unable to connect to ${ApiConfig.baseUrl}. Check your phone internet connection or verify Laravel and Python are running.';
      }
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