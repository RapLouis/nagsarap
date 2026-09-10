import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/attendance_history_item.dart';
import '../../services/attendance_history_service.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  State<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  static const Color navy = Color(0xFF080878);

  static const Color background = Color(0xFFF6F6F6);

  static const Color muted = Color(0xFF777783);

  bool _loading = true;

  String? _error;

  List<AttendanceHistoryItem> _records = const [];

  @override
  void initState() {
    super.initState();

    _loadHistory();
  }

  Future<void> _loadHistory() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    final result = await AttendanceHistoryService.instance.getHistory();

    if (!mounted) {
      return;
    }

    setState(() {
      _loading = false;

      if (result.success) {
        _records = result.records;
        _error = null;
      } else {
        _records = const [];
        _error = result.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Attendance History',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: RefreshIndicator(
        color: navy,
        onRefresh: _loadHistory,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: navy));
    }

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [const SizedBox(height: 100), _buildError()],
      );
    }

    if (_records.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [const SizedBox(height: 100), _buildEmpty()],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 30),
      itemCount: _records.length,
      separatorBuilder: (BuildContext context, int index) =>
          const SizedBox(height: 14),
      itemBuilder: (BuildContext context, int index) {
        return _buildAttendanceCard(_records[index]);
      },
    );
  }

  Widget _buildAttendanceCard(AttendanceHistoryItem record) {
    final statusColor = _statusColor(record.status);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFE2E2E8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4C8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.event_available_rounded,
                  color: navy,
                  size: 24,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.eventName,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _eventDate(record),
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _displayStatus(record.status),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),
          _infoRow(
            Icons.access_time_rounded,
            'Attendance Time',
            _attendanceDateTime(record.attendanceTime),
          ),
          if (record.venue.isNotEmpty) ...[
            const SizedBox(height: 10),
            _infoRow(Icons.location_on_outlined, 'Location', record.venue),
          ],
          if (record.confidenceScore != null) ...[
            const SizedBox(height: 10),
            _infoRow(
              Icons.verified_user_outlined,
              'Face Match',
              _confidence(record.confidenceScore!),
            ),
          ],
          if (record.locationAccuracy != null) ...[
            const SizedBox(height: 10),
            _infoRow(
              Icons.gps_fixed_rounded,
              'GPS Accuracy',
              '±${record.locationAccuracy!.round()} m',
            ),
          ],
          if (record.source.isNotEmpty) ...[
            const SizedBox(height: 10),
            _infoRow(
              Icons.devices_rounded,
              'Source',
              _sourceName(record.source),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: navy, size: 18),
        const SizedBox(width: 9),
        SizedBox(
          width: 112,
          child: Text(
            label,
            style: const TextStyle(color: muted, fontSize: 12),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Column(
        children: [
          Icon(Icons.history_rounded, color: navy, size: 48),
          SizedBox(height: 14),
          Text(
            'No attendance yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 7),
          Text(
            'Your recorded attendance will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 46),
          const SizedBox(height: 13),
          const Text(
            'Unable to load history',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            _error ?? 'Please try again.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted, fontSize: 13),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _loadHistory,
            style: FilledButton.styleFrom(
              backgroundColor: navy,
              foregroundColor: Colors.white,
            ),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  String _eventDate(AttendanceHistoryItem record) {
    final parsed = DateTime.tryParse(record.eventDate);

    if (parsed != null) {
      return DateFormat('MMMM d, yyyy').format(parsed);
    }

    if (record.eventDate.isNotEmpty) {
      return record.eventDate;
    }

    if (record.attendanceTime != null) {
      return DateFormat('MMMM d, yyyy')
          .format(record.attendanceTime!.toLocal());
    }

    return 'Date unavailable';
  }

  String _attendanceDateTime(DateTime? value) {
    if (value == null) {
      return 'Time unavailable';
    }

    return DateFormat('MMM d, yyyy • h:mm a').format(value.toLocal());
  }

  String _confidence(double score) {
    final percentage = score <= 1 ? score * 100 : score;

    return '${percentage.toStringAsFixed(1)}%';
  }

  String _displayStatus(String value) {
    final normalized = value.trim();

    if (normalized.isEmpty) {
      return 'Recorded';
    }

    return normalized
        .split('_')
        .map(
          (word) => word.isEmpty
              ? ''
              : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  Color _statusColor(String status) {
    switch (status.trim().toLowerCase()) {
      case 'present':
      case 'verified':
        return const Color(0xFF159947);

      case 'late':
        return const Color(0xFFFF8A00);

      case 'absent':
        return const Color(0xFFD32F2F);

      case 'excused':
        return const Color(0xFF1976D2);

      default:
        return navy;
    }
  }

  String _sourceName(String value) {
    switch (value.trim().toLowerCase()) {
      case 'mobile_online':
        return 'Mobile';

      case 'mobile_offline':
      case 'mobile_offline_sync':
        return 'Mobile Offline';

      case 'kiosk':
        return 'Kiosk';

      case 'web':
        return 'Web';

      default:
        return value;
    }
  }
}
