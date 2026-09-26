class SanctionItem {
  final int id;
  final String title;
  final String reason;
  final String status;

  final DateTime? issuedAt;
  final DateTime? resolvedAt;

  const SanctionItem({
    required this.id,
    required this.title,
    required this.reason,
    required this.status,
    required this.issuedAt,
    required this.resolvedAt,
  });

  factory SanctionItem.fromJson(Map<String, dynamic> json) {
    return SanctionItem(
      id: _intValue(json['sanction_id'] ?? json['id']),
      title: _stringValue(json['title'], fallback: 'Attendance Sanction'),
      reason: _stringValue(json['reason']),
      status: _stringValue(json['status'], fallback: 'pending'),
      issuedAt: _dateValue(json['issued_at'] ?? json['created_at']),
      resolvedAt: _dateValue(json['resolved_at']),
    );
  }

  bool get isResolved {
    return status.trim().toLowerCase() == 'resolved';
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

  static String _stringValue(dynamic value, {String fallback = ''}) {
    if (value == null) {
      return fallback;
    }

    final text = value.toString().trim();

    if (text.isEmpty || text.toLowerCase() == 'null') {
      return fallback;
    }

    return text;
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
