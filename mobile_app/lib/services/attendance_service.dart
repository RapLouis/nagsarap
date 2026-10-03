import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/liveness_challenge.dart';
import '../core/api_endpoints.dart';
import 'api_service.dart';
import 'offline_storage_service.dart';

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

class AttendanceService {
  AttendanceService._();

  static final AttendanceService instance = AttendanceService._();

  final ApiService _api = ApiService.instance;
  final OfflineStorageService _offlineStorage = OfflineStorageService.instance;

  Future<OfflineSyncResult>? _activeOfflineSync;

  Future<LivenessChallengeResult> requestLivenessChallenge({
    required int eventId,
  }) async {
    final sessionId = const Uuid().v4();

    try {
      final response = await _api.dio.post(
        ApiEndpoints.attendanceLivenessChallenge,
        data: {'event_id': eventId, 'session_id': sessionId},
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
            'Unable to start liveness challenge.',
      );
    } on DioException catch (e) {
      debugPrint(
        'ATTENDANCE CHALLENGE DIO ERROR: ${e.response?.statusCode} - ${e.response?.data}',
      );
      return LivenessChallengeResult(
        success: false,
        networkUnavailable: e.response == null,
        message: _extractErrorMessage(e),
      );
    } catch (e) {
      debugPrint('ATTENDANCE CHALLENGE ERROR: $e');
      return const LivenessChallengeResult(
        success: false,
        networkUnavailable: false,
        message: 'Unable to start liveness challenge.',
      );
    }
  }

