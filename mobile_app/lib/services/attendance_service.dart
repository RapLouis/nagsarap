import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/api_endpoints.dart';
import 'api_service.dart';

class AttendanceService {
  AttendanceService._();

  static final AttendanceService instance =
      AttendanceService._();

  final ApiService _api = ApiService.instance;

  // ===========================================================================
  // ANALYZE ATTENDANCE LIVENESS FRAME
  // ===========================================================================

  Future<AttendanceLivenessFrameResult>
      analyzeLivenessFrame({
    required XFile frame,
  }) async {
    try {
      final formData = FormData.fromMap({
        'frame': await MultipartFile.fromFile(
          frame.path,
          filename: 'attendance-liveness-frame.jpg',
        ),
      });

      final response = await _api.dio.post(
        ApiEndpoints.analyzeAttendanceLivenessFrame,
        data: formData,
        options: Options(
          contentType: 'multipart/form-data',
          sendTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 20),
        ),
      );

      final responseMap = _asMap(response.data);

      if (responseMap == null) {
        return const AttendanceLivenessFrameResult(
          success: false,
          message: 'Invalid liveness response.',
        );
      }

      final data =
          _asMap(responseMap['data']) ??
          <String, dynamic>{};

      final success =
          responseMap['success'] == true;

      return AttendanceLivenessFrameResult(
        success: success,
        code: responseMap['code']?.toString(),
        message:
            responseMap['message']?.toString() ??
            (success
                ? 'Live frame analyzed.'
                : 'Unable to analyze frame.'),
        faceDetected:
            _boolValue(data['face_detected']),
        yaw:
            _doubleValue(data['yaw']),
        eyeOpenness:
            _doubleValue(data['eye_openness']),
        mouthWidth:
            _doubleValue(data['mouth_width']),
        blurScore:
            _doubleValue(data['blur_score']),
        detectionScore:
            _doubleValue(data['detection_score']),
        data: data,
      );
    } on DioException catch (e) {
      return AttendanceLivenessFrameResult(
        success: false,
        code: _extractCode(e),
        message: _extractErrorMessage(e),
      );
    } catch (e) {
      debugPrint(
        'ATTENDANCE LIVENESS FRAME ERROR: $e',
      );

      return const AttendanceLivenessFrameResult(
        success: false,
        message:
            'Unable to analyze the attendance camera frame.',
      );
    }
  }

  // ===========================================================================
  // MOBILE CHECK-IN
  // ===========================================================================

  Future<AttendanceResult> mobileCheckIn({
    required int eventId,
    required double latitude,
    required double longitude,
    required double locationAccuracy,
    required XFile centerFrame,
    required XFile blinkFrame,
    required XFile turnedFrame,
    required XFile smileFrame,
    required XFile returnedFrame,
  }) async {
    try {
      final formData = FormData.fromMap({
        'event_id': eventId,

        'latitude': latitude,

        'longitude': longitude,

        'location_accuracy':
            locationAccuracy,

        'center_frame':
            await MultipartFile.fromFile(
          centerFrame.path,
          filename: 'attendance-center.jpg',
        ),

        'blink_frame':
            await MultipartFile.fromFile(
          blinkFrame.path,
          filename: 'attendance-blink.jpg',
        ),

        'turned_frame':
            await MultipartFile.fromFile(
          turnedFrame.path,
          filename: 'attendance-turned.jpg',
        ),

        'smile_frame':
            await MultipartFile.fromFile(
          smileFrame.path,
          filename: 'attendance-smile.jpg',
        ),

        'returned_frame':
            await MultipartFile.fromFile(
          returnedFrame.path,
          filename: 'attendance-returned.jpg',
        ),
      });

      final response = await _api.dio.post(
        ApiEndpoints.attendanceMobileCheckIn,
        data: formData,
        options: Options(
          contentType: 'multipart/form-data',
          sendTimeout: const Duration(
            seconds: 60,
          ),
          receiveTimeout: const Duration(
            seconds: 120,
          ),
        ),
      );

      final responseMap =
          _asMap(response.data);

      if (responseMap == null) {
        return const AttendanceResult(
          success: false,
          message:
              'Invalid attendance response from server.',
        );
      }

      final success =
          responseMap['success'] == true;

      return AttendanceResult(
        success: success,
        code:
            responseMap['code']?.toString(),
        message:
            responseMap['message']?.toString() ??
            (success
                ? 'Attendance recorded successfully.'
                : 'Attendance verification failed.'),
        data:
            _asMap(responseMap['data']),
      );
    } on DioException catch (e) {
      debugPrint(
        'ATTENDANCE CHECK-IN HTTP ERROR: '
        '${e.response?.statusCode} '
        '${e.response?.data}',
      );

      return AttendanceResult(
        success: false,
        code: _extractCode(e),
        message: _extractErrorMessage(e),
        data: _asMap(
          _asMap(e.response?.data)?['data'],
        ),
      );
    } catch (e) {
      debugPrint(
        'ATTENDANCE CHECK-IN ERROR: $e',
      );

      return const AttendanceResult(
        success: false,
        message:
            'Unable to complete attendance verification.',
      );
    }
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

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

  bool _boolValue(
    dynamic value,
  ) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    if (value is String) {
      final normalized =
          value.trim().toLowerCase();

      return normalized == 'true' ||
          normalized == '1';
    }

    return false;
  }

  double? _doubleValue(
    dynamic value,
  ) {
    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value);
    }

    return null;
  }

  String? _extractCode(
    DioException exception,
  ) {
    final raw =
        exception.response?.data;

    if (raw is Map) {
      return raw['code']?.toString();
    }

    return null;
  }

  String _extractErrorMessage(
    DioException exception,
  ) {
    final response =
        exception.response;

    if (response == null) {
      return 'Unable to connect to the server. '
          'Make sure Laravel and the Python biometric '
          'service are running.';
    }

    final raw = response.data;

    if (raw is Map) {
      final data =
          Map<String, dynamic>.from(
        raw,
      );

      final errors = data['errors'];

      if (errors is Map &&
          errors.isNotEmpty) {
        final first =
            errors.values.first;

        if (first is List &&
            first.isNotEmpty) {
          return first.first.toString();
        }

        return first.toString();
      }

      if (data['message'] != null) {
        return data['message']
            .toString();
      }
    }

    switch (response.statusCode) {
      case 401:
        return 'Your login session has expired. Please log in again.';

      case 403:
        return 'Your account is not allowed to record attendance.';

      case 404:
        return 'The attendance event could not be found.';

      case 409:
        return 'Attendance has already been recorded for this event.';

      case 422:
        return 'Attendance verification failed. Please try again.';

      case 429:
        return 'Too many verification requests. Please wait a moment and try again.';

      default:
        return 'Attendance verification failed. Please try again.';
    }
  }
}

// =============================================================================
// ATTENDANCE RESULT
// =============================================================================

class AttendanceResult {
  const AttendanceResult({
    required this.success,
    required this.message,
    this.code,
    this.data,
  });

  final bool success;
  final String message;
  final String? code;
  final Map<String, dynamic>? data;

  factory AttendanceResult.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];

    return AttendanceResult(
      success: json['success'] == true,
      message: json['message']?.toString() ?? 'Unknown attendance response.',
      code: json['code']?.toString(),
      data: rawData is Map
          ? Map<String, dynamic>.from(rawData)
          : null,
    );
  }
}

// =============================================================================
// ATTENDANCE LIVENESS FRAME RESULT
// =============================================================================

class AttendanceLivenessFrameResult {
  final bool success;
  final String? code;
  final String message;

  final bool faceDetected;

  final double? yaw;
  final double? eyeOpenness;
  final double? mouthWidth;

  final double? blurScore;
  final double? detectionScore;

  final Map<String, dynamic>? data;

  const AttendanceLivenessFrameResult({
    required this.success,
    this.code,
    required this.message,
    this.faceDetected = false,
    this.yaw,
    this.eyeOpenness,
    this.mouthWidth,
    this.blurScore,
    this.detectionScore,
    this.data,
  });
}