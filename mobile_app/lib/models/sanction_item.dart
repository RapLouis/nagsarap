class SanctionItem {
  final int id;
  final String title;
  final String reason;
  final String status;
  final String? consequence;
  final String? checkpoint;
  final String? infractionType;
  final String? slotLabel;
  final String? preferredMode;
  final String? officialReceiptNo;
  final String? adminRemarks;
  final double fineAmount;
  final double? commServiceHours;

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
    this.infractionType,
    this.slotLabel,
    this.preferredMode,
    this.officialReceiptNo,
    this.adminRemarks,
    this.fineAmount = 0.0,
    this.commServiceHours,
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
      json['checkpoint_key'] ??
          json['checkpoint'] ??
          json['infraction_type'] ??
          json['period'] ??
          json['session_type'] ??
          json['type'],
    );

    final fine = _doubleValue(json['fine_amount']) ?? 0.0;
    final rawConsequence = _stringValue(
      json['consequence'] ?? json['sanction_type'] ?? json['penalty'],
    );

    final effectiveConsequence = rawConsequence.isNotEmpty
        ? rawConsequence
        : (fine > 0 ? 'Fine: ₱${fine.toStringAsFixed(2)}' : null);

    return SanctionItem(
      id: _intValue(json['sanction_id'] ?? json['id']) ?? 0,
      title: rawTitle,
      reason: _stringValue(
        json['reason'] ?? json['description'] ?? json['remarks'],
      ),
      status: _stringValue(
        json['status'],
        fallback: 'unsettled',
      ),
      consequence: effectiveConsequence,
      checkpoint: rawCheckpoint.isEmpty ? null : rawCheckpoint,
      infractionType: _nullableString(json['infraction_type']),
      slotLabel: _nullableString(json['slot_label']),
      preferredMode: _nullableString(json['preferred_mode']),
      officialReceiptNo: _nullableString(json['official_receipt_no']),
      adminRemarks: _nullableString(json['admin_remarks']),
      fineAmount: fine,
      commServiceHours: _doubleValue(json['comm_service_hours']),
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
    return s == 'settled' ||
        s == 'excused' ||
        s == 'resolved' ||
        s == 'cleared' ||
        s == 'waived' ||
        resolvedAt != null;
  }

  String get checkpointLabel {
    final key = (infractionType ?? checkpoint ?? '').toLowerCase();
    if (key.contains('morning_time_in')) return 'Morning Time-In';
    if (key.contains('morning_time_out')) return 'Morning Time-Out';
    if (key.contains('afternoon_time_in')) return 'Afternoon Time-In';
    if (key.contains('afternoon_time_out')) return 'Afternoon Time-Out';
    if (missedPeriod == 'time_in') return 'Time-In';
    if (missedPeriod == 'time_out') return 'Time-Out';
    return slotLabel ?? 'Checkpoint';
  }

  String? get missedPeriod {
    final combined =
        '${infractionType ?? ''} ${checkpoint ?? ''} $title $reason'.toLowerCase();

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

  static double? _doubleValue(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static String? _nullableString(dynamic value) {
    final s = _stringValue(value);
    return s.isEmpty ? null : s;
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

class SanctionSummary {
  final double unsettledBalance;
  final int activeCount;
  final bool isCleared;
  final double fineRatePerLog;

  const SanctionSummary({
    this.unsettledBalance = 0.0,
    this.activeCount = 0,
    this.isCleared = true,
    this.fineRatePerLog = 0.0,
  });

  factory SanctionSummary.fromJson(Map<String, dynamic> json) {
    double toDouble(dynamic v) {
      if (v is double) return v;
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '') ?? 0.0;
    }

    int toInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    final count = toInt(json['active_count']);
    return SanctionSummary(
      unsettledBalance: toDouble(json['unsettled_balance']),
      activeCount: count,
      isCleared: json['is_cleared'] is bool ? json['is_cleared'] as bool : count == 0,
      fineRatePerLog: toDouble(json['fine_rate_per_log']),
    );
  }
}