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

  String _toMilitaryTime(String? value) {
    if (value == null) return '';
    final text = value.trim();
    if (text.isEmpty) return '';

    try {
      final uppercase = text.toUpperCase();
      if (uppercase.contains('AM') || uppercase.contains('PM')) {
        final parsed = DateFormat('h:mm a').parse(uppercase);
        return DateFormat('HH:mm:ss').format(parsed);
      } else if (uppercase.contains(':')) {
        final parts = uppercase.split(':');
        if (parts.length == 2) {
          final parsed = DateFormat('HH:mm').parse(uppercase);
          return DateFormat('HH:mm:ss').format(parsed);
        } else if (parts.length >= 3) {
          final parsed = DateFormat('HH:mm:ss').parse(uppercase);
          return DateFormat('HH:mm:ss').format(parsed);
        }
      }
    } catch (_) {}

    return text;
  }

  String get startTime {
    return _toMilitaryTime(_readString(['start_time', 'time_in', 'attendance_start']));
  }

  String get endTime {
    return _toMilitaryTime(_readString(['end_time', 'time_out', 'attendance_end']));
  }

  String? get formattedTimeRange {
    final start = startTime.trim();
    final end = endTime.trim();
    if (start.isEmpty && end.isEmpty) {
      return null;
    }
    if (start.isNotEmpty && end.isNotEmpty) {
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