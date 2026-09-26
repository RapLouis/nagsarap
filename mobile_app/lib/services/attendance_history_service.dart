import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/api_endpoints.dart';
import '../models/attendance_history_item.dart';
import 'api_service.dart';

class AttendanceHistoryService {
  AttendanceHistoryService._();

  static final AttendanceHistoryService instance =
      AttendanceHistoryService._();

  final ApiService _api = ApiService.instance;

  Future<AttendanceHistoryResult> getHistory() async {
    try {
      debugPrint(
        'ATTENDANCE HISTORY REQUEST: '
        '${ApiEndpoints.attendanceHistory}',
      );

      final response = await _api.dio.get(
        ApiEndpoints.attendanceHistory,
        queryParameters: const <String, dynamic>{
          'limit': 100,
        },
      );

      debugPrint(
        'ATTENDANCE HISTORY RESPONSE: '
        '${response.statusCode}',
      );

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

      final records = <AttendanceHistoryItem>[];

      for (final item in rawData) {
        if (item is Map) {
          try {
            records.add(
              AttendanceHistoryItem.fromJson(
                Map<String, dynamic>.from(item),
              ),
            );
          } catch (error) {
            debugPrint(
              'ATTENDANCE HISTORY ITEM PARSE ERROR: $error',
            );
          }
        }
      }

      return AttendanceHistoryResult(
        success: true,
        message: json['message']?.toString() ??
            'Attendance history retrieved successfully.',
        records: records,
      );
    } on DioException catch (exception) {
      debugPrint(
        '================================================',
      );
      debugPrint(
        'ATTENDANCE HISTORY HTTP ERROR',
      );
      debugPrint(
        'Type: ${exception.type}',
      );
      debugPrint(
        'Status: ${exception.response?.statusCode}',
      );
      debugPrint(
        'URL: ${exception.requestOptions.uri}',
      );
      debugPrint(
        'Response: ${exception.response?.data}',
      );
      debugPrint(
        '================================================',
      );

      final response = exception.response;

      // ------------------------------------------------------------
      // NO RESPONSE
      // ------------------------------------------------------------

      if (response == null) {
        return const AttendanceHistoryResult(
          success: false,
          networkUnavailable: true,
          message:
              'Unable to connect to the server. '
              'Check your internet connection or API server.',
        );
      }

      // ------------------------------------------------------------
      // SERVER RESPONSE
      // ------------------------------------------------------------

      final statusCode = response.statusCode;

      final raw = response.data;

      String serverMessage =
          'Unable to load attendance history.';

      if (raw is Map) {
        final json = Map<String, dynamic>.from(raw);

        serverMessage = _serverMessage(
          json,
          fallback: serverMessage,
        );
      }

      switch (statusCode) {
        case 401:
          return const AttendanceHistoryResult(
            success: false,
            message:
                'Your login session has expired. '
                'Please log in again.',
          );

        case 403:
          return const AttendanceHistoryResult(
            success: false,
            message:
                'You are not authorized to view attendance history.',
          );

        case 404:
          return const AttendanceHistoryResult(
            success: false,
            message:
                'Attendance history endpoint was not found on the server.',
          );

        case 419:
          return const AttendanceHistoryResult(
            success: false,
            message:
                'Your session is no longer valid. '
                'Please log in again.',
          );

        case 422:
          return AttendanceHistoryResult(
            success: false,
            message: serverMessage,
          );

        case 429:
          return const AttendanceHistoryResult(
            success: false,
            message:
                'Too many requests. Please wait a moment and try again.',
          );

        case 500:
          return AttendanceHistoryResult(
            success: false,
            message:
                'Laravel encountered a server error. '
                '$serverMessage',
          );

        case 502:
        case 503:
        case 504:
          return const AttendanceHistoryResult(
            success: false,
            networkUnavailable: true,
            message:
                'The API server is temporarily unavailable.',
          );

        default:
          return AttendanceHistoryResult(
            success: false,
            message:
                '$serverMessage '
                'HTTP $statusCode.',
          );
      }
    } catch (exception) {
      debugPrint(
        'ATTENDANCE HISTORY ERROR: $exception',
      );

      return AttendanceHistoryResult(
        success: false,
        message:
            'Unable to load attendance history: '
            '$exception',
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

      if (text.isNotEmpty) {
        return text;
      }
    }

    final errors = json['errors'];

    if (errors is Map && errors.isNotEmpty) {
      final firstValue = errors.values.first;

      if (firstValue is List && firstValue.isNotEmpty) {
        return firstValue.first.toString();
      }

      return firstValue.toString();
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