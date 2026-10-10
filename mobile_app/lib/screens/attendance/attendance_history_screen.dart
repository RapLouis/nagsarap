import 'package:flutter/material.dart';

import '../../main.dart';
import '../../models/attendance_history_item.dart';
import '../../services/attendance_history_service.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  State<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  static const Color brandNavy = Color(0xFF080878);
  static const Color brandGold = Color(0xFFFFC800);
  static const Color muted = Color(0xFF94A3B8);

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
    final isDark = themeController.isDarkMode;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          item.eventName,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : brandNavy,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Status', item.status.toUpperCase()),
            const SizedBox(height: 8),
            _buildDetailRow(
              'Session',
              item.sessionType == 'time_out' ? 'Time-Out' : 'Time-In',
            ),
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
              _buildDetailRow(
                'GPS Accuracy',
                '${item.locationAccuracy!.toStringAsFixed(1)} m',
              ),
            ],
            if (item.source != null) ...[
              const SizedBox(height: 8),
              _buildDetailRow('Check-in Method', item.source!),
            ],
            const SizedBox(height: 8),
            _buildDetailRow(
              'Confidence Score',
              '${(item.confidenceScore * 100).toStringAsFixed(1)}%',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Close',
              style: TextStyle(
                color: isDark ? brandGold : brandNavy,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    final isDark = themeController.isDarkMode;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: muted,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : brandNavy,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeController.isDarkMode;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E293B) : brandNavy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Attendance History',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      body: RefreshIndicator(
        color: brandGold,
        onRefresh: _fetchHistory,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: brandGold))
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _fetchHistory,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark ? brandGold : brandNavy,
                            foregroundColor: isDark ? brandNavy : Colors.white,
                          ),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : _records.isEmpty
                    ? Center(
                        child: Text(
                          'No attendance records found.',
                          style: TextStyle(
                            color: isDark ? Colors.white70 : muted,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _records.length,
                        itemBuilder: (context, index) {
                          final item = _records[index];
                          final isTimeOut = item.sessionType == 'time_out';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF1E293B)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isDark
                                    ? const Color(0xFF334155)
                                    : const Color(0xFFE2E8F0),
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x06000000),
                                  blurRadius: 8,
                                  offset: Offset(0, 3),
                                ),
                              ],
                            ),
                            child: ListTile(
                              onTap: () => _showRecordDetails(item),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              leading: CircleAvatar(
                                backgroundColor: isTimeOut
                                    ? brandGold.withValues(alpha: 0.15)
                                    : const Color(0xFF10B981)
                                        .withValues(alpha: 0.15),
                                child: Icon(
                                  isTimeOut
                                      ? Icons.logout_rounded
                                      : Icons.check_circle_rounded,
                                  color: isTimeOut
                                      ? brandGold
                                      : const Color(0xFF10B981),
                                ),
                              ),
                              title: Text(
                                item.eventName,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : brandNavy,
                                  fontSize: 15,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '${isTimeOut ? "Time-Out" : "Time-In"} • ${item.attendanceTime ?? "Recorded"}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: muted,
                                  ),
                                ),
                              ),
                              trailing: Icon(
                                Icons.chevron_right_rounded,
                                color: isDark ? Colors.white54 : Colors.grey,
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}