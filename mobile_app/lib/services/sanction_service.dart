import 'package:flutter/foundation.dart';

import '../models/attendance_history_item.dart';
import '../models/event_item.dart';
import '../models/sanction_item.dart';
import 'api_service.dart';
import 'attendance_history_service.dart';
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

    // Load existing sanctions from Laravel.
    try {
      final response = await _api.dio.get<dynamic>('/api/v1/sanctions');
      final raw = response.data;

      if (raw is Map) {
        final map = Map<String, dynamic>.from(raw);
        final rawData = map['data'];

        if (rawData is List) {
          for (final item in rawData) {
            if (item is Map) {
              sanctions.add(
                SanctionItem.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              );
            }
          }
        }
      }
    } catch (error) {
      debugPrint('SERVER SANCTIONS ERROR: $error');
    }

    // Independently evaluate missed Time-In and Time-Out.
    try {
      final eventsResult = await EventService.instance.getEvents();
      final historyResult =
          await AttendanceHistoryService.instance.getHistory();

      if (eventsResult.success && historyResult.success) {
        final now = DateTime.now();
        var syntheticId = 900000;

        for (final event in eventsResult.events) {
          final eventDate = event.date;

          if (eventDate == null) continue;

          final eventDay = DateTime(
            eventDate.year,
            eventDate.month,
            eventDate.day,
          );

          // Match attendance records to this event.
          final eventRecords = historyResult.records.where((record) {
            if (event.id != null && record.eventId != null) {
              return event.id == record.eventId;
            }

            return record.eventName.trim().toLowerCase() ==
                event.name.trim().toLowerCase();
          }).toList();

          final hasTimeIn = eventRecords.any(
            (record) => _isSuccessfulRecordFor(
              record,
              'time_in',
            ),
          );

          final hasTimeOut = eventRecords.any(
            (record) => _isSuccessfulRecordFor(
              record,
              'time_out',
            ),
          );

          final timeInDeadline = _getPeriodDeadline(
            event: event,
            eventDate: eventDay,
            isTimeIn: true,
          );

          final timeOutDeadline = _getPeriodDeadline(
            event: event,
            eventDate: eventDay,
            isTimeIn: false,
          );

          // TIME-IN MISSED:
          // Only generate after the Time-In period closes.
          if (!hasTimeIn && now.isAfter(timeInDeadline)) {
            final exists = _alreadyHasSanction(
              sanctions,
              eventName: event.name,
              eventDate: eventDay,
              period: 'time-in',
              eventId: event.id,
            );

            if (!exists) {
              sanctions.add(
                SanctionItem(
                  id: syntheticId++,
                  title: '${event.name} - Time-In Missed',
                  reason:
                      'No Time-In attendance was recorded before the Time-In period closed.',
                  status: 'pending',
                  issuedAt: timeInDeadline,
                  resolvedAt: null,
                  eventDate: eventDay,
                  eventId: event.id,
                ),
              );
            }
          }

          // TIME-OUT MISSED:
          // Only generate after the Time-Out period closes.
          if (!hasTimeOut && now.isAfter(timeOutDeadline)) {
            final exists = _alreadyHasSanction(
              sanctions,
              eventName: event.name,
              eventDate: eventDay,
              period: 'time-out',
              eventId: event.id,
            );

            if (!exists) {
              sanctions.add(
                SanctionItem(
                  id: syntheticId++,
                  title: '${event.name} - Time-Out Missed',
                  reason:
                      'No Time-Out attendance was recorded before the Time-Out period closed.',
                  status: 'pending',
                  issuedAt: timeOutDeadline,
                  resolvedAt: null,
                  eventDate: eventDay,
                  eventId: event.id,
                ),
              );
            }
          }
        }
      }
    } catch (error) {
      debugPrint('SANCTION EVALUATION ERROR: $error');
    }

    sanctions.sort((a, b) {
      final first = a.eventDate ??
          a.issuedAt ??
          DateTime.fromMillisecondsSinceEpoch(0);

      final second = b.eventDate ??
          b.issuedAt ??
          DateTime.fromMillisecondsSinceEpoch(0);

      return second.compareTo(first);
    });

    return SanctionResult(
      success: true,
      message: 'Sanctions loaded successfully.',
      sanctions: sanctions,
    );
  }

  // Check whether an actual successful attendance exists
  // for the requested attendance period.
  bool _isSuccessfulRecordFor(
    AttendanceHistoryItem record,
    String expectedPeriod,
  ) {
    final raw = record.raw;

    final rawType = _firstString(raw, const [
      'session_type',
      'checkpoint_key',
      'attendance_type',
      'type',
      'session',
    ]);

    var normalizedType = _normalizePeriod(rawType);

    // Some API responses may use another field for the session type.
    normalizedType ??= _normalizePeriod(
      _firstString(raw, const [
        'status',
        'attendance_status',
      ]),
    );

    if (normalizedType != expectedPeriod) {
      return false;
    }

    final status = record.status.trim().toLowerCase();

    const rejectedStates = [
      'missed',
      'absent',
      'rejected',
      'failed',
      'cancelled',
      'canceled',
      'denied',
      'invalid',
    ];

    if (rejectedStates.any(status.contains)) {
      return false;
    }

    return true;
  }

  String? _normalizePeriod(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final text = value
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');

    if ([
          'time_in',
          'timein',
          'in',
          'check_in',
          'checkin',
        ].contains(text) ||
        text.endsWith('_time_in')) {
      return 'time_in';
    }

    if ([
          'time_out',
          'timeout',
          'out',
          'check_out',
          'checkout',
        ].contains(text) ||
        text.endsWith('_time_out')) {
      return 'time_out';
    }

    return null;
  }

  // Prevent duplicate sanctions for the same event,
  // event date, and missed attendance period.
  bool _alreadyHasSanction(
    List<SanctionItem> sanctions, {
    required String eventName,
    required DateTime eventDate,
    required String period,
    required int? eventId,
  }) {
    return sanctions.any((sanction) {
      final title = sanction.title.toLowerCase();

      if (!title.contains(period)) {
        return false;
      }

      if (sanction.eventId != null && eventId != null) {
        if (sanction.eventId != eventId) {
          return false;
        }
      } else if (!title.contains(eventName.toLowerCase())) {
        return false;
      }

      final existingDate = sanction.eventDate;

      if (existingDate == null) {
        // Legacy sanctions without event dates are treated
        // as existing to avoid creating duplicates.
        return true;
      }

      return existingDate.year == eventDate.year &&
          existingDate.month == eventDate.month &&
          existingDate.day == eventDate.day;
    });
  }

  DateTime _getPeriodDeadline({
    required EventItem event,
    required DateTime eventDate,
    required bool isTimeIn,
  }) {
    final raw = event.raw;

    final explicitKeys = isTimeIn
        ? const [
            'time_in_end',
            'time_in_end_time',
            'time_in_until',
            'time_in_to',
            'check_in_end',
            'checkin_end',
          ]
        : const [
            'time_out_end',
            'time_out_end_time',
            'time_out_until',
            'time_out_to',
            'check_out_end',
            'checkout_end',
          ];

    final explicitValue = _firstString(raw, explicitKeys);
    final explicitTime = _parseTime(explicitValue);

    if (explicitTime != null) {
      return DateTime(
        eventDate.year,
        eventDate.month,
        eventDate.day,
        explicitTime.hour,
        explicitTime.minute,
        explicitTime.second,
      );
    }

    // Read the end of the configured attendance window.
    final rangeKeys = isTimeIn
        ? const [
            'time_in',
            'time_in_window',
            'check_in_window',
          ]
        : const [
            'time_out',
            'time_out_window',
            'check_out_window',
          ];

    for (final key in rangeKeys) {
      final value = _firstString(raw, [key]);
      final rangeEnd = _parseRangeEnd(value);

      if (rangeEnd != null) {
        return DateTime(
          eventDate.year,
          eventDate.month,
          eventDate.day,
          rangeEnd.hour,
          rangeEnd.minute,
          rangeEnd.second,
        );
      }
    }

    // Time-Out fallback.
    if (!isTimeIn) {
      final fallback = _parseTime(event.endTime);

      if (fallback != null) {
        return DateTime(
          eventDate.year,
          eventDate.month,
          eventDate.day,
          fallback.hour,
          fallback.minute,
          fallback.second,
        );
      }
    }

    // If the actual deadline is not provided by the API,
    // wait until the event date has fully ended.
    return eventDate.add(const Duration(days: 1));
  }

  String? _firstString(
    Map<String, dynamic> map,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = map[key];

      if (value == null) continue;

      final text = value.toString().trim();

      if (text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }

    return null;
  }

  DateTime? _parseRangeEnd(String? value) {
    if (value == null) return null;

    final separator = RegExp(
      r'\s*(?:-|–|—|to)\s*',
      caseSensitive: false,
    );

    final parts = value.split(separator);

    if (parts.length < 2) return null;

    return _parseTime(parts.last);
  }

  DateTime? _parseTime(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final text = value.trim().toUpperCase();

    final match = RegExp(
      r'(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(AM|PM)?',
    ).firstMatch(text);

    if (match == null) return null;

    var hour = int.tryParse(match.group(1)!) ?? -1;
    final minute = int.tryParse(match.group(2)!) ?? -1;
    final second = int.tryParse(match.group(3) ?? '0') ?? 0;
    final period = match.group(4);

    if (hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59 ||
        second > 59) {
      return null;
    }

    if (period == 'PM' && hour < 12) {
      hour += 12;
    }

    if (period == 'AM' && hour == 12) {
      hour = 0;
    }

    return DateTime(
      2000,
      1,
      1,
      hour,
      minute,
      second,
    );
  }
}