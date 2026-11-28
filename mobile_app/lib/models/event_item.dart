typedef JsonMap = Map<String, dynamic>;

class EventCheckpointSlot {
  final int slotIndex;
  final String slotLabel;
  final String checkpointKey;
  final String type; // 'in' or 'out'
  final String label;
  final String startTime;
  final String endTime;

  const EventCheckpointSlot({
    required this.slotIndex,
    required this.slotLabel,
    required this.checkpointKey,
    required this.type,
    required this.label,
    required this.startTime,
    required this.endTime,
  });

  bool get isTimeOut => type == 'out';
}

class EventItem {
  final JsonMap raw;

  const EventItem({required this.raw});

  factory EventItem.fromJson(JsonMap json) {
    return EventItem(raw: json);
  }

  int? get id => _readInt(['event_id', 'id']);

  String get name => _readString(['title', 'event_name', 'name']) ?? 'Event';

  String get description =>
      _readString(['description', 'event_description']) ?? '';

  String get eventDate =>
      _readString(['event_date', 'start_date', 'date']) ?? '';

  String get endDate =>
      _readString([
        'event_end_date',
        'end_date',
        'event_date',
        'start_date',
        'date',
      ]) ??
      '';

  List<JsonMap> get days {
    final rawDays = raw['days'];
    if (rawDays is List) {
      final result = <JsonMap>[];
      for (final item in rawDays) {
        if (item is Map) {
          result.add(JsonMap.from(item));
        }
      }
      return result;
    }
    return const [];
  }

  JsonMap? get todayDay {
    final todayStr = _todayIsoDate();
    for (final day in days) {
      final d = (day['event_date'] ?? day['date'] ?? '').toString().trim();
      if (d.length >= 10 && d.substring(0, 10) == todayStr) {
        return JsonMap.from(day);
      }
    }
    return null;
  }

  List<JsonMap> get activeSlots {
    final allDays = days;
    final JsonMap? targetDay =
        todayDay ?? (allDays.isNotEmpty ? allDays.first : null);

    final rawSlots = targetDay != null ? targetDay['slots'] : raw['slots'];
    if (rawSlots is List) {
      final result = <JsonMap>[];
      for (final item in rawSlots) {
        if (item is Map) {
          result.add(JsonMap.from(item));
        }
      }
      return result;
    }
    return const [];
  }

  /// Extracts all configured checkpoints (Morning Time-In/Out & Afternoon Time-In/Out)
  /// across the active day's slots.
  List<EventCheckpointSlot> get todayCheckpoints {
    final slots = activeSlots;
    final result = <EventCheckpointSlot>[];

    for (int i = 0; i < slots.length; i++) {
      final slot = slots[i];
      final slotLabel = slot['label']?.toString().trim().isNotEmpty == true
          ? slot['label'].toString().trim()
          : 'Slot ${i + 1}';

      final morningEnabled =
          slot['morning_enabled'] != false && slot['has_morning'] != false;
      final afternoonEnabled =
          slot['afternoon_enabled'] != false && slot['has_afternoon'] != false;

      if (morningEnabled) {
        final mInStart = _firstSlotValue(slot, [
          'morning_time_in_start',
          'time_in_start',
        ]);
        final mInEnd = _firstSlotValue(slot, [
          'morning_time_in_end',
          'time_in_end',
        ]);
        if (mInStart != null) {
          result.add(
            EventCheckpointSlot(
              slotIndex: i,
              slotLabel: slotLabel,
              checkpointKey: 'morning_time_in',
              type: 'in',
              label: 'Morning Time-In',
              startTime: mInStart,
              endTime: mInEnd ?? mInStart,
            ),
          );
        }

        final mOutStart = _firstSlotValue(slot, [
          'morning_time_out_start',
          'time_out_start',
        ]);
        final mOutEnd = _firstSlotValue(slot, [
          'morning_time_out_end',
          'time_out_end',
        ]);
        if (mOutStart != null) {
          result.add(
            EventCheckpointSlot(
              slotIndex: i,
              slotLabel: slotLabel,
              checkpointKey: 'morning_time_out',
              type: 'out',
              label: 'Morning Time-Out',
              startTime: mOutStart,
              endTime: mOutEnd ?? mOutStart,
            ),
          );
        }
      }

      if (afternoonEnabled) {
        final aInStart = _firstSlotValue(slot, ['afternoon_time_in_start']);
        final aInEnd = _firstSlotValue(slot, ['afternoon_time_in_end']);
        if (aInStart != null) {
          result.add(
            EventCheckpointSlot(
              slotIndex: i,
              slotLabel: slotLabel,
              checkpointKey: 'afternoon_time_in',
              type: 'in',
              label: 'Afternoon Time-In',
              startTime: aInStart,
              endTime: aInEnd ?? aInStart,
            ),
          );
        }

        final aOutStart = _firstSlotValue(slot, ['afternoon_time_out_start']);
        final aOutEnd = _firstSlotValue(slot, ['afternoon_time_out_end']);
        if (aOutStart != null) {
          result.add(
            EventCheckpointSlot(
              slotIndex: i,
              slotLabel: slotLabel,
              checkpointKey: 'afternoon_time_out',
              type: 'out',
              label: 'Afternoon Time-Out',
              startTime: aOutStart,
              endTime: aOutEnd ?? aOutStart,
            ),
          );
        }
      }
    }

    return result;
  }

List<JsonMap> get studentAttendances {
    final rawList = raw['student_attendances'];
    if (rawList is List) {
      return rawList
          .whereType()
          .map((e) => JsonMap.from(e))
          .toList();
    }
    return const [];
  }

