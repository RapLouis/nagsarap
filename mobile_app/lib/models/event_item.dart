class EventItem {
  final Map<String, dynamic> raw;

  const EventItem({required this.raw});

  factory EventItem.fromJson(Map<String, dynamic> json) {
    return EventItem(raw: json);
  }

  int? get id => _intValue(['id', 'event_id']);

  String get name => _stringValue(['event_name', 'name', 'title']) ?? 'Event';

  String get description =>
      _stringValue(['description', 'event_description']) ?? '';

  String get eventDate => _stringValue(['event_date', 'date']) ?? '';

  String get startTime =>
      _stringValue(['start_time', 'time_in', 'attendance_start']) ?? '';

  String get endTime =>
      _stringValue(['end_time', 'time_out', 'attendance_end']) ?? '';

  String get venue =>
      _stringValue(['venue', 'location', 'location_name', 'event_location']) ??
      '';

  bool get isActive {
    final value = raw['is_active'];

    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value == 1;
    }

    final text = value?.toString().toLowerCase();

    return text == '1' || text == 'true';
  }

  DateTime? get date {
    final value = eventDate.trim();

    if (value.isEmpty) {
      return null;
    }

    final parsed = DateTime.tryParse(value);

    if (parsed != null) {
      return DateTime(parsed.year, parsed.month, parsed.day);
    }

    if (value.length >= 10) {
      final shortened = value.substring(0, 10);
      return DateTime.tryParse(shortened);
    }

    return null;
  }

  bool get isToday {
    final event = date;

    if (event == null) {
      return false;
    }

    final now = DateTime.now();

    return event.year == now.year &&
        event.month == now.month &&
        event.day == now.day;
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

  String? _stringValue(List<String> keys) {
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

  int? _intValue(List<String> keys) {
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
}
