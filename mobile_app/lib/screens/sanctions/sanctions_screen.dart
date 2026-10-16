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
  static const Color muted = Color(0xFF94A3B8);

  static const Color pendingColor = Color(0xFFD97706);
  static const Color resolvedColor = Color(0xFF16A34A);

  bool _loading = true;
  String? _error;

  List<SanctionItem> _sanctions = const [];

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

  @override
  Widget build(BuildContext context) {
    final isDark = themeController.isDarkMode;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E293B) : navy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Sanctions',
          style: TextStyle(fontWeight: FontWeight.w700),
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
        children: [const SizedBox(height: 100), _buildError()],
      );
    }

    if (_sanctions.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [const SizedBox(height: 100), _buildEmpty()],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 110),
      itemCount: _sanctions.length + 1,
      itemBuilder: (BuildContext context, int index) {
        if (index == 0) return _buildTableHeader();
        final sanction = _sanctions[index - 1];
        return _buildTableRow(sanction, index - 1);
      },
    );
  }

  Widget _buildTableHeader() {
    final isDark = themeController.isDarkMode;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEDEDF8),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E2E8),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(
              'Date',
              style: TextStyle(
                color: isDark ? gold : navy,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              'Attendance issue',
              style: TextStyle(
                color: isDark ? gold : navy,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          SizedBox(
            width: 72,
            child: Text(
              'Status',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: isDark ? gold : navy,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableRow(SanctionItem sanction, int index) {
    final isDark = themeController.isDarkMode;
    final resolved = sanction.isResolved;
    final statusColor = resolved ? resolvedColor : pendingColor;

    final dateText = sanction.issuedAt == null
        ? '--'
        : DateFormat('MMM d, yyyy').format(sanction.issuedAt!.toLocal());

    String title = sanction.title.trim();
    if (title.isEmpty) title = 'Attendance issue';

    final rowColor = isDark
        ? (index.isEven ? const Color(0xFF0F172A) : const Color(0xFF1E293B))
        : (index.isEven ? Colors.white : const Color(0xFFFAFAFC));

    final borderColor =
        isDark ? const Color(0xFF334155) : const Color(0xFFE2E2E8);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      decoration: BoxDecoration(
        color: rowColor,
        border: Border(
          left: BorderSide(color: borderColor),
          right: BorderSide(color: borderColor),
          bottom: BorderSide(color: borderColor),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Text(
              dateText,
              style: const TextStyle(
                color: muted,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isDark ? Colors.white : navy,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 72,
            child: Align(
              alignment: Alignment.topRight,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  resolved ? 'Resolved' : 'Pending',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    final isDark = themeController.isDarkMode;

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E2E8),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.event_available_rounded,
            color: isDark ? gold : navy,
            size: 45,
          ),
          const SizedBox(height: 12),
          Text(
            'No attendance issues',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'You currently have no recorded attendance issues.',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    final isDark = themeController.isDarkMode;

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 44),
          const SizedBox(height: 12),
          Text(
            'Unable to load attendance issues',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            _error ?? 'Please try again.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted, fontSize: 13),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _loadSanctions,
            style: FilledButton.styleFrom(
              backgroundColor: isDark ? gold : navy,
              foregroundColor: isDark ? navy : Colors.white,
            ),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }
}