  bool isCheckpointRecorded(int slotIndex, String checkpointKey) {
    final todayStr = _todayIsoDate();
    for (final att in studentAttendances) {
      final attSlot = att['slot_index'] is num
          ? (att['slot_index'] as num).toInt()
          : int.tryParse(att['slot_index']?.toString() ?? '');
      final attKey = att['checkpoint_key']?.toString().trim();
      final attDate = att['event_date']?.toString().trim();

      if (attDate != null &&
          attDate.isNotEmpty &&
          attDate.length >= 10 &&
          attDate.substring(0, 10) != todayStr) {
        continue;
      }

      if ((attSlot == null || attSlot == slotIndex) && attKey == checkpointKey) {
        return true;
      }
    }
    return false;
  }

  String? _firstSlotValue(JsonMap slot, List<String> keys) {
    for (final key in keys) {
      final val = slot[key];
      if (val != null) {
        final str = val.toString().trim();
        if (str.isNotEmpty && str.toLowerCase() != 'null') {
          return str;
        }
      }
    }
    return null;
  }

  String _toMilitaryTime(String? value, {bool takeLast = false}) {
    if (value == null) return '';
    final text = value.trim();
    if (text.isEmpty) return '';

    try {
      final uppercase = text.toUpperCase();

      final amPmRegex = RegExp(
        r'(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(AM|PM)',
        caseSensitive: false,
      );
      final matches = amPmRegex.allMatches(uppercase).toList();

      if (matches.isNotEmpty) {
        final match = takeLast ? matches.last : matches.first;
        int hour = int.parse(match.group(1)!);
        final minute = int.parse(match.group(2)!);
        final second = match.group(3) != null ? int.parse(match.group(3)!) : 0;
        final period = match.group(4)!.toUpperCase();

        if (period == 'PM' && hour < 12) hour += 12;
        if (period == 'AM' && hour == 12) hour = 0;

        return '${hour.toString().padLeft(2, '0')}:'
            '${minute.toString().padLeft(2, '0')}:'
            '${second.toString().padLeft(2, '0')}';
      }

      final h24Regex = RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)(?::([0-5]\d))?\b');
      final h24Matches = h24Regex.allMatches(uppercase).toList();

      if (h24Matches.isNotEmpty) {
        final match = takeLast ? h24Matches.last : h24Matches.first;
        final hour = int.parse(match.group(1)!);
        final minute = int.parse(match.group(2)!);
        final second = match.group(3) != null ? int.parse(match.group(3)!) : 0;
        return '${hour.toString().padLeft(2, '0')}:'
            '${minute.toString().padLeft(2, '0')}:'
            '${second.toString().padLeft(2, '0')}';
      }
    } catch (_) {}

