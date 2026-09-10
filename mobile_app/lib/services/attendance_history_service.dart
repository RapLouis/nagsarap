import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/attendance_history_item.dart';
import 'api_service.dart';

class AttendanceHistoryResult {
  final bool success;
  final String message;
  final List<AttendanceHistoryItem> records;

  const AttendanceHistoryResult({
    required this.success,
    required this.message,
    required this.records,
  });
}

class AttendanceHistoryService {
  AttendanceHistoryService._();

  static final AttendanceHistoryService instance = AttendanceHistoryService._();

  final ApiService _api = ApiService.instance;

  Future<AttendanceHistoryResult> getHistory() async {
    try {
      final response = await _api.dio.get('/api/v1/attendance/history');

      final records = _extractRecords(response.data);

      return AttendanceHistoryResult(
        success: true,
        message: 'Attendance history loaded.',
        records: records,
      );
    } on DioException catch (e) {
      return AttendanceHistoryResult(
        success: false,
        message: _extractErrorMessage(e),
        records: const [],
      );
    } catch (e) {
      debugPrint('ATTENDANCE HISTORY ERROR: $e');

      return const AttendanceHistoryResult(
        success: false,
        message: 'Unable to load attendance history.',
        records: [],
      );
    }
  }

  List<AttendanceHistoryItem> _extractRecords(dynamic raw) {
    final List<dynamic> rawRecords = _findList(raw);

    final records = <AttendanceHistoryItem>[];

    for (final item in rawRecords) {
      if (item is Map<String, dynamic>) {
        records.add(AttendanceHistoryItem.fromJson(item));
      } else if (item is Map) {
        records.add(
          AttendanceHistoryItem.fromJson(Map<String, dynamic>.from(item)),
        );
      }
    }

    records.sort((a, b) {
      final first = a.attendanceTime;

      final second = b.attendanceTime;

      if (first == null && second == null) {
        return 0;
      }

      if (first == null) {
        return 1;
      }

      if (second == null) {
        return -1;
      }

      return second.compareTo(first);
    });

    return records;
  }

  List<dynamic> _findList(dynamic raw) {
    if (raw is List) {
      return raw;
    }

    if (raw is! Map) {
      return const [];
    }

    final map = Map<String, dynamic>.from(raw);

    final candidates = [
      map['data'],
      map['attendances'],
      map['attendance'],
      map['history'],
      map['records'],
      map['results'],
    ];

    for (final candidate in candidates) {
      if (candidate is List) {
        return candidate;
      }

      if (candidate is Map) {
        final nested = Map<String, dynamic>.from(candidate);

        final nestedCandidates = [
          nested['data'],
          nested['attendances'],
          nested['history'],
          nested['records'],
        ];

        for (final nestedCandidate in nestedCandidates) {
          if (nestedCandidate is List) {
            return nestedCandidate;
          }
        }
      }
    }

    return const [];
  }

  String _extractErrorMessage(DioException exception) {
    final response = exception.response;

    if (response == null) {
      return 'Unable to connect to Laravel. Make sure the server is running.';
    }

    final raw = response.data;

    if (raw is Map) {
      final data = Map<String, dynamic>.from(raw);

      if (data['message'] != null) {
        return data['message'].toString();
      }

      if (data['detail'] != null) {
        return data['detail'].toString();
      }

      if (data['errors'] is Map) {
        final errors = Map<String, dynamic>.from(data['errors']);

        if (errors.isNotEmpty) {
          final value = errors.values.first;

          if (value is List && value.isNotEmpty) {
            return value.first.toString();
          }

          return value.toString();
        }
      }
    }

    if (response.statusCode == 401) {
      return 'Your session has expired. Please log in again.';
    }

    return 'Unable to load attendance history.';
  }
}
