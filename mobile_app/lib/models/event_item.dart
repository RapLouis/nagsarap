import 'package:intl/intl.dart';

class EventItem {
  final Map<String, dynamic> raw;

  const EventItem({required this.raw});

  factory EventItem.fromJson(Map<String, dynamic> json) {
    return EventItem(raw: json);
  }

  int? get id => _readInt(['event_id', 'id']);

  String get name => _readString(['title', 'event_name', 'name']) ?? 'Event';

  String get description => _readString(['description', 'event_description']) ?? '';

  String get eventDate => _readString(['event_date', 'date']) ?? '';

  String _toMilitaryTime(String? value, {bool takeLast = false}) {
    if (value == null) return '';
    final text = value.trim();
    if (text.isEmpty) return '';

    try {
      final uppercase = text.toUpperCase();

      // Handle Range Strings (e.g. "8:00 AM - 11:10 PM")
      final amPmRegex = RegExp(r'(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(AM|PM)', caseSensitive: false);
      final matches = amPmRegex.allMatches(uppercase).toList();

      if (matches.isNotEmpty) {
        final match = takeLast ? matches.last : matches.first;
        int hour = int.parse(match.group(1)!);
        final minute = int.parse(match.group(2)!);
        final second = match.group(3) != null ? int.parse(match.group(3)!) : 0;
        final period = match.group(4)!.toUpperCase();

        if (period == 'PM' && hour < 12) hour += 12;
        if (period == 'AM' && hour == 12) hour = 0;

        return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}';
      }

      final h24Regex = RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)(?::([0-5]\d))?\b');
      final h24Matches = h24Regex.allMatches(uppercase).toList();

      if (h24Matches.isNotEmpty) {
        final match = takeLast ? h24Matches.last : h24Matches.first;
        final hour = int.parse(match.group(1)!);
        final minute = int.parse(match.group(2)!);
        final second = match.group(3) != null ? int.parse(match.group(3)!) : 0;
        return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}';
      }
    } catch (_) {}

    return text;
  }

  String get startTime {
    return _toMilitaryTime(_readString(['start_time', 'time_in', 'attendance_start']), takeLast: false);
  }

  String get endTime {
    return _toMilitaryTime(_readString(['end_time', 'time_out', 'attendance_end']), takeLast: true);
  }

  String? get formattedTimeRange {
    final start = startTime.trim();
    final end = endTime.trim();
    if (start.isEmpty && end.isEmpty) {
      return null;
    }
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

  int get geofenceRadius => _readInt(['geofence_radius']) ?? 0;

  bool get geofenceEnabled => _readBool(raw['geofence_enabled']);

  int get lateAfterMinutes => _readInt(['late_after_minutes']) ?? 0;

  bool get isActive => _readBool(raw['is_active']);

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
    if (event == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return event.isAfter(today);
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