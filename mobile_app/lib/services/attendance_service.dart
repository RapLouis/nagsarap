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

  // Prevents Home load, app resume, pull-to-refresh, or another caller
  // from synchronizing the same offline biometric files simultaneously.
  Future<OfflineSyncResult>? _activeOfflineSync;

  // Local frame selection only. Laravel/Python remains authoritative.
  // These values match the tolerant online challenge so an offline record
  // is not rejected merely because one candidate is slightly off-center.
  // ===========================================================================
  // SERVER LIVENESS CHALLENGE
  // ===========================================================================

  Future<LivenessChallengeResult> requestLivenessChallenge({
    required int eventId,
  }) async {
    final sessionId = const Uuid().v4();

    try {
      final response = await _api.dio.post(
        ApiEndpoints.attendanceLivenessChallenge,
        data: {'event_id': eventId, 'session_id': sessionId},
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
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
        final challengeDirection = direction!;

        return LivenessChallengeResult(
          success: true,
          networkUnavailable: false,
          message: 'Liveness challenge issued.',
          challenge: LivenessChallenge(
            nonce: nonce,
            direction: challengeDirection,
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
      debugPrint('ATTENDANCE CHALLENGE ERROR: $e');
      return const LivenessChallengeResult(
        success: false,
        networkUnavailable: false,
        message: 'Unable to start the liveness challenge.',
      );
    }
  }

  // ===========================================================================
  // ANALYZE ONE ATTENDANCE LIVENESS FRAME
  // ===========================================================================

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

  // ===========================================================================
  // NORMAL ONLINE ATTENDANCE
  // ===========================================================================

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

  // ===========================================================================
  // STORE OFFLINE ATTENDANCE
  //
  // Offline capture uses exactly the same two evidence stages as online:
  // CENTER -> TURN LEFT/RIGHT -> COMPLETE.
  // No blink, smile, or return-to-center evidence is stored.
  // ===========================================================================

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
          message:
              'An offline attendance for this event is already waiting to sync.',
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

  // ===========================================================================
  // SYNC ONE OFFLINE RECORD
  //
  // The server performs the authoritative liveness verification when the
  // phone reconnects. Only CENTER + TURN are uploaded.
  // ===========================================================================

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
        'OFFLINE SYNC HTTP ERROR: '
        '${e.response?.statusCode} '
        '${e.response?.data}',
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

  // ===========================================================================
  // SYNC ALL PENDING ATTENDANCE
  //
  // SINGLE-FLIGHT GUARANTEE
  //
  // Home loading, app-resume, pull-to-refresh, and manual synchronization can
  // all request synchronization.
  //
  // Only one real synchronization operation may access the offline biometric
  // files at one time.
  //
  // Other callers join the same Future instead of starting a second processor.
  // ===========================================================================

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

  // ===========================================================================
  // ACTUAL OFFLINE QUEUE PROCESSOR
  // ===========================================================================

  Future<OfflineSyncResult> _runPendingAttendanceSync() async {
    final records = await _offlineStorage.getPendingAttendances();

    debugPrint('==========================================');

    debugPrint('OFFLINE SYNC START');

    debugPrint('Pending records: ${records.length}');

    debugPrint('==========================================');

    if (records.isEmpty) {
      debugPrint('OFFLINE SYNC: nothing to synchronize.');

      return const OfflineSyncResult(total: 0, synced: 0, remaining: 0);
    }

    var synced = 0;

    for (final record in records) {
      debugPrint('OFFLINE SYNC: processing ${record.uuid}');

      final result = await syncOfflineAttendance(record);

      debugPrint('==========================================');

      debugPrint('OFFLINE SYNC RESULT');

      debugPrint('Success: ${result.success}');

      debugPrint('Code: ${result.code}');

      debugPrint('Message: ${result.message}');

      debugPrint('Network unavailable: ${result.networkUnavailable}');

      debugPrint('==========================================');

      // -----------------------------------------------------------------------
      // SUCCESS
      //
      // Laravel accepted and stored this attendance.
      //
      // The server is now authoritative, so remove its local pending files.
      // -----------------------------------------------------------------------

      if (result.success) {
        await _offlineStorage.deletePending(record);

        synced++;

        debugPrint(
          'OFFLINE SYNC: '
          '${record.uuid} synchronized and removed locally.',
        );

        continue;
      }

      // -----------------------------------------------------------------------
      // DUPLICATE / IDEMPOTENCY
      //
      // Laravel already owns an attendance for this student/event.
      //
      // There is no reason to retry this local queue forever.
      // -----------------------------------------------------------------------

      if (result.code == 'ALREADY_CHECKED_IN') {
        await _offlineStorage.deletePending(record);

        synced++;

        debugPrint(
          'OFFLINE SYNC: '
          '${record.uuid} already exists on server. '
          'Local copy removed.',
        );

        continue;
      }

      // -----------------------------------------------------------------------
      // NETWORK FAILURE
      //
      // Stop and keep all remaining evidence locally.
      // -----------------------------------------------------------------------

      if (result.networkUnavailable) {
        debugPrint(
          'OFFLINE SYNC: network unavailable. '
          'Keeping pending attendance locally.',
        );

        break;
      }

      // -----------------------------------------------------------------------
      // VERIFICATION OR SERVER REJECTION
      //
      // Do not silently destroy biometric evidence when verification fails.
      // -----------------------------------------------------------------------

      debugPrint(
        'OFFLINE SYNC: '
        '${record.uuid} was not accepted. '
        'Keeping it locally.',
      );
    }

    final remaining = await _offlineStorage.pendingCount();

    debugPrint('==========================================');

    debugPrint('OFFLINE SYNC COMPLETE');

    debugPrint('Total: ${records.length}');

    debugPrint('Synced: $synced');

    debugPrint('Remaining: $remaining');

    debugPrint('==========================================');

    return OfflineSyncResult(
      total: records.length,
      synced: synced,
      remaining: remaining,
    );
  }

  // ===========================================================================
  // PENDING COUNT
  // ===========================================================================

  Future<int> pendingOfflineCount() {
    return _offlineStorage.pendingCount();
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
      return 'Unable to connect to the server.';
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

      if (map['message'] != null) {
        return map['message'].toString();
      }
    }

    switch (response.statusCode) {
      case 401:
        return 'Your login session has expired.';

      case 403:
        return 'Your account cannot record attendance.';

      case 404:
        return 'Event not found.';

      case 409:
        return 'Attendance has already been recorded.';

      case 422:
        return 'Attendance verification failed.';

      case 429:
        return 'Too many requests. Please wait.';

      default:
        return 'Attendance verification failed.';
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

// =============================================================================
// LIVENESS FRAME RESULT
// =============================================================================

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

// =============================================================================
// OFFLINE SYNC RESULT
// =============================================================================

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

