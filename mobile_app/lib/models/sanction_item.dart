class SanctionItem {
  final int id;
  final String title;
  final String reason;
  final String status;
  final String? consequence;
  final String? checkpoint;

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
    this.consequence,
    this.checkpoint,
    this.eventDate,
    this.eventId,
  });

  factory SanctionItem.fromJson(Map<String, dynamic> json) {
    final event = json['event'];

    final eventMap = event is Map
        ? Map<String, dynamic>.from(event)
        : <String, dynamic>{};

    final rawTitle = _stringValue(
      json['title'] ??
          json['event_title'] ??
          json['violation'] ??
          eventMap['title'] ??
          eventMap['name'],
      fallback: 'Attendance Sanction',
    );

    final rawCheckpoint = _stringValue(
      json['checkpoint'] ??
          json['checkpoint_key'] ??
          json['period'] ??
          json['session_type'] ??
          json['type'],
    );

    final rawConsequence = _stringValue(
      json['consequence'] ?? json['sanction_type'] ?? json['penalty'],
    );

    return SanctionItem(
      id: _intValue(json['sanction_id'] ?? json['id']) ?? 0,
      title: rawTitle,
      reason: _stringValue(
        json['reason'] ?? json['description'] ?? json['remarks'],
      ),
      status: _stringValue(
        json['status'],
        fallback: 'pending',
      ),
      consequence: rawConsequence.isEmpty ? null : rawConsequence,
      checkpoint: rawCheckpoint.isEmpty ? null : rawCheckpoint,
      issuedAt: _dateValue(
        json['issued_at'] ?? json['created_at'],
      ),
      resolvedAt: _dateValue(
        json['resolved_at'] ?? json['cleared_at'],
      ),
      eventDate: _dateValue(
        json['event_date'] ??
            json['start_date'] ??
            eventMap['event_date'] ??
            eventMap['start_date'] ??
            eventMap['date'],
      ),
      eventId: _intValue(
        json['event_id'] ?? eventMap['event_id'] ?? eventMap['id'],
      ),
    );
  }

  bool get isResolved {
    final s = status.trim().toLowerCase();
    return s == 'resolved' ||
        s == 'cleared' ||
        s == 'waived' ||
        resolvedAt != null;
  }

  String? get missedPeriod {
    final combined = '${checkpoint ?? ''} $title $reason'.toLowerCase();

    final hasTimeIn = combined.contains('time-in') ||
        combined.contains('time in') ||
        combined.contains('time_in');
    final hasTimeOut = combined.contains('time-out') ||
        combined.contains('time out') ||
        combined.contains('time_out');

    if ((hasTimeIn && hasTimeOut) ||
        combined.contains('absent') ||
        combined.contains('both')) {
      return 'both';
    }
    if (hasTimeIn) return 'time_in';
    if (hasTimeOut) return 'time_out';

    return null;
  }

  static int? _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
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