  Future<AttendanceLivenessFrameResult> analyzeLivenessFrame({
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
          sendTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 12),
        ),
      );

      final map = _asMap(response.data);

      if (map == null) {
        return const AttendanceLivenessFrameResult(
          success: false,
          message: 'Invalid liveness response.',
        );
      }

      final data = _asMap(map['data']) ?? <String, dynamic>{};

      return AttendanceLivenessFrameResult(
        success: map['success'] == true,
        code: map['code']?.toString(),
        message: map['message']?.toString() ?? 'Frame analyzed.',
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
      return AttendanceLivenessFrameResult(
        success: false,
        code: _extractCode(e),
        message: _extractErrorMessage(e),
        networkUnavailable: e.response == null,
      );
    } catch (e) {
      debugPrint('LIVENESS FRAME ERROR: $e');
      return const AttendanceLivenessFrameResult(
        success: false,
        message: 'Unable to analyze camera frame.',
      );
    }
  }

  Future<AttendanceResult> mobileCheckIn({
    required int eventId,
    required double latitude,
    required double longitude,
    required double locationAccuracy,
    required XFile centerFrame,
    required XFile turnedFrame,
    required String challengeNonce,
    required String sessionId,
  }) async {
    try {
      final formData = FormData.fromMap({
        'event_id': eventId,
        'challenge_nonce': challengeNonce,
        'session_id': sessionId,
        'latitude': latitude,
        'longitude': longitude,
        'location_accuracy': locationAccuracy,
        'center_frame': await MultipartFile.fromFile(
          centerFrame.path,
          filename: 'attendance-center.jpg',
        ),
        'turned_frame': await MultipartFile.fromFile(
          turnedFrame.path,
          filename: 'attendance-turn.jpg',
        ),
      });

      final response = await _api.dio.post(
        ApiEndpoints.attendanceMobileCheckIn,
        data: formData,
        options: Options(
          contentType: 'multipart/form-data',
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 120),
        ),
      );

      final map = _asMap(response.data);

      if (map == null) {
        return const AttendanceResult(
          success: false,
          message: 'Invalid attendance response.',
        );
      }

      return AttendanceResult.fromJson(map);
    } on DioException catch (e) {
      debugPrint(
        'CHECKIN DIO ERROR: ${e.response?.statusCode} - ${e.response?.data}',
      );
      return AttendanceResult(
        success: false,
        code: _extractCode(e),
        message: _extractErrorMessage(e),
        data: _asMap(_asMap(e.response?.data)?['data']),
        networkUnavailable: e.response == null,
      );
    } catch (e) {
      debugPrint('ATTENDANCE ERROR: $e');
      return const AttendanceResult(
        success: false,
        message: 'Unable to record attendance.',
      );
    }
  }

  Future<AttendanceResult> queueOfflineAttendance({
    required int eventId,
    required double latitude,
    required double longitude,
    required double locationAccuracy,
    required DateTime attendanceTime,
    required XFile centerFrame,
    required XFile turnedFrame,
    required String livenessDirection,
  }) async {
    try {
      final exists = await _offlineStorage.hasPendingForEvent(eventId);

      if (exists) {
        return const AttendanceResult(
          success: false,
          code: 'OFFLINE_ALREADY_PENDING',
          message: 'An offline attendance for this event is already waiting to sync.',
        );
      }

      final record = await _offlineStorage.queueAttendance(
        eventId: eventId,
        latitude: latitude,
        longitude: longitude,
        locationAccuracy: locationAccuracy,
        attendanceTime: attendanceTime,
        centerFrame: centerFrame,
        turnedFrame: turnedFrame,
        livenessDirection: livenessDirection,
      );

      return AttendanceResult(
        success: true,
        code: 'OFFLINE_ATTENDANCE_QUEUED',
        message: 'Attendance saved offline.',
        data: <String, dynamic>{
          'attendance_uuid': record.uuid,
          'attendance_time': record.attendanceTime,
          'liveness_direction': record.livenessDirection,
          'sync_status': 'pending',
        },
      );
    } catch (e) {
      debugPrint('QUEUE OFFLINE ERROR: $e');
      return const AttendanceResult(
        success: false,
        code: 'OFFLINE_SAVE_FAILED',
        message: 'Unable to save offline attendance.',
      );
    }
  }

  Future<AttendanceResult> syncOfflineAttendance(
    PendingAttendanceRecord record,
  ) async {
    if (!record.allFilesExist) {
      return const AttendanceResult(
        success: false,
        code: 'OFFLINE_FILES_MISSING',
        message: 'Offline biometric files are missing.',
      );
    }

    try {
      final formData = FormData.fromMap({
        'event_id': record.eventId,
        'attendance_uuid': record.uuid,
        'attendance_time': record.attendanceTime,
        'latitude': record.latitude,
        'longitude': record.longitude,
        'location_accuracy': record.locationAccuracy,
        'liveness_direction': record.livenessDirection,
        'center_frame': await MultipartFile.fromFile(
          record.centerFramePath,
          filename: 'offline-center.jpg',
        ),
        'turned_frame': await MultipartFile.fromFile(
          record.turnedFramePath,
          filename: 'offline-turn.jpg',
        ),
      });

      final response = await _api.dio.post(
        ApiEndpoints.attendanceSync,
        data: formData,
        options: Options(
          contentType: 'multipart/form-data',
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 120),
        ),
      );

      final map = _asMap(response.data);

      if (map == null) {
        return const AttendanceResult(
          success: false,
          message: 'Invalid offline sync response.',
        );
      }

      return AttendanceResult.fromJson(map);
    } on DioException catch (e) {
      debugPrint(
        'OFFLINE SYNC HTTP ERROR: ${e.response?.statusCode} - ${e.response?.data}',
      );
      return AttendanceResult(
        success: false,
        code: _extractCode(e),
        message: _extractErrorMessage(e),
        data: _asMap(_asMap(e.response?.data)?['data']),
        networkUnavailable: e.response == null,
      );
    } catch (e) {
      debugPrint('OFFLINE SYNC ERROR: $e');
      return const AttendanceResult(
        success: false,
        code: 'OFFLINE_SYNC_FAILED',
        message: 'Unable to synchronize offline attendance.',
      );
    }
  }

  Future<OfflineSyncResult> syncPendingAttendances() {
    final existing = _activeOfflineSync;

    if (existing != null) {
      debugPrint('OFFLINE SYNC: already running - joining existing sync.');
      return existing;
    }

    late final Future<OfflineSyncResult> future;
    future = Future<OfflineSyncResult>(_runPendingAttendanceSync);
    _activeOfflineSync = future;

    future.whenComplete(() {
      if (identical(_activeOfflineSync, future)) {
        _activeOfflineSync = null;
      }
    });

    return future;
  }

  Future<bool> syncPendingRecords() async {
    final result = await syncPendingAttendances();
    return result.synced > 0 || result.remaining == 0;
  }

  Future<OfflineSyncResult> _runPendingAttendanceSync() async {
    final records = await _offlineStorage.getPendingAttendances();

    if (records.isEmpty) {
      return const OfflineSyncResult(total: 0, synced: 0, remaining: 0);
    }

    var synced = 0;

    for (final record in records) {
      final result = await syncOfflineAttendance(record);

      if (result.success || result.code == 'ALREADY_CHECKED_IN') {
        await _offlineStorage.deletePending(record);
        synced++;
        continue;
      }

      if (result.networkUnavailable) {
        break;
      }
    }

    final remaining = await _offlineStorage.pendingCount();

    return OfflineSyncResult(
      total: records.length,
      synced: synced,
      remaining: remaining,
    );
  }

  Future<int> pendingOfflineCount() {
    return _offlineStorage.pendingCount();
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
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
    if (raw is Map) return raw['code']?.toString();
    return null;
  }

  String _extractErrorMessage(DioException exception) {
    final response = exception.response;

    if (response == null) {
      return 'Unable to connect to server. Please check your internet connection.';
    }

    final raw = response.data;

    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      final errors = map['errors'];

      if (errors is Map && errors.isNotEmpty) {
        final first = errors.values.first;
        if (first is List && first.isNotEmpty) {
          return first.first.toString();
        }
        return first.toString();
      }

      if (map['message'] != null) return map['message'].toString();
    }

    switch (response.statusCode) {
      case 401:
        return 'Your login session has expired.';
      case 403:
        return 'Your account cannot record attendance.';
      case 404:
        return 'Event or endpoint not found on server.';
      case 409:
        return 'Attendance has already been recorded.';
      case 422:
        return 'Attendance verification failed.';
      case 429:
        return 'Too many requests. Please wait.';
      default:
        return 'Server Error (${response.statusCode}): ${response.statusMessage ?? "Attendance verification failed."}';
    }
  }
}

class AttendanceResult {
  const AttendanceResult({
    required this.success,
    required this.message,
    this.code,
    this.data,
    this.networkUnavailable = false,
  });

  final bool success;
  final String message;
  final String? code;
  final Map<String, dynamic>? data;
  final bool networkUnavailable;

  factory AttendanceResult.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    return AttendanceResult(
      success: json['success'] == true,
      message: json['message']?.toString() ?? 'Unknown response.',
      code: json['code']?.toString(),
      data: rawData is Map ? Map<String, dynamic>.from(rawData) : null,
    );
  }
}

class AttendanceLivenessFrameResult {
  const AttendanceLivenessFrameResult({
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
    this.networkUnavailable = false,
  });

  final bool success;
  final String? code;
  final String message;
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
  final bool networkUnavailable;
}

class OfflineSyncResult {
  const OfflineSyncResult({
    required this.total,
    required this.synced,
    required this.remaining,
  });

  final int total;
  final int synced;
  final int remaining;
}