    return text;
  }

  String get startTime {
    final checkpoints = todayCheckpoints;
    if (checkpoints.isNotEmpty) {
      return _toMilitaryTime(checkpoints.first.startTime, takeLast: false);
    }
    final slots = activeSlots;
    if (slots.isNotEmpty) {
      final firstSlotStart = _firstSlotValue(slots.first, [
        'morning_time_in_start',
        'time_in_start',
        'afternoon_time_in_start',
      ]);
      if (firstSlotStart != null) {
        return _toMilitaryTime(firstSlotStart, takeLast: false);
      }
    }
    return _toMilitaryTime(
      _readString(['start_time', 'time_in', 'attendance_start']),
      takeLast: false,
    );
  }

  String get endTime {
    final checkpoints = todayCheckpoints;
    if (checkpoints.isNotEmpty) {
      return _toMilitaryTime(checkpoints.last.endTime, takeLast: true);
    }
    final slots = activeSlots;
    if (slots.isNotEmpty) {
      final lastSlotEnd = _firstSlotValue(slots.last, [
        'afternoon_time_out_end',
        'morning_time_out_end',
        'time_out_end',
        'afternoon_time_in_end',
        'morning_time_in_end',
        'time_in_end',
      ]);
      if (lastSlotEnd != null) {
        return _toMilitaryTime(lastSlotEnd, takeLast: true);
      }
    }
    return _toMilitaryTime(
      _readString(['end_time', 'time_out', 'attendance_end']),
      takeLast: true,
    );
  }

  String? get formattedTimeRange {
    final start = startTime.trim();
    final end = endTime.trim();
    if (start.isEmpty && end.isEmpty) return null;
    if (start.isNotEmpty && end.isNotEmpty && start != end) {
      return '$start - $end';
    }
    return start.isNotEmpty ? start : end;
  }

  String get venue {
    return _readString([
          'location',
          'venue',
          'location_name',
          'event_location',
        ]) ??
        '';
  }

  double? get latitude => _readDouble(['latitude']);

  double? get longitude => _readDouble(['longitude']);

  int get geofenceRadius =>
      _readInt(['radius_meters', 'geofence_radius']) ?? 0;

  bool get geofenceEnabled =>
      _readBool(raw['is_geofenced'] ?? raw['geofence_enabled']);

  int get lateAfterMinutes => _readInt(['late_after_minutes']) ?? 0;

  bool get isActive =>
      raw['is_active'] == null ? true : _readBool(raw['is_active']);

  String get normalizedDate {
    final value = eventDate.trim();
    if (value.isEmpty) return '';
    if (value.length >= 10) return value.substring(0, 10);
    return value;
  }

  DateTime? get date {
    final normalized = normalizedDate;
    if (normalized.isEmpty) return null;
    return DateTime.tryParse(normalized);
  }

  DateTime? get parsedEndDate {
    final value = endDate.trim();
    if (value.isEmpty) return date;
    final norm = value.length >= 10 ? value.substring(0, 10) : value;
    return DateTime.tryParse(norm) ?? date;
  }

  String _todayIsoDate() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  bool get isToday {
    if (todayDay != null) return true;

    final todayStr = _todayIsoDate();
    if (normalizedDate == todayStr) return true;

    final start = date;
    final end = parsedEndDate;
    if (start != null && end != null) {
      final now = DateTime.now();
      final todayOnly = DateTime(now.year, now.month, now.day);
      final startOnly = DateTime(start.year, start.month, start.day);
      final endOnly = DateTime(end.year, end.month, end.day);
      return !todayOnly.isBefore(startOnly) && !todayOnly.isAfter(endOnly);
    }

    return false;
  }

  bool get isUpcoming {
    if (isToday) return false;
    final now = DateTime.now();
    final todayOnly = DateTime(now.year, now.month, now.day);

    for (final day in days) {
      final dStr = (day['event_date'] ?? day['date'] ?? '').toString().trim();
      if (dStr.length >= 10) {
        final parsed = DateTime.tryParse(dStr.substring(0, 10));
        if (parsed != null && parsed.isAfter(todayOnly)) {
          return true;
        }
      }
    }

    final event = date;
    if (event == null) return false;
    return event.isAfter(todayOnly);
  }

  String? _readString(List<String> keys) {
    for (final key in keys) {
      final value = raw[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
    }
    return null;
  }

  int? _readInt(List<String> keys) {
    for (final key in keys) {
      final value = raw[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value != null) {
        final parsed = int.tryParse(value.toString());
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  double? _readDouble(List<String> keys) {
    for (final key in keys) {
      final value = raw[key];
      if (value is double) return value;
      if (value is num) return value.toDouble();
      if (value != null) {
        final parsed = double.tryParse(value.toString());
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  bool _readBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1';
    }
    return false;
  }
}