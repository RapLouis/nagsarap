class AttendanceHistoryItem {
  final int id;
  final int? eventId;

  final String eventName;
  final String eventDate;
  final String startTime;
  final String endTime;
  final String venue;

  final String status;

  final DateTime? attendanceTime;
  final DateTime? syncTime;

  final double? confidenceScore;
  final double? latitude;
  final double? longitude;
  final double? locationAccuracy;

  final String source;

  const AttendanceHistoryItem({
    required this.id,
    required this.eventId,
    required this.eventName,
    required this.eventDate,
    required this.startTime,
    required this.endTime,
    required this.venue,
    required this.status,
    required this.attendanceTime,
    required this.syncTime,
    required this.confidenceScore,
    required this.latitude,
    required this.longitude,
    required this.locationAccuracy,
    required this.source,
  });

  factory AttendanceHistoryItem.fromJson(Map<String, dynamic> json) {
    final event = _mapValue(json['event']);

    return AttendanceHistoryItem(
      id: _intValue(json['attendance_id'] ?? json['id']),
      eventId: _nullableInt(
        json['event_id'] ?? event['event_id'] ?? event['id'],
      ),
      eventName: _stringValue(
        event['title'] ?? event['name'] ?? json['event_name'] ?? 'Event',
      ),
      eventDate: _stringValue(
        event['event_date'] ?? event['date'] ?? json['event_date'],
      ),
      startTime: _stringValue(event['start_time'] ?? json['start_time']),
      endTime: _stringValue(event['end_time'] ?? json['end_time']),
      venue: _stringValue(
        event['location'] ??
            event['venue'] ??
            json['location'] ??
            json['venue'],
      ),
      status: _stringValue(json['status'] ?? 'Recorded'),
      attendanceTime: _dateValue(
        json['attendance_time'] ?? json['logged_at'] ?? json['created_at'],
      ),
      syncTime: _dateValue(json['sync_time']),
      confidenceScore: _doubleValue(
        json['confidence_score'] ??
            json['face_confidence'] ??
            json['face_similarity'],
      ),
      latitude: _doubleValue(json['latitude']),
      longitude: _doubleValue(json['longitude']),
      locationAccuracy: _doubleValue(json['location_accuracy']),
      source: _stringValue(json['source']),
    );
  }

  static Map<String, dynamic> _mapValue(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return <String, dynamic>{};
  }

  static String _stringValue(dynamic value) {
    if (value == null) {
      return '';
    }

    final result = value.toString().trim();

    if (result.toLowerCase() == 'null') {
      return '';
    }

    return result;
  }

  static int _intValue(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int? _nullableInt(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value.toString());
  }

  static double? _doubleValue(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString());
  }

  static DateTime? _dateValue(dynamic value) {
    if (value == null) {
      return null;
    }

    final text = value.toString().trim();

    if (text.isEmpty || text.toLowerCase() == 'null') {
      return null;
    }

    return DateTime.tryParse(text);
  }
}
