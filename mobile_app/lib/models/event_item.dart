class EventItem {
  final Map<String, dynamic> raw;

  const EventItem({required this.raw});

  factory EventItem.fromJson(Map<String, dynamic> json) {
    return EventItem(raw: json);
  }

  int? get id => _readInt(['event_id', 'id']);

  String get name => _readString(['title', 'event_name', 'name']) ?? 'Event';

  String get description =>
      _readString(['description', 'event_description']) ?? '';

  String get eventDate =>
      _readString(['event_date', 'start_date', 'date']) ?? '';

  String get endDate =>
      _readString(['end_date', 'event_date', 'start_date', 'date']) ?? '';

  List get days {
    final rawDays = raw['days'];
    if (rawDays is List) {
      final List result = [];
      for (final item in rawDays) {
        if (item is Map) {
          result.add(Map<String, dynamic>.from(item));
        }
      }
      return result;
    }
    return const [];
  }

  Map<String, dynamic>? get todayDay {
    final todayStr = _todayIsoDate();
    for (final day in days) {
      if (day is Map) {
        final d = (day['event_date'] ?? day['date'] ?? '').toString().trim();
        if (d.length >= 10 && d.substring(0, 10) == todayStr) {
          return Map<String, dynamic>.from(day);
        }
      }
    }
    return null;
  }

  List get activeSlots {
    final allDays = days;
    final Map<String, dynamic>? targetDay = todayDay ??
        (allDays.isNotEmpty && allDays.first is Map
            ? Map<String, dynamic>.from(allDays.first as Map)
            : null);

    final rawSlots = targetDay != null ? targetDay['slots'] : raw['slots'];
    if (rawSlots is List) {
      final List result = [];
      for (final item in rawSlots) {
        if (item is Map) {
          result.add(Map<String, dynamic>.from(item));
        }
      }
      return result;
    }
    return const [];
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
    final slots = activeSlots;
    if (slots.isNotEmpty && slots.first is Map) {
      final firstSlotStart = (slots.first as Map)['time_in_start']?.toString();
      if (firstSlotStart != null && firstSlotStart.trim().isNotEmpty) {
        return _toMilitaryTime(firstSlotStart, takeLast: false);
      }
    }
    return _toMilitaryTime(
      _readString(['start_time', 'time_in', 'attendance_start']),
      takeLast: false,
    );
  }

  String get endTime {
    final slots = activeSlots;
    if (slots.isNotEmpty && slots.last is Map) {
      final lastSlot = slots.last as Map;
      final lastSlotEnd =
          (lastSlot['time_out_end'] ?? lastSlot['time_in_end'])?.toString();
      if (lastSlotEnd != null && lastSlotEnd.trim().isNotEmpty) {
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
      if (day is Map) {
        final dStr = (day['event_date'] ?? day['date'] ?? '').toString().trim();
        if (dStr.length >= 10) {
          final parsed = DateTime.tryParse(dStr.substring(0, 10));
          if (parsed != null && parsed.isAfter(todayOnly)) {
            return true;
          }
        }
      }
    }

    final event = date;
    if (event == null) return false;
    return event.isAfter(todayOnly);
  }

  String? _readString(List keys) {
    for (final key in keys) {
      final value = raw[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
    }
    return null;
  }

  int? _readInt(List keys) {
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

  double? _readDouble(List keys) {
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