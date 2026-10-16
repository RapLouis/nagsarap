import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/sanction_item.dart';
import 'api_service.dart';
import 'attendance_history_service.dart';
import 'auth_service.dart';
import 'event_service.dart';

class SanctionResult {
  final bool success;
  final String message;
  final List<SanctionItem> sanctions;

  const SanctionResult({
    required this.success,
    required this.message,
    required this.sanctions,
  });
}

class SanctionService {
  SanctionService._();

  static final SanctionService instance = SanctionService._();

  final ApiService _api = ApiService.instance;

  Future<SanctionResult> getSanctions() async {
    final sanctions = <SanctionItem>[];

    try {
      final response = await _api.dio.get('/api/v1/sanctions');
      final raw = response.data;

      if (raw is Map) {
        final map = Map<String, dynamic>.from(raw);
        final dynamic rawData = map['data'];
        if (rawData is List) {
          for (final item in rawData) {
            if (item is Map) {
              sanctions.add(
                SanctionItem.fromJson(Map<String, dynamic>.from(item)),
              );
            }
          }
        }
      }
    } catch (_) {
      // Fallback for offline or client-side generation
    }

    // --- CLIENT-SIDE AUTOMATIC MISSED EVENT SANCTIONS EVALUATION ---
    try {
      final eventsResult = await EventService.instance.getEvents();
      final historyResult = await AttendanceHistoryService.instance.getHistory();

      if (eventsResult.success && historyResult.success) {
        final events = eventsResult.events;
        final history = historyResult.records;
        final now = DateTime.now();
        final todayStart = DateTime(now.year, now.month, now.day);

        int syntheticId = 900000;

        for (final event in events) {
          final eventDate = event.date;
          if (eventDate == null) continue;

          final eventDayMidnight =
              DateTime(eventDate.year, eventDate.month, eventDate.day);

          // Evaluate past events prior to today (starting 12:00 AM)
          if (eventDayMidnight.isBefore(todayStart)) {
            final eventRecords = history
                .where((r) =>
                    r.eventId == event.id ||
                    r.eventName.trim().toLowerCase() ==
                        event.name.trim().toLowerCase())
                .toList();

            bool hasTimeIn = eventRecords.any((r) =>
                r.status.toLowerCase().contains('time_in') ||
                r.status.toLowerCase() == 'time-in');
            bool hasTimeOut = eventRecords.any((r) =>
                r.status.toLowerCase().contains('time_out') ||
                r.status.toLowerCase() == 'time-out');

            final evaluationDate =
                eventDayMidnight.add(const Duration(days: 1)); // 12:00 AM next day

            if (!hasTimeIn) {
              final exists = sanctions.any((s) =>
                  s.title.toLowerCase().contains(event.name.toLowerCase()) &&
                  s.title.toLowerCase().contains('time-in'));
              if (!exists) {
                sanctions.add(
                  SanctionItem(
                    id: syntheticId++,
                    title: '${event.name} - Time-In Missed',
                    reason: '',
                    status: 'pending',
                    issuedAt: evaluationDate,
                    resolvedAt: null,
                  ),
                );
              }
            }

            if (!hasTimeOut) {
              final exists = sanctions.any((s) =>
                  s.title.toLowerCase().contains(event.name.toLowerCase()) &&
                  s.title.toLowerCase().contains('time-out'));
              if (!exists) {
                sanctions.add(
                  SanctionItem(
                    id: syntheticId++,
                    title: '${event.name} - Time-Out Missed',
                    reason: '',
                    status: 'pending',
                    issuedAt: evaluationDate,
                    resolvedAt: null,
                  ),
                );
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('CLIENT-SIDE SANCTIONS EVALUATION ERROR: $e');
    }

    // Sort descending (newest/latest missed events on top)
    sanctions.sort((a, b) {
      final first = a.issuedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final second = b.issuedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return second.compareTo(first);
    });

    return SanctionResult(
      success: true,
      message: 'Sanctions loaded successfully.',
      sanctions: sanctions,
    );
  }

  String _errorMessage(DioException exception) {
    final response = exception.response;

    if (response == null) {
      return 'Unable to connect to Laravel.';
    }

    final raw = response.data;

    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      final message = map['message']?.toString();
      if (message != null && message.isNotEmpty) {
        return message;
      }
    }

    if (response.statusCode == 401) {
      return 'Your session has expired. Please log in again.';
    }

    return 'Unable to load sanctions.';
  }
}