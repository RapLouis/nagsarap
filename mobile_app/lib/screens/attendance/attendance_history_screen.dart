import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../main.dart';
import '../../models/attendance_history_item.dart';
import '../../services/attendance_history_service.dart';

enum _HistoryFilter { all, timeIn, timeOut }

class AttendanceHistoryScreen extends StatefulWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  State<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  static const Color brandNavy = Color(0xFF080878);
  static const Color brandGold = Color(0xFFFFC800);
  static const Color muted = Color(0xFF64748B);

  bool _loading = true;
  String? _error;
  List<AttendanceHistoryItem> _records = const [];
  _HistoryFilter _filter = _HistoryFilter.all;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory({bool showLoader = true}) async {
    if (!mounted) return;
    if (showLoader) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    final result = await AttendanceHistoryService.instance.getHistory();
    if (!mounted) return;

    if (!result.success && _records.isEmpty) {
      setState(() {
        _loading = false;
        _error = result.message;
      });
      return;
    }

    setState(() {
      _loading = false;
      if (result.success) {
        _records = result.records;
      }
      _error = null;
    });
  }

  List<AttendanceHistoryItem> get _filteredRecords {
    switch (_filter) {
      case _HistoryFilter.timeIn:
        return _records.where((r) => r.sessionType == 'time_in').toList();
      case _HistoryFilter.timeOut:
        return _records.where((r) => r.sessionType == 'time_out').toList();
      case _HistoryFilter.all:
        return _records;
    }
  }

  int get _timeInCount =>
      _records.where((r) => r.sessionType == 'time_in').length;

  int get _timeOutCount =>
      _records.where((r) => r.sessionType == 'time_out').length;

  void _selectFilter(_HistoryFilter next) {
    if (_filter == next) return;
    HapticFeedback.selectionClick();
    setState(() => _filter = next);
  }

  DateTime? _resolveDate(AttendanceHistoryItem item) {
    if (item.eventDate != null) {
      final parsed = DateTime.tryParse(item.eventDate!);
      if (parsed != null) return parsed;
    }
    return item.loggedAt?.toLocal();
  }

  String _formatShortDate(AttendanceHistoryItem item) {
    final dt = _resolveDate(item);
    if (dt == null) return item.eventDate ?? '';
    return DateFormat('MMM d, yyyy').format(dt);
  }

  String _formatFullDate(AttendanceHistoryItem item) {
    final dt = _resolveDate(item);
    if (dt == null) return item.eventDate ?? 'N/A';
    return DateFormat('MMMM d, yyyy').format(dt);
  }

  String _formatTime(AttendanceHistoryItem item) {
    final dt = item.loggedAt?.toLocal();
    if (dt != null) {
      return DateFormat('h:mm a').format(dt);
    }
    return item.attendanceTime ?? 'Recorded';
  }

  String _formatSource(String? rawSource) {
    if (rawSource == null || rawSource.trim().isEmpty) {
      return 'Mobile Verification';
    }
    switch (rawSource.trim().toLowerCase()) {
      case 'mobile_online':
        return 'Online Verification';
      case 'mobile_offline':
      case 'offline_sync':
        return 'Offline Synced';
      case 'kiosk':
      case 'scanner':
        return 'Campus Scanner';
      default:
        return rawSource
            .replaceAll('_', ' ')
            .split(' ')
            .where((w) => w.isNotEmpty)
            .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
            .join(' ');
    }
  }

  double _confidencePercent(double score) {
    if (score <= 1.0) return (score * 100).clamp(0.0, 100.0);
    return score.clamp(0.0, 100.0);
  }

  String _formatAccuracy(double accuracy) {
    final meters = accuracy.toStringAsFixed(1);
    if (accuracy <= 25) return '$meters m (High precision)';
    if (accuracy <= 100) return '$meters m (Within geofence)';
    return '$meters m';
  }

  BoxDecoration _cardDecoration(
    bool isDark, {
    Color? borderColor,
    double borderWidth = 1.0,
    Color? backgroundColor,
  }) {
    return BoxDecoration(
      color: backgroundColor ?? (isDark ? const Color(0xFF1E293B) : Colors.white),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: borderColor ??
            (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
        width: borderWidth,
      ),
      boxShadow: isDark
          ? null
          : [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
    );
  }

  void _showRecordDetails(AttendanceHistoryItem item) {
    final isDark = themeController.isDarkMode;
    final isTimeOut = item.sessionType == 'time_out';
    final sessionLabel = isTimeOut ? 'Time-Out' : 'Time-In';
    final sessionAccent =
        isTimeOut ? const Color(0xFFD97706) : const Color(0xFF059669);

    final statusUpper = item.status.toUpperCase();
    final isPresent = statusUpper == 'PRESENT' || statusUpper == 'VERIFIED';
    final confidencePct = _confidencePercent(item.confidenceScore);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF475569)
                        : const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.eventName,
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : brandNavy,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isPresent
                                    ? const Color(0xFFDCFCE7)
                                    : const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isPresent
                                        ? Icons.verified_rounded
                                        : Icons.info_outline_rounded,
                                    size: 13,
                                    color: isPresent
                                        ? const Color(0xFF15803D)
                                        : const Color(0xFF92400E),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    statusUpper,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: isPresent
                                          ? const Color(0xFF15803D)
                                          : const Color(0xFF92400E),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: sessionAccent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                sessionLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: sessionAccent,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: Icon(
                      Icons.close_rounded,
                      color: isDark ? Colors.white70 : muted,
                      size: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(
                height: 1,
                color: isDark
                    ? const Color(0xFF334155)
                    : const Color(0xFFE2E8F0),
              ),
              const SizedBox(height: 14),
              if (item.eventDate != null || item.loggedAt != null) ...[
                _buildDetailRow(
                  icon: Icons.calendar_today_rounded,
                  label: 'Event Date',
                  value: _formatFullDate(item),
                  iconColor: isDark ? brandGold : brandNavy,
                ),
                const SizedBox(height: 12),
              ],
              _buildDetailRow(
                icon: Icons.access_time_filled_rounded,
                label: 'Recorded Time',
                value: _formatTime(item),
                iconColor: sessionAccent,
              ),
              if (item.venue != null && item.venue!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildDetailRow(
                  icon: Icons.place_outlined,
                  label: 'Venue',
                  value: item.venue!,
                  iconColor: const Color(0xFF2563EB),
                ),
              ],
              if (item.locationAccuracy != null) ...[
                const SizedBox(height: 12),
                _buildDetailRow(
                  icon: Icons.my_location_rounded,
                  label: 'GPS Accuracy',
                  value: _formatAccuracy(item.locationAccuracy!),
                  iconColor: const Color(0xFF0284C7),
                ),
              ],
              if (item.source != null) ...[
                const SizedBox(height: 12),
                _buildDetailRow(
                  icon: Icons.smartphone_rounded,
                  label: 'Check-in Method',
                  value: _formatSource(item.source),
                  iconColor: const Color(0xFF7C3AED),
                ),
              ],
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0F172A)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.face_retouching_natural_rounded,
                              size: 16,
                              color: Color(0xFF059669),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Face Match Confidence',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? const Color(0xFFCBD5E1)
                                    : const Color(0xFF334155),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${confidencePct.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : brandNavy,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: (confidencePct / 100.0).clamp(0.0, 1.0),
                        minHeight: 6,
                        backgroundColor: isDark
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFE2E8F0),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF10B981),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark ? brandGold : brandNavy,
                    foregroundColor: isDark ? brandNavy : Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Close',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    required Color iconColor,
  }) {
    final isDark = themeController.isDarkMode;

    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 17, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: muted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeController.isDarkMode;
    final items = _filteredRecords;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0F172A) : const Color(0xFFF4F6FA),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E293B) : brandNavy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Attendance History',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
      ),
      body: RefreshIndicator(
        color: brandGold,
        onRefresh: () => _fetchHistory(showLoader: false),
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: brandGold))
            : _error != null
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: _cardDecoration(isDark),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              color: Colors.redAccent,
                              size: 32,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: isDark ? Colors.white70 : muted,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 14),
                            ElevatedButton(
                              onPressed: _fetchHistory,
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    isDark ? brandGold : brandNavy,
                                foregroundColor:
                                    isDark ? brandNavy : Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text(
                                'Retry',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : _records.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(20),
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 36,
                              horizontal: 20,
                            ),
                            decoration: _cardDecoration(isDark),
                            child: Column(
                              children: [
                                Container(
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    color: (isDark ? brandGold : brandNavy)
                                        .withValues(alpha: 0.08),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.history_rounded,
                                    size: 26,
                                    color: isDark ? brandGold : brandNavy,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No attendance records found.',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? Colors.white : brandNavy,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Your verified Time-In and Time-Out logs will appear here.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 12.5, color: muted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                        children: [
                          _buildIndividualStatCards(isDark),
                          const SizedBox(height: 14),
                          if (items.isEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 28,
                                horizontal: 16,
                              ),
                              decoration: _cardDecoration(isDark),
                              child: Center(
                                child: Text(
                                  'No ${_filter == _HistoryFilter.timeIn ? "Time-In" : "Time-Out"} records found.',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: muted,
                                  ),
                                ),
                              ),
                            )
                          else
                            ...items.map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _buildRecordCard(item, isDark),
                              ),
                            ),
                        ],
                      ),
      ),
    );
  }

  Widget _buildIndividualStatCards(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: _individualStatCard(
            label: 'Total Logs',
            value: '${_records.length}',
            accent: isDark ? brandGold : brandNavy,
            selected: _filter == _HistoryFilter.all,
            isDark: isDark,
            onTap: () => _selectFilter(_HistoryFilter.all),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _individualStatCard(
            label: 'Time-In',
            value: '$_timeInCount',
            accent: const Color(0xFF059669),
            selected: _filter == _HistoryFilter.timeIn,
            isDark: isDark,
            onTap: () => _selectFilter(_HistoryFilter.timeIn),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _individualStatCard(
            label: 'Time-Out',
            value: '$_timeOutCount',
            accent: const Color(0xFFD97706),
            selected: _filter == _HistoryFilter.timeOut,
            isDark: isDark,
            onTap: () => _selectFilter(_HistoryFilter.timeOut),
          ),
        ),
      ],
    );
  }

  Widget _individualStatCard({
    required String label,
    required String value,
    required Color accent,
    required bool selected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final baseBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final activeBg = Color.alphaBlend(
      accent.withValues(alpha: isDark ? 0.16 : 0.06),
      baseBg,
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: _cardDecoration(
        isDark,
        backgroundColor: selected ? activeBg : baseBg,
        borderColor: selected ? accent : null,
        borderWidth: selected ? 1.6 : 1.0,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected
                        ? (isDark ? Colors.white : accent)
                        : (isDark ? const Color(0xFF94A3B8) : muted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecordCard(AttendanceHistoryItem item, bool isDark) {
    final isTimeOut = item.sessionType == 'time_out';
    final sessionAccent =
        isTimeOut ? const Color(0xFFD97706) : const Color(0xFF059669);
    final sessionBg = isTimeOut
        ? (isDark ? const Color(0xFF422006) : const Color(0xFFFEF3C7))
        : (isDark ? const Color(0xFF064E3B) : const Color(0xFFDCFCE7));
    final sessionLabel = isTimeOut ? 'Time-Out' : 'Time-In';

    final statusUpper = item.status.toUpperCase();
    final isPresent = statusUpper == 'PRESENT' || statusUpper == 'VERIFIED';

    final dateText = _formatShortDate(item);
    final timeText = _formatTime(item);
    final subtitleText =
        dateText.isNotEmpty ? '$timeText • $dateText' : timeText;

    return Container(
      decoration: _cardDecoration(isDark),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showRecordDetails(item),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: sessionBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isTimeOut ? Icons.logout_rounded : Icons.login_rounded,
                    color: sessionAccent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.eventName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : brandNavy,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2.5,
                            ),
                            decoration: BoxDecoration(
                              color: isPresent
                                  ? (isDark
                                      ? const Color(0xFF064E3B)
                                      : const Color(0xFFDCFCE7))
                                  : (isDark
                                      ? const Color(0xFF451A03)
                                      : const Color(0xFFFEF3C7)),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              statusUpper,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                                color: isPresent
                                    ? (isDark
                                        ? const Color(0xFF6EE7B7)
                                        : const Color(0xFF15803D))
                                    : (isDark
                                        ? const Color(0xFFFCD34D)
                                        : const Color(0xFF92400E)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: sessionBg,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              sessionLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: sessionAccent,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.access_time_rounded,
                            size: 13,
                            color: isDark ? const Color(0xFF94A3B8) : muted,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              subtitleText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isDark
                                    ? const Color(0xFFCBD5E1)
                                    : const Color(0xFF475569),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (item.venue != null && item.venue!.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            const Icon(
                              Icons.place_outlined,
                              size: 13,
                              color: Color(0xFF2563EB),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                item.venue!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: isDark
                                      ? const Color(0xFF94A3B8)
                                      : muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: isDark ? Colors.white54 : const Color(0xFF94A3B8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}