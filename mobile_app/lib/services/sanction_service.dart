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

class _ExpectedCheckpoint {
  final DateTime eventDay;
  final int? slotIndex;
  final String checkpointKey;
  final String baseType; // 'time_in' or 'time_out'
  final String label;
  final DateTime deadline;

  const _ExpectedCheckpoint({
    required this.eventDay,
    required this.slotIndex,
    required this.checkpointKey,
    required this.baseType,
    required this.label,
    required this.deadline,
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

    // Independently evaluate missed checkpoints (supports both 2-checkpoint and 4-checkpoint events).
    try {
      final eventsResult = await EventService.instance.getEvents();
      final historyResult =
          await AttendanceHistoryService.instance.getHistory();

      if (eventsResult.success && historyResult.success) {
        final now = DateTime.now();
        var syntheticId = 900000;

        for (final event in eventsResult.events) {
          final checkpoints = _extractEventCheckpoints(event);
          if (checkpoints.isEmpty) continue;

          // Match attendance records to this event.
          final eventRecords = historyResult.records.where((record) {
            if (event.id != null && record.eventId != null) {
              return event.id == record.eventId;
            }

            return record.eventName.trim().toLowerCase() ==
                event.name.trim().toLowerCase();
          }).toList();

          for (final cp in checkpoints) {
            if (!now.isAfter(cp.deadline)) continue;

            final hasCheckpoint = eventRecords.any(
              (record) => _isSuccessfulRecordForCheckpoint(record, cp),
            );

            if (!hasCheckpoint) {
              final exists = _alreadyHasSanction(
                sanctions,
                eventName: event.name,
                eventDate: cp.eventDay,
                checkpoint: cp,
                eventId: event.id,
              );

              if (!exists) {
                sanctions.add(
                  SanctionItem(
                    id: syntheticId++,
                    title: '${event.name} - ${cp.label} Missed',
                    reason:
                        'No ${cp.label} attendance was recorded before the ${cp.label} period closed.',
                    status: 'pending',
                    issuedAt: cp.deadline,
                    resolvedAt: null,
                    eventDate: cp.eventDay,
                    eventId: event.id,
                  ),
                );
              }
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

  List<_ExpectedCheckpoint> _extractEventCheckpoints(EventItem event) {
    final raw = event.raw;
    final results = <_ExpectedCheckpoint>[];

    // 1. Check multi-day / multi-slot structure (`days[].slots[]`).
    final rawDays = raw['days'];
    if (rawDays is List && rawDays.isNotEmpty) {
      for (final dayEntry in rawDays) {
        if (dayEntry is! Map) continue;
        final dayMap = Map<String, dynamic>.from(dayEntry);

        DateTime? parsedDay;
        final rawDayDate = _firstString(dayMap, const ['date', 'event_date']);
        if (rawDayDate != null) {
          final dt = DateTime.tryParse(rawDayDate);
          if (dt != null) {
            parsedDay = DateTime(dt.year, dt.month, dt.day);
          }
        }
        parsedDay ??= event.date != null
            ? DateTime(event.date!.year, event.date!.month, event.date!.day)
            : null;
        if (parsedDay == null) continue;

        final rawSlots = dayMap['slots'];
        if (rawSlots is List && rawSlots.isNotEmpty) {
          for (int i = 0; i < rawSlots.length; i++) {
            final slotEntry = rawSlots[i];
            if (slotEntry is! Map) continue;
            final slotMap = Map<String, dynamic>.from(slotEntry);

            final slotIndex =
                int.tryParse(slotMap['slot_index']?.toString() ?? '') ?? i;
            final periodRaw =
                _firstString(slotMap, const ['period', 'session', 'name'])
                    ?.toLowerCase();

            final String prefixKey;
            final String prefixLabel;
            if (periodRaw == 'morning' || slotIndex == 0) {
              prefixKey = 'morning';
              prefixLabel = 'Morning';
            } else if (periodRaw == 'afternoon' || slotIndex == 1) {
              prefixKey = 'afternoon';
              prefixLabel = 'Afternoon';
            } else {
              prefixKey = 'slot_$slotIndex';
              prefixLabel = 'Session ${slotIndex + 1}';
            }

            final inDeadline = _getSlotDeadline(
              slotMap: slotMap,
              dayMap: dayMap,
              event: event,
              eventDate: parsedDay,
              isTimeIn: true,
            );
            final outDeadline = _getSlotDeadline(
              slotMap: slotMap,
              dayMap: dayMap,
              event: event,
              eventDate: parsedDay,
              isTimeIn: false,
            );

            results.add(
              _ExpectedCheckpoint(
                eventDay: parsedDay,
                slotIndex: slotIndex,
                checkpointKey: '${prefixKey}_time_in',
                baseType: 'time_in',
                label: '$prefixLabel Time-In',
                deadline: inDeadline,
              ),
            );
            results.add(
              _ExpectedCheckpoint(
                eventDay: parsedDay,
                slotIndex: slotIndex,
                checkpointKey: '${prefixKey}_time_out',
                baseType: 'time_out',
                label: '$prefixLabel Time-Out',
                deadline: outDeadline,
              ),
            );
          }
        }
      }

      if (results.isNotEmpty) return results;
    }

    final eventDate = event.date;
    if (eventDate == null) return results;

    final eventDay = DateTime(eventDate.year, eventDate.month, eventDate.day);

    // 2. Check top-level 4-checkpoint keys (`morning_time_in_*`, `afternoon_time_in_*`).
    final hasTopLevelMorning = _firstString(raw, const [
          'morning_time_in_start',
          'morning_time_in_end',
          'morning_time_in',
          'morning_time_out_start',
          'morning_time_out_end',
          'morning_time_out',
        ]) !=
        null;
    final hasTopLevelAfternoon = _firstString(raw, const [
          'afternoon_time_in_start',
          'afternoon_time_in_end',
          'afternoon_time_in',
          'afternoon_time_out_start',
          'afternoon_time_out_end',
          'afternoon_time_out',
        ]) !=
        null;

    if (hasTopLevelMorning || hasTopLevelAfternoon) {
      if (hasTopLevelMorning) {
        results.add(
          _ExpectedCheckpoint(
            eventDay: eventDay,
            slotIndex: 0,
            checkpointKey: 'morning_time_in',
            baseType: 'time_in',
            label: 'Morning Time-In',
            deadline: _getPrefixedPeriodDeadline(
              raw: raw,
              event: event,
              eventDate: eventDay,
              prefix: 'morning',
              isTimeIn: true,
            ),
          ),
        );
        results.add(
          _ExpectedCheckpoint(
            eventDay: eventDay,
            slotIndex: 0,
            checkpointKey: 'morning_time_out',
            baseType: 'time_out',
            label: 'Morning Time-Out',
            deadline: _getPrefixedPeriodDeadline(
              raw: raw,
              event: event,
              eventDate: eventDay,
              prefix: 'morning',
              isTimeIn: false,
            ),
          ),
        );
      }

      if (hasTopLevelAfternoon) {
        results.add(
          _ExpectedCheckpoint(
            eventDay: eventDay,
            slotIndex: 1,
            checkpointKey: 'afternoon_time_in',
            baseType: 'time_in',
            label: 'Afternoon Time-In',
            deadline: _getPrefixedPeriodDeadline(
              raw: raw,
              event: event,
              eventDate: eventDay,
              prefix: 'afternoon',
              isTimeIn: true,
            ),
          ),
        );
        results.add(
          _ExpectedCheckpoint(
            eventDay: eventDay,
            slotIndex: 1,
            checkpointKey: 'afternoon_time_out',
            baseType: 'time_out',
            label: 'Afternoon Time-Out',
            deadline: _getPrefixedPeriodDeadline(
              raw: raw,
              event: event,
              eventDate: eventDay,
              prefix: 'afternoon',
              isTimeIn: false,
            ),
          ),
        );
      }

      return results;
    }

    // 3. Fallback: standard 2-checkpoint event (Time-In & Time-Out).
    results.add(
      _ExpectedCheckpoint(
        eventDay: eventDay,
        slotIndex: null,
        checkpointKey: 'time_in',
        baseType: 'time_in',
        label: 'Time-In',
        deadline: _getPeriodDeadline(
          event: event,
          eventDate: eventDay,
          isTimeIn: true,
        ),
      ),
    );
    results.add(
      _ExpectedCheckpoint(
        eventDay: eventDay,
        slotIndex: null,
        checkpointKey: 'time_out',
        baseType: 'time_out',
        label: 'Time-Out',
        deadline: _getPeriodDeadline(
          event: event,
          eventDate: eventDay,
          isTimeIn: false,
        ),
      ),
    );

    return results;
  }

  bool _isSuccessfulRecordForCheckpoint(
    AttendanceHistoryItem record,
    _ExpectedCheckpoint checkpoint,
  ) {
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

    final raw = record.raw;

    // Match record date if multi-day and record carries an explicit date.
    final rawRecordDate = _firstString(raw, const [
      'attendance_date',
      'event_date',
      'date',
      'recorded_at',
      'attendance_time',
    ]);
    if (rawRecordDate != null) {
      final parsed = DateTime.tryParse(rawRecordDate)?.toLocal();
      if (parsed != null &&
          (parsed.year != checkpoint.eventDay.year ||
              parsed.month != checkpoint.eventDay.month ||
              parsed.day != checkpoint.eventDay.day)) {
        return false;
      }
    }

    final rawCheckpointKey = _firstString(raw, const [
      'checkpoint_key',
      'checkpoint',
    ])?.toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');

    final rawSlot = raw['slot_index'] ?? raw['slotIndex'];
    final recordSlotIndex =
        rawSlot != null ? int.tryParse(rawSlot.toString()) : null;

    // If this is a 4-checkpoint slot (e.g., morning_time_in / afternoon_time_out):
    if (checkpoint.slotIndex != null) {
      if (rawCheckpointKey != null && rawCheckpointKey.isNotEmpty) {
        return rawCheckpointKey == checkpoint.checkpointKey;
      }

      if (recordSlotIndex != null) {
        return recordSlotIndex == checkpoint.slotIndex &&
            _isSuccessfulRecordFor(record, checkpoint.baseType);
      }

      // Legacy records without slot_index/checkpoint_key satisfy slot 0 only.
      if (checkpoint.slotIndex == 0) {
        return _isSuccessfulRecordFor(record, checkpoint.baseType);
      }

      return false;
    }

    return _isSuccessfulRecordFor(record, checkpoint.baseType);
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
  // event date, and missed attendance checkpoint/period.
  bool _alreadyHasSanction(
    List<SanctionItem> sanctions, {
    required String eventName,
    required DateTime eventDate,
    required _ExpectedCheckpoint checkpoint,
    required int? eventId,
  }) {
    final labelToken = checkpoint.label.toLowerCase();
    final keyToken = checkpoint.checkpointKey.toLowerCase();
    final hyphenPeriod = checkpoint.baseType.replaceAll('_', '-');

    return sanctions.any((sanction) {
      final title = sanction.title.toLowerCase();

      if (checkpoint.slotIndex != null) {
        final hasMorning = title.contains('morning');
        final hasAfternoon = title.contains('afternoon');
        final matchesCheckpoint = title.contains(labelToken) ||
            title.contains(keyToken) ||
            (title.contains(hyphenPeriod) &&
                ((checkpoint.checkpointKey.startsWith('morning') &&
                        hasMorning) ||
                    (checkpoint.checkpointKey.startsWith('afternoon') &&
                        hasAfternoon) ||
                    (!hasMorning && !hasAfternoon)));
        if (!matchesCheckpoint) {
          return false;
        }
      } else {
        if (!title.contains(hyphenPeriod) &&
            !title.contains(checkpoint.baseType)) {
          return false;
        }
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

  DateTime _getSlotDeadline({
    required Map<String, dynamic> slotMap,
    required Map<String, dynamic> dayMap,
    required EventItem event,
    required DateTime eventDate,
    required bool isTimeIn,
  }) {
    final explicitKeys = isTimeIn
        ? const [
            'time_in_end',
            'time_in_end_time',
            'time_in_until',
            'time_in_to',
            'check_in_end',
          ]
        : const [
            'time_out_end',
            'time_out_end_time',
            'time_out_until',
            'time_out_to',
            'check_out_end',
          ];

    final explicitValue = _firstString(slotMap, explicitKeys);
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

    final rangeKeys = isTimeIn
        ? const ['time_in', 'time_in_window']
        : const ['time_out', 'time_out_window'];
    for (final key in rangeKeys) {
      final rangeEnd = _parseRangeEnd(_firstString(slotMap, [key]));
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

    if (!isTimeIn) {
      final slotEnd = _parseTime(
        _firstString(slotMap, const ['end_time', 'end']) ??
            _firstString(dayMap, const ['end_time', 'end']) ??
            event.endTime,
      );
      if (slotEnd != null) {
        return DateTime(
          eventDate.year,
          eventDate.month,
          eventDate.day,
          slotEnd.hour,
          slotEnd.minute,
          slotEnd.second,
        );
      }
    }

    return eventDate.add(const Duration(days: 1));
  }

  DateTime _getPrefixedPeriodDeadline({
    required Map<String, dynamic> raw,
    required EventItem event,
    required DateTime eventDate,
    required String prefix,
    required bool isTimeIn,
  }) {
    final suffix = isTimeIn ? 'time_in' : 'time_out';
    final explicitValue = _firstString(raw, [
      '${prefix}_${suffix}_end',
      '${prefix}_${suffix}_end_time',
      '${prefix}_${suffix}_until',
      '${prefix}_${suffix}_to',
    ]);
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

    final rangeEnd = _parseRangeEnd(
      _firstString(raw, ['${prefix}_$suffix', '${prefix}_${suffix}_window']),
    );
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

    return _getPeriodDeadline(
      event: event,
      eventDate: eventDate,
      isTimeIn: isTimeIn,
    );
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