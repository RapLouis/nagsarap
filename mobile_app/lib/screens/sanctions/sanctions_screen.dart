import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../main.dart';
import '../../models/sanction_item.dart';
import '../../services/sanction_service.dart';
import '../../widgets/main_bottom_navigation.dart';

class SanctionsScreen extends StatefulWidget {
  const SanctionsScreen({super.key});

  @override
  State<SanctionsScreen> createState() => _SanctionsScreenState();
}

class _SanctionsScreenState extends State<SanctionsScreen> {
  static const Color navy = Color(0xFF080878);
  static const Color gold = Color(0xFFFFC800);
  static const Color muted = Color(0xFF64748B);

  bool _loading = true;
  String? _error;

  List<SanctionItem> _sanctions = const [];
  String _selectedFilter = 'All'; // 'All', 'Pending', 'Resolved'

  @override
  void initState() {
    super.initState();
    _loadSanctions();
  }

  Future<void> _loadSanctions() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final result = await SanctionService.instance.getSanctions();

      if (!mounted) return;

      if (result.success) {
        final sorted = List<SanctionItem>.from(result.sanctions);

        // Sort descending: Latest/newest missed events on top
        sorted.sort((a, b) {
          final first = a.issuedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final second = b.issuedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return second.compareTo(first);
        });

        setState(() {
          _loading = false;
          _sanctions = sorted;
          _error = null;
        });
      } else {
        setState(() {
          _loading = false;
          _sanctions = const [];
          _error = result.message;
        });
      }
    } catch (e) {
      debugPrint('SANCTIONS SCREEN ERROR: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _sanctions = const [];
        _error = 'Unable to load attendance issues.';
      });
    }
  }

  int get _pendingCount => _sanctions.where((s) => !s.isResolved).length;
  int get _resolvedCount => _sanctions.where((s) => s.isResolved).length;

  List<SanctionItem> get _filteredSanctions {
    if (_selectedFilter == 'Pending') {
      return _sanctions.where((s) => !s.isResolved).toList();
    } else if (_selectedFilter == 'Resolved') {
      return _sanctions.where((s) => s.isResolved).toList();
    }
    return _sanctions;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeController.isDarkMode;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : navy,
            border: Border(
              bottom: BorderSide(
                color: isDark ? const Color(0xFF334155) : const Color(0xFF0F172A).withValues(alpha: 0.1),
              ),
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: const Text(
                  'Sanctions Monitoring Table',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        color: gold,
        onRefresh: _loadSanctions,
        child: _buildBody(),
      ),
      bottomNavigationBar: const MainBottomNavigation(currentIndex: 3),
      floatingActionButton: MainBottomNavigation.scannerButton(
        context,
        currentIndex: 3,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 180),
          Center(child: CircularProgressIndicator(color: gold)),
        ],
      );
    }

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [const SizedBox(height: 100), _buildErrorCard()],
      );
    }

    final filtered = _filteredSanctions;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
      children: [
        _buildSegmentedFilter(),
        const SizedBox(height: 16),
        if (filtered.isEmpty)
          _buildEmptyState()
        else
          ...filtered.map((sanction) => _buildSanctionCard(sanction)),
      ],
    );
  }

  Widget _buildSegmentedFilter() {
    final isDark = themeController.isDarkMode;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
          width: 1.0,
        ),
      ),
      child: Row(
        children: ['All', 'Pending', 'Resolved'].map((tab) {
          final isSelected = _selectedFilter == tab;
          final count = tab == 'All'
              ? _sanctions.length
              : (tab == 'Pending' ? _pendingCount : _resolvedCount);

          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedFilter = tab),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isDark ? const Color(0xFF0F172A) : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          )
                        ]
                      : null,
                ),
                child: Text(
                  '$tab ($count)',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? (isDark ? Colors.white : navy)
                        : muted,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSanctionCard(SanctionItem sanction) {
    final isDark = themeController.isDarkMode;
    final issueInfo = _parseIssueInfo(sanction);

    final dateText = sanction.issuedAt == null
        ? 'Date Unspecified'
        : DateFormat('MMM d, yyyy').format(sanction.issuedAt!.toLocal());

    final timeText = sanction.issuedAt == null
        ? ''
        : DateFormat('h:mm a').format(sanction.issuedAt!.toLocal());

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: sanction.isResolved
              ? (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0))
              : issueInfo.color.withValues(alpha: 0.4),
          width: sanction.isResolved ? 1.0 : 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // TOP ROW: EVENT NAME + RESOLVED/PENDING STATUS
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    issueInfo.eventName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : navy,
                      height: 1.2,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _buildStatusPill(sanction.isResolved, isDark),
              ],
            ),

            const SizedBox(height: 10),

            // MIDDLE ROW: ISSUE TYPE BADGE + DATE
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: issueInfo.color.withValues(alpha: isDark ? 0.2 : 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: issueInfo.color.withValues(alpha: 0.3),
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(issueInfo.icon, size: 13, color: issueInfo.color),
                      const SizedBox(width: 5),
                      Text(
                        issueInfo.issueLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                          color: issueInfo.color,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded, size: 11, color: muted),
                    const SizedBox(width: 4),
                    Text(
                      timeText.isNotEmpty ? '$dateText • $timeText' : dateText,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusPill(bool isResolved, bool isDark) {
    if (isResolved) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
        decoration: BoxDecoration(
          color: const Color(0xFFDCFCE7),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'RESOLVED',
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            color: Color(0xFF15803D),
            letterSpacing: 0.3,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'PENDING',
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          color: Color(0xFFB45309),
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // SMART ISSUE PARSER & FORMATTER
  // --------------------------------------------------------------------------

  _ParsedIssue _parseIssueInfo(SanctionItem sanction) {
    final rawTitle = sanction.title.trim();
    String eventName = rawTitle;
    String lower = rawTitle.toLowerCase();

    // Extract Event Name if formatted as "Event Name - Issue Type" or "Event Name : Issue Type"
    if (rawTitle.contains(' - ')) {
      final parts = rawTitle.split(' - ');
      eventName = parts[0].trim();
      lower = parts.sublist(1).join(' ').toLowerCase();
    } else if (rawTitle.contains(' : ')) {
      final parts = rawTitle.split(' : ');
      eventName = parts[0].trim();
      lower = parts.sublist(1).join(' ').toLowerCase();
    }

    final isNoAttendance = lower.contains('no attendance') ||
        lower.contains('absent') ||
        lower.contains('both missed') ||
        (lower.contains('time-in') && lower.contains('time-out')) ||
        (lower.contains('time in') && lower.contains('time out'));

    final isTimeInMissed = lower.contains('time-in') || lower.contains('time in');
    final isTimeOutMissed = lower.contains('time-out') || lower.contains('time out');

    if (isNoAttendance) {
      return _ParsedIssue(
        eventName: eventName.isEmpty ? 'Scheduled Event' : eventName,
        issueLabel: 'NO ATTENDANCE RECORDED',
        color: const Color(0xFFDC2626), // Crimson Red
        icon: Icons.event_busy_rounded,
      );
    } else if (isTimeInMissed) {
      return _ParsedIssue(
        eventName: eventName.isEmpty ? 'Scheduled Event' : eventName,
        issueLabel: 'TIME-IN MISSED',
        color: const Color(0xFFD97706), // Amber
        icon: Icons.login_rounded,
      );
    } else if (isTimeOutMissed) {
      return _ParsedIssue(
        eventName: eventName.isEmpty ? 'Scheduled Event' : eventName,
        issueLabel: 'TIME-OUT MISSED',
        color: const Color(0xFFEA580C), // Orange
        icon: Icons.logout_rounded,
      );
    }

    return _ParsedIssue(
      eventName: eventName.isEmpty ? 'Scheduled Event' : eventName,
      issueLabel: rawTitle.toUpperCase(),
      color: const Color(0xFF475569), // Slate
      icon: Icons.warning_amber_rounded,
    );
  }

  Widget _buildEmptyState() {
    final isDark = themeController.isDarkMode;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
      alignment: Alignment.center,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_circle_outline_rounded,
              size: 36,
              color: const Color(0xFF16A34A).withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'No attendance issues',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : navy,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'You currently have no recorded attendance sanctions or warnings.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: muted),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    final isDark = themeController.isDarkMode;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 30),
          const SizedBox(height: 8),
          Text(
            _error ?? 'Unable to load attendance issues.',
            style: const TextStyle(fontSize: 12, color: muted),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _loadSanctions,
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? gold : navy,
              foregroundColor: isDark ? navy : Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: const Text('Try Again', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _ParsedIssue {
  final String eventName;
  final String issueLabel;
  final Color color;
  final IconData icon;

  const _ParsedIssue({
    required this.eventName,
    required this.issueLabel,
    required this.color,
    required this.icon,
  });
}