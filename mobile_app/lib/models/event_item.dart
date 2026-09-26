class EventItem {
  final Map<String, dynamic> raw;

  const EventItem({required this.raw});

  factory EventItem.fromJson(Map<String, dynamic> json) {
    return EventItem(raw: json);
  }

  // ===========================================================================
  // BASIC FIELDS
  // ===========================================================================

  int? get id {
    return _readInt(['event_id', 'id']);
  }

  String get name {
    return _readString(['title', 'event_name', 'name']) ?? 'Event';
  }

  String get description {
    return _readString(['description', 'event_description']) ?? '';
  }

  String get eventDate {
    return _readString(['event_date', 'date']) ?? '';
  }

  String get startTime {
    return _readString(['start_time', 'time_in', 'attendance_start']) ?? '';
  }

  String get endTime {
    return _readString(['end_time', 'time_out', 'attendance_end']) ?? '';
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

  // ===========================================================================
  // GEOFENCE
  // ===========================================================================

  double? get latitude {
    return _readDouble(['latitude']);
  }

  double? get longitude {
    return _readDouble(['longitude']);
  }

  int get geofenceRadius {
    return _readInt(['geofence_radius']) ?? 0;
  }

  bool get geofenceEnabled {
    return _readBool(raw['geofence_enabled']);
  }

  int get lateAfterMinutes {
    return _readInt(['late_after_minutes']) ?? 0;
  }

  bool get isActive {
    return _readBool(raw['is_active']);
  }

  // ===========================================================================
  // DATE
  // ===========================================================================

  /*
   * Laravel may send:
   *
   * 2026-09-09
   *
   * OR:
   *
   * 2026-09-09T00:00:00.000000Z
   *
   * We normalize both to YYYY-MM-DD.
   */

  String get normalizedDate {
    final value = eventDate.trim();

    if (value.isEmpty) {
      return '';
    }

    if (value.length >= 10) {
      return value.substring(0, 10);
    }

    return value;
  }

  DateTime? get date {
    final normalized = normalizedDate;

    if (normalized.isEmpty) {
      return null;
    }

    return DateTime.tryParse(normalized);
  }

  /*
   * Compare YYYY-MM-DD directly.
   *
   * This avoids UTC/local timezone conversion problems.
   */

  bool get isToday {
    final now = DateTime.now();

    final today =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';

    return normalizedDate == today;
  }

  bool get isUpcoming {
    final event = date;

    if (event == null) {
      return false;
    }

    final now = DateTime.now();

    final today = DateTime(now.year, now.month, now.day);

    return event.isAfter(today);
  }

  // ===========================================================================
  // PARSING
  // ===========================================================================

  String? _readString(List<String> keys) {
    for (final key in keys) {
      final value = raw[key];

      if (value == null) {
        continue;
      }

      final text = value.toString().trim();

      if (text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }

    return null;
  }

  int? _readInt(List<String> keys) {
    for (final key in keys) {
      final value = raw[key];

      if (value is int) {
        return value;
      }

      if (value is num) {
        return value.toInt();
      }

      if (value != null) {
        final parsed = int.tryParse(value.toString());

        if (parsed != null) {
          return parsed;
        }
      }
    }

    return null;
  }

  double? _readDouble(List<String> keys) {
    for (final key in keys) {
      final value = raw[key];

      if (value is double) {
        return value;
      }

      if (value is num) {
        return value.toDouble();
      }

      if (value != null) {
        final parsed = double.tryParse(value.toString());

        if (parsed != null) {
          return parsed;
        }
      }
    }

    return null;
  }

  bool _readBool(dynamic value) {
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
}
