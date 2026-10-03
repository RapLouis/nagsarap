import 'package:flutter/material.dart';

import '../../models/attendance_history_item.dart';
import '../../services/attendance_history_service.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  State<AttendanceHistoryScreen> createState() => _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  static const Color brandNavy = Color(0xFF1B1F5C);
  static const Color brandGold = Color(0xFFC9973E);
  static const Color bgLight = Color(0xFFF9FAFB);

  bool _loading = true;
  String? _error;
  List<AttendanceHistoryItem> _records = const [];

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await AttendanceHistoryService.instance.getHistory();
    if (!mounted) return;

    if (!result.success) {
      setState(() {
        _loading = false;
        _error = result.message;
      });
      return;
    }

    setState(() {
      _loading = false;
      _records = result.records;
      _error = null;
    });
  }

  void _showRecordDetails(AttendanceHistoryItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          item.eventName,
          style: const TextStyle(fontWeight: FontWeight.bold, color: brandNavy),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Status', item.status.toUpperCase()),
            const SizedBox(height: 8),
            _buildDetailRow('Session', item.sessionType == 'time_out' ? 'Time-Out' : 'Time-In'),
            const SizedBox(height: 8),
            _buildDetailRow('Recorded Time', item.attendanceTime ?? 'N/A'),
            if (item.eventDate != null) ...[
              const SizedBox(height: 8),
              _buildDetailRow('Event Date', item.eventDate!),
            ],
            if (item.venue != null) ...[
              const SizedBox(height: 8),
              _buildDetailRow('Venue', item.venue!),
            ],
            if (item.locationAccuracy != null) ...[
              const SizedBox(height: 8),
              _buildDetailRow('GPS Accuracy', '${item.locationAccuracy!.toStringAsFixed(1)} m'),
            ],
            if (item.source != null) ...[
              const SizedBox(height: 8),
              _buildDetailRow('Check-in Method', item.source!),
            ],
            const SizedBox(height: 8),
            _buildDetailRow('Confidence Score', '${(item.confidenceScore * 100).toStringAsFixed(1)}%'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close', style: TextStyle(color: brandNavy, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.grey, fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, color: brandNavy, fontSize: 13),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgLight,
      appBar: AppBar(
        backgroundColor: brandNavy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Attendance History',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      body: RefreshIndicator(
        color: brandNavy,
        onRefresh: _fetchHistory,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: brandNavy))
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _fetchHistory,
                          style: ElevatedButton.styleFrom(backgroundColor: brandNavy),
                          child: const Text('Retry', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  )
                : _records.isEmpty
                    ? const Center(child: Text('No attendance records found.'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _records.length,
                        itemBuilder: (context, index) {
                          final item = _records[index];
                          final isTimeOut = item.sessionType == 'time_out';

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              onTap: () => _showRecordDetails(item),
                              leading: CircleAvatar(
                                backgroundColor: isTimeOut
                                    ? brandGold.withValues(alpha: 0.15)
                                    : const Color(0xFF10B981).withValues(alpha: 0.15),
                                child: Icon(
                                  isTimeOut ? Icons.logout_rounded : Icons.check_circle_rounded,
                                  color: isTimeOut ? brandGold : const Color(0xFF10B981),
                                ),
                              ),
                              title: Text(
                                item.eventName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: brandNavy,
                                ),
                              ),
                              subtitle: Text(
                                '${isTimeOut ? "Time-Out" : "Time-In"} • ${item.attendanceTime ?? "Recorded"}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: const Icon(
                                Icons.chevron_right_rounded,
                                color: Colors.grey,
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}