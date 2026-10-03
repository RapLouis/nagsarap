class AttendanceHistoryItem {
  final Map<String, dynamic> raw;

  const AttendanceHistoryItem({required this.raw});

  factory AttendanceHistoryItem.fromJson(Map<String, dynamic> json) {
    return AttendanceHistoryItem(raw: json);
  }

  int? get id => _readInt(['attendance_id', 'id']);

  int? get eventId => _readInt(['event_id']);

  String get eventName {
    final eventMap = raw['event'];
    if (eventMap is Map) {
      final name = _readStringFromMap(Map<String, dynamic>.from(eventMap), ['title', 'event_name', 'name']);
      if (name != null) return name;
    }
    return _readString(['event_name', 'title', 'name']) ?? 'Event';
  }

  String get sessionType {
    final session = _readString(['session_type', 'type', 'session'])?.toLowerCase();
    if (session == 'time_out' || session == 'out') {
      return 'time_out';
    }
    return 'time_in';
  }

  String get status {
    return _readString(['status', 'attendance_status'])?.toLowerCase() ?? 'present';
  }

  double get confidenceScore {
    return _readDouble(['confidence_score', 'confidence']) ?? 1.0;
  }

  DateTime? get loggedAt {
    final dateStr = _readString(['logged_at', 'recorded_at', 'created_at', 'date', 'attendance_time']);
    if (dateStr == null) return null;
    return DateTime.tryParse(dateStr);
  }

  String? get formattedTime {
    final time = loggedAt;
    if (time == null) return null;
    final hour = time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
    final period = time.hour >= 12 ? 'PM' : 'AM';
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  // Extended getters for attendance history screen details
  String? get venue {
    final eventMap = raw['event'];
    if (eventMap is Map) {
      final v = _readStringFromMap(Map<String, dynamic>.from(eventMap), ['location', 'venue', 'location_name']);
      if (v != null) return v;
    }
    return _readString(['venue', 'location', 'location_name']);
  }

  double? get locationAccuracy => _readDouble(['location_accuracy', 'accuracy']);

  String? get source => _readString(['source', 'method', 'check_in_method']);

  String? get eventDate {
    final eventMap = raw['event'];
    if (eventMap is Map) {
      final d = _readStringFromMap(Map<String, dynamic>.from(eventMap), ['event_date', 'date']);
      if (d != null) return d;
    }
    return _readString(['event_date', 'date']);
  }

  String? get attendanceTime => formattedTime ?? _readString(['attendance_time', 'logged_at', 'time']);

  String? _readString(List<String> keys) => _readStringFromMap(raw, keys);

  String? _readStringFromMap(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value != null && value.toString().trim().isNotEmpty && value.toString() != 'null') {
        return value.toString().trim();
      }
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
}