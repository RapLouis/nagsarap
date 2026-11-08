class SanctionItem {
  final int id;
  final String title;
  final String reason;
  final String status;

  final DateTime? issuedAt;
  final DateTime? resolvedAt;
  final DateTime? eventDate;

  final int? eventId;

  const SanctionItem({
    required this.id,
    required this.title,
    required this.reason,
    required this.status,
    required this.issuedAt,
    required this.resolvedAt,
    this.eventDate,
    this.eventId,
  });

  factory SanctionItem.fromJson(
    Map<String, dynamic> json,
  ) {
    final event = json['event'];

    final eventMap = event is Map
        ? Map<String, dynamic>.from(event)
        : <String, dynamic>{};

    return SanctionItem(
      id: _intValue(
            json['sanction_id'] ?? json['id'],
          ) ??
          0,

      title: _stringValue(
        json['title'],
        fallback: 'Attendance Sanction',
      ),

      reason: _stringValue(json['reason']),

      status: _stringValue(
        json['status'],
        fallback: 'pending',
      ),

      issuedAt: _dateValue(
        json['issued_at'] ?? json['created_at'],
      ),

      resolvedAt: _dateValue(
        json['resolved_at'],
      ),

      eventDate: _dateValue(
        json['event_date'] ??
            json['start_date'] ??
            eventMap['event_date'] ??
            eventMap['date'],
      ),

      eventId: _intValue(
        json['event_id'] ??
            eventMap['event_id'] ??
            eventMap['id'],
      ),
    );
  }

  bool get isResolved {
    return status.trim().toLowerCase() == 'resolved';
  }

  // Identify which attendance period was missed.
  String? get missedPeriod {
    final lower = title.toLowerCase();

    if (lower.contains('time-in') ||
        lower.contains('time in')) {
      return 'time_in';
    }

    if (lower.contains('time-out') ||
        lower.contains('time out')) {
      return 'time_out';
    }

    return null;
  }

  static int? _intValue(dynamic value) {
    if (value is int) return value;

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '');
  }

  static String _stringValue(
    dynamic value, {
    String fallback = '',
  }) {
    if (value == null) return fallback;

    final text = value.toString().trim();

    if (text.isEmpty || text.toLowerCase() == 'null') {
      return fallback;
    }

    return text;
  }

  static DateTime? _dateValue(dynamic value) {
    if (value == null) return null;

    final text = value.toString().trim();

    if (text.isEmpty || text.toLowerCase() == 'null') {
      return null;
    }

    return DateTime.tryParse(text);
  }
}