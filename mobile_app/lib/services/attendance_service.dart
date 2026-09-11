import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/api_endpoints.dart';
import 'api_service.dart';
import 'offline_storage_service.dart';

class AttendanceService {
  AttendanceService._();

  static final AttendanceService instance = AttendanceService._();

  final ApiService _api = ApiService.instance;

  final OfflineStorageService _offlineStorage = OfflineStorageService.instance;

  // Must match Python final verification.
  static const double _centerLimit = 0.08;
  static const double _blinkRatio = 0.72;
  static const double _turnDelta = 0.06;
  static const double _smileRatio = 1.04;
  static const double _returnDelta = 0.06;

  // ===========================================================================
  // ANALYZE ONE FRAME
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
          sendTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 20),
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
        'location_accuracy': locationAccuracy,
        'center_frame': await MultipartFile.fromFile(
          centerFrame.path,
          filename: 'attendance-center.jpg',
        ),
        'blink_frame': await MultipartFile.fromFile(
          blinkFrame.path,
          filename: 'attendance-blink.jpg',
        ),
        'turned_frame': await MultipartFile.fromFile(
          turnedFrame.path,
          filename: 'attendance-turn.jpg',
        ),
        'smile_frame': await MultipartFile.fromFile(
          smileFrame.path,
          filename: 'attendance-smile.jpg',
        ),
        'returned_frame': await MultipartFile.fromFile(
          returnedFrame.path,
          filename: 'attendance-return.jpg',
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
  // STORE BURST OFFLINE
  // ===========================================================================

  Future<AttendanceResult> queueOfflineAttendance({
    required int eventId,
    required double latitude,
    required double longitude,
    required double locationAccuracy,
    required DateTime attendanceTime,
    required List<XFile> centerCandidates,
    required List<XFile> blinkCandidates,
    required List<XFile> turnedCandidates,
    required List<XFile> smileCandidates,
    required List<XFile> returnedCandidates,
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
        centerCandidates: centerCandidates,
        blinkCandidates: blinkCandidates,
        turnedCandidates: turnedCandidates,
        smileCandidates: smileCandidates,
        returnedCandidates: returnedCandidates,
      );

      return AttendanceResult(
        success: true,
        code: 'OFFLINE_ATTENDANCE_QUEUED',
        message: 'Attendance saved offline.',
        data: <String, dynamic>{
          'attendance_uuid': record.uuid,
          'attendance_time': record.attendanceTime,
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
  // ANALYZE ALL CANDIDATES
  // ===========================================================================

  Future<List<_AnalyzedCandidate>> _analyzeCandidates(
    List<String> paths,
    String step,
  ) async {
    final accepted = <_AnalyzedCandidate>[];

    for (final path in paths) {
      final result = await analyzeLivenessFrame(frame: XFile(path));

      if (result.networkUnavailable) {
        throw const _NetworkUnavailable();
      }

      if (!result.success ||
          !result.faceDetected ||
          result.yaw == null ||
          result.eyeOpenness == null ||
          result.mouthWidth == null) {
        debugPrint(
          'OFFLINE CANDIDATE REJECTED '
          '[$step] ${result.message}',
        );

        continue;
      }

      accepted.add(_AnalyzedCandidate(path: path, result: result));
    }

    return accepted;
  }

  Future<_SelectedFrames> _selectBestFrames(
    PendingAttendanceRecord record,
  ) async {
    // -------------------------------------------------------------------------
    // CENTER
    // -------------------------------------------------------------------------

    final centerResults = await _analyzeCandidates(
      record.centerCandidatePaths,
      'CENTER',
    );

    final validCenters = centerResults
        .where((candidate) => candidate.result.yaw!.abs() <= _centerLimit)
        .toList();

    validCenters.sort((a, b) {
      final yawOrder = a.result.yaw!.abs().compareTo(b.result.yaw!.abs());

      if (yawOrder != 0) {
        return yawOrder;
      }

      return b.quality.compareTo(a.quality);
    });

    if (validCenters.isEmpty) {
      throw const _SelectionFailed(
        'No good centered frame was found. Keep your whole face inside the guide and look directly at the camera.',
      );
    }

    final center = validCenters.first;

    final centerYaw = center.result.yaw!;

    final centerEye = center.result.eyeOpenness!;

    final centerMouth = center.result.mouthWidth!;

    // -------------------------------------------------------------------------
    // BLINK
    // -------------------------------------------------------------------------

    final blinkResults = await _analyzeCandidates(
      record.blinkCandidatePaths,
      'BLINK',
    );

    final validBlinks = blinkResults
        .where(
          (candidate) =>
              candidate.result.eyeOpenness! <= centerEye * _blinkRatio,
        )
        .toList();

    validBlinks.sort(
      (a, b) => a.result.eyeOpenness!.compareTo(b.result.eyeOpenness!),
    );

    if (validBlinks.isEmpty) {
      throw const _SelectionFailed(
        'No valid blink frame was found. Close BOTH eyes fully and keep them closed while the blink burst is captured.',
      );
    }

    // -------------------------------------------------------------------------
    // TURN
    // -------------------------------------------------------------------------

    final turnResults = await _analyzeCandidates(
      record.turnedCandidatePaths,
      'TURN',
    );

    final validTurns = turnResults
        .where(
          (candidate) =>
              (candidate.result.yaw! - centerYaw).abs() >= _turnDelta,
        )
        .toList();

    validTurns.sort(
      (a, b) => (b.result.yaw! - centerYaw).abs().compareTo(
        (a.result.yaw! - centerYaw).abs(),
      ),
    );

    if (validTurns.isEmpty) {
      throw const _SelectionFailed(
        'No valid head-turn frame was found. Turn clearly left or right and hold the pose.',
      );
    }

    // -------------------------------------------------------------------------
    // SMILE
    // -------------------------------------------------------------------------

    final smileResults = await _analyzeCandidates(
      record.smileCandidatePaths,
      'SMILE',
    );

    final validSmiles = smileResults
        .where(
          (candidate) =>
              candidate.result.mouthWidth! >= centerMouth * _smileRatio,
        )
        .toList();

    validSmiles.sort(
      (a, b) => b.result.mouthWidth!.compareTo(a.result.mouthWidth!),
    );

    if (validSmiles.isEmpty) {
      throw const _SelectionFailed(
        'No valid smile frame was found. Smile clearly and hold the expression.',
      );
    }

    // -------------------------------------------------------------------------
    // RETURN CENTER
    // -------------------------------------------------------------------------

    final returnResults = await _analyzeCandidates(
      record.returnedCandidatePaths,
      'RETURN CENTER',
    );

    final validReturns = returnResults.where((candidate) {
      final yaw = candidate.result.yaw!;

      return yaw.abs() <= _centerLimit &&
          (yaw - centerYaw).abs() <= _returnDelta;
    }).toList();

    validReturns.sort(
      (a, b) => (a.result.yaw! - centerYaw).abs().compareTo(
        (b.result.yaw! - centerYaw).abs(),
      ),
    );

    if (validReturns.isEmpty) {
      throw const _SelectionFailed(
        'No valid final centered frame was found. Return to the center and hold still.',
      );
    }

    return _SelectedFrames(
      centerPath: center.path,
      blinkPath: validBlinks.first.path,
      turnedPath: validTurns.first.path,
      smilePath: validSmiles.first.path,
      returnedPath: validReturns.first.path,
    );
  }

  // ===========================================================================
  // SYNC ONE RECORD
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
      debugPrint('Selecting best biometric frames...');

      final selected = await _selectBestFrames(record);

      debugPrint('OFFLINE BEST FRAMES SELECTED');

      final formData = FormData.fromMap({
        'event_id': record.eventId,
        'attendance_uuid': record.uuid,
        'attendance_time': record.attendanceTime,
        'latitude': record.latitude,
        'longitude': record.longitude,
        'location_accuracy': record.locationAccuracy,

        'center_frame': await MultipartFile.fromFile(
          selected.centerPath,
          filename: 'offline-center.jpg',
        ),

        'blink_frame': await MultipartFile.fromFile(
          selected.blinkPath,
          filename: 'offline-blink.jpg',
        ),

        'turned_frame': await MultipartFile.fromFile(
          selected.turnedPath,
          filename: 'offline-turn.jpg',
        ),

        'smile_frame': await MultipartFile.fromFile(
          selected.smilePath,
          filename: 'offline-smile.jpg',
        ),

        'returned_frame': await MultipartFile.fromFile(
          selected.returnedPath,
          filename: 'offline-return.jpg',
        ),
      });

      final response = await _api.dio.post(
        '/api/v1/attendance/sync',
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
    } on _NetworkUnavailable {
      return const AttendanceResult(
        success: false,
        code: 'NETWORK_UNAVAILABLE',
        message: 'Server is unavailable.',
        networkUnavailable: true,
      );
    } on _SelectionFailed catch (e) {
      return AttendanceResult(
        success: false,
        code: 'OFFLINE_LIVENESS_EVIDENCE_FAILED',
        message: e.message,
      );
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
  // SYNC ALL
  // ===========================================================================

  Future<OfflineSyncResult> syncPendingAttendances() async {
    final records = await _offlineStorage.getPendingAttendances();

    debugPrint('==========================================');
    debugPrint('OFFLINE SYNC START');
    debugPrint('Pending records: ${records.length}');
    debugPrint('==========================================');

    if (records.isEmpty) {
      return const OfflineSyncResult(total: 0, synced: 0, remaining: 0);
    }

    var synced = 0;

    for (final record in records) {
      final result = await syncOfflineAttendance(record);

      debugPrint('OFFLINE SYNC RESULT');
      debugPrint('Success: ${result.success}');
      debugPrint('Code: ${result.code}');
      debugPrint('Message: ${result.message}');
      debugPrint('Network unavailable: ${result.networkUnavailable}');

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

class _AnalyzedCandidate {
  const _AnalyzedCandidate({required this.path, required this.result});

  final String path;
  final AttendanceLivenessFrameResult result;

  double get quality {
    return ((result.detectionScore ?? 0) * 1000) + (result.blurScore ?? 0);
  }
}

class _SelectedFrames {
  const _SelectedFrames({
    required this.centerPath,
    required this.blinkPath,
    required this.turnedPath,
    required this.smilePath,
    required this.returnedPath,
  });

  final String centerPath;
  final String blinkPath;
  final String turnedPath;
  final String smilePath;
  final String returnedPath;
}

class _SelectionFailed implements Exception {
  const _SelectionFailed(this.message);

  final String message;
}

class _NetworkUnavailable implements Exception {
  const _NetworkUnavailable();
}
