import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/api_endpoints.dart';
import '../models/attendance_history_item.dart';
import 'api_service.dart';
import 'offline_storage_service.dart';

class AttendanceHistoryService {
  AttendanceHistoryService._();

  static final AttendanceHistoryService instance =
      AttendanceHistoryService._();

  final ApiService _api = ApiService.instance;
  final OfflineStorageService _offlineStorage = OfflineStorageService.instance;

  Future<AttendanceHistoryResult> getHistory() async {
    try {
      debugPrint(
        'ATTENDANCE HISTORY REQUEST: ${ApiEndpoints.attendanceHistory}',
      );

      final response = await _api.dio.get(
        ApiEndpoints.attendanceHistory,
        queryParameters: const <String, dynamic>{'limit': 100},
      );

      debugPrint('ATTENDANCE HISTORY RESPONSE: ${response.statusCode}');

      final raw = response.data;

      if (raw is! Map) {
        return const AttendanceHistoryResult(
          success: false,
          message: 'The server returned an invalid attendance history response.',
        );
      }

      final json = Map<String, dynamic>.from(raw);

      if (json['success'] != true) {
        return AttendanceHistoryResult(
          success: false,
          message: _serverMessage(
            json,
            fallback: 'Unable to load attendance history.',
          ),
        );
      }

      final rawData = json['data'];

      if (rawData is! List) {
        return const AttendanceHistoryResult(
          success: false,
          message: 'The server returned invalid attendance history data.',
        );
      }

      final historyMaps = <Map<String, dynamic>>[];
      final records = <AttendanceHistoryItem>[];

      for (final item in rawData) {
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          historyMaps.add(map);
          try {
            records.add(AttendanceHistoryItem.fromJson(map));
          } catch (error) {
            debugPrint('ATTENDANCE HISTORY ITEM PARSE ERROR: $error');
          }
        }
      }

      await _offlineStorage.cacheHistory(historyMaps);

      return AttendanceHistoryResult(
        success: true,
        message: json['message']?.toString() ??
            'Attendance history retrieved successfully.',
        records: records,
      );
    } on DioException catch (exception) {
      debugPrint('ATTENDANCE HISTORY HTTP ERROR: ${exception.response?.statusCode}');

      if (exception.response == null) {
        return _loadOfflineHistory();
      }

      final response = exception.response;
      final statusCode = response?.statusCode;

      return AttendanceHistoryResult(
        success: false,
        message: 'Unable to load attendance history. HTTP $statusCode.',
      );
    } catch (exception) {
      debugPrint('ATTENDANCE HISTORY ERROR: $exception');
      return _loadOfflineHistory();
    }
  }

  Future<AttendanceHistoryResult> _loadOfflineHistory() async {
    try {
      final cachedMaps = await _offlineStorage.loadCachedHistory();
      final pendingRecords = await _offlineStorage.getPendingAttendances();

      final combinedMaps = <Map<String, dynamic>>[];

      for (final pending in pendingRecords) {
        combinedMaps.add({
          'event_id': pending.eventId,
          'session_type': pending.sessionType,
          'status': 'pending (offline)',
          'attendance_time': pending.attendanceTime,
          'logged_at': pending.attendanceTime,
          'confidence_score': 1.0,
          'check_in_method': 'Offline Local',
        });
      }

      combinedMaps.addAll(cachedMaps);

      final records = <AttendanceHistoryItem>[];
      for (final map in combinedMaps) {
        try {
          records.add(AttendanceHistoryItem.fromJson(map));
        } catch (_) {}
      }

      return AttendanceHistoryResult(
        success: true,
        message: 'Offline mode: showing saved attendance records.',
        records: records,
        networkUnavailable: true,
      );
    } catch (e) {
      return AttendanceHistoryResult(
        success: false,
        networkUnavailable: true,
        message: 'Unable to load offline attendance history.',
      );
    }
  }

  String _serverMessage(
    Map<String, dynamic> json, {
    required String fallback,
  }) {
    final message = json['message'];
    if (message != null) {
      final text = message.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return fallback;
  }
}

class AttendanceHistoryResult {
  const AttendanceHistoryResult({
    required this.success,
    required this.message,
    this.records = const <AttendanceHistoryItem>[],
    this.networkUnavailable = false,
  });

  final bool success;
  final String message;
  final List<AttendanceHistoryItem> records;
  final bool networkUnavailable;
}