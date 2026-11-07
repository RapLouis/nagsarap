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
  String _selectedFilter = 'All';

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

        sorted.sort((a, b) {
          final first = a.eventDate ?? a.issuedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final second = b.eventDate ?? b.issuedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
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
        _error = 'Unable to load sanctions.';
      });
    }
  }

  List<_EventSanctionCard> _getGroupedSanctions() {
    List<SanctionItem> items = _sanctions;
    if (_selectedFilter == 'Pending') {
      items = _sanctions.where((s) => !s.isResolved).toList();
    } else if (_selectedFilter == 'Resolved') {
      items = _sanctions.where((s) => s.isResolved).toList();
    }

    final Map<String, List<SanctionItem>> eventMap = {};
    for (final item in items) {
      final eventName = _extractEventName(item.title);
      eventMap.putIfAbsent(eventName, () => []).add(item);
    }

    final List<_EventSanctionCard> cards = [];

    eventMap.forEach((eventName, groupItems) {
      DateTime? eventDate;
      for (final item in groupItems) {
        final candidate = item.eventDate ?? item.issuedAt;
        if (candidate != null) {
          if (eventDate == null || candidate.isAfter(eventDate!)) {
            eventDate = candidate;
          }
        }
      }

      final isResolved = groupItems.every((i) => i.isResolved);
      final Set<String> missedTags = {};

      for (final item in groupItems) {
        final lower = item.title.toLowerCase();
        if (lower.contains('time-in') || lower.contains('time in')) {
          missedTags.add('TIME-IN MISSED');
        }
        if (lower.contains('time-out') || lower.contains('time out')) {
          missedTags.add('TIME-OUT MISSED');
        }
        if (missedTags.isEmpty) {
          missedTags.add('ATTENDANCE MISSED');
        }
      }

      final sortedTags = missedTags.toList()
        ..sort((a, b) {
          if (a.contains('TIME-IN') && b.contains('TIME-OUT')) return -1;
          if (a.contains('TIME-OUT') && b.contains('TIME-IN')) return 1;
          return a.compareTo(b);
        });

      cards.add(_EventSanctionCard(
        eventName: eventName,
        date: eventDate,
        isResolved: isResolved,
        missedTags: sortedTags,
      ));
    });

    cards.sort((a, b) {
      final d1 = a.date ?? DateTime(0);
      final d2 = b.date ?? DateTime(0);
      return d2.compareTo(d1);
    });

    return cards;
  }

  String _extractEventName(String title) {
    final trimmed = title.trim();
    if (trimmed.contains(' - ')) {
      return trimmed.split(' - ')[0].trim();
    }
    if (trimmed.contains(' : ')) {
      return trimmed.split(' : ')[0].trim();
    }
    return trimmed;
  }

  int get _pendingCount => _sanctions.where((s) => !s.isResolved).length;
  int get _resolvedCount => _sanctions.where((s) => s.isResolved).length;

  @override
  Widget build(BuildContext context) {
    final isDark = themeController.isDarkMode;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E293B) : navy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Sanctions',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
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

    final cards = _getGroupedSanctions();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
      children: [
        _buildSegmentedFilter(),
        const SizedBox(height: 16),
        if (cards.isEmpty)
          _buildEmptyState()
        else
          ...cards.map((card) => _buildSanctionCard(card)),
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
                padding: const EdgeInsets.symmetric(vertical: 9),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isDark ? const Color(0xFF0F172A) : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$tab ($count)',
                  style: TextStyle(
                    fontSize: 12,
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

  Widget _buildSanctionCard(_EventSanctionCard card) {
    final isDark = themeController.isDarkMode;

    final dateText = card.date == null
        ? 'Date Unspecified'
        : DateFormat('MMM d, yyyy').format(card.date!.toLocal());

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  card.eventName,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : navy,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buildStatusPill(card.isResolved),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            dateText,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: muted,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: card.missedTags.map((tag) => _buildTag(tag, isDark)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPill(bool isResolved) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isResolved ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isResolved ? 'RESOLVED' : 'PENDING',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: isResolved ? const Color(0xFF15803D) : const Color(0xFFB45309),
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildTag(String tag, bool isDark) {
    Color textColor;
    Color bgColor;

    if (tag.contains('TIME-IN')) {
      textColor = const Color(0xFFB45309);
      bgColor = isDark ? const Color(0xFF451A03) : const Color(0xFFFEF3C7);
    } else if (tag.contains('TIME-OUT')) {
      textColor = const Color(0xFFC2410C);
      bgColor = isDark ? const Color(0xFF431407) : const Color(0xFFFFEDD5);
    } else {
      textColor = const Color(0xFF475569);
      bgColor = isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        tag,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: textColor,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final isDark = themeController.isDarkMode;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
      alignment: Alignment.center,
      child: Column(
        children: [
          Text(
            'No Sanctions',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : navy,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'You currently have no recorded attendance sanctions.',
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
          Text(
            _error ?? 'Unable to load sanctions.',
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

class _EventSanctionCard {
  final String eventName;
  final DateTime? date;
  final bool isResolved;
  final List<String> missedTags;

  _EventSanctionCard({
    required this.eventName,
    required this.date,
    required this.isResolved,
    required this.missedTags,
  });
}