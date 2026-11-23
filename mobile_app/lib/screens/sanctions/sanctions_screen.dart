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

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  bool _loading = true;
  bool _isSearching = false;
  String? _error;

  List<SanctionItem> _sanctions = const [];
  String _selectedFilter = 'All';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadSanctions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _startSearch() {
    setState(() {
      _isSearching = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  void _stopSearch() {
    setState(() {
      _isSearching = false;
      _searchQuery = '';
      _searchController.clear();
    });
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
          final first = a.eventDate ??
              a.issuedAt ??
              DateTime.fromMillisecondsSinceEpoch(0);

          final second = b.eventDate ??
              b.issuedAt ??
              DateTime.fromMillisecondsSinceEpoch(0);

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
    } catch (error) {
      debugPrint('SANCTIONS SCREEN ERROR: $error');

      if (!mounted) return;

      setState(() {
        _loading = false;
        _sanctions = const [];
        _error = 'Unable to load sanctions.';
      });
    }
  }

  // Filter and group sanctions by event AND event date.
  List<_EventSanctionCard> _getGroupedSanctions() {
    List<SanctionItem> items = _sanctions;

    if (_selectedFilter == 'Pending') {
      items = _sanctions.where((item) => !item.isResolved).toList();
    } else if (_selectedFilter == 'Resolved') {
      items = _sanctions.where((item) => item.isResolved).toList();
    }

    final Map<String, List<SanctionItem>> groups = {};

    for (final item in items) {
      final eventName = _extractEventName(item.title);

      final date = item.eventDate ?? item.issuedAt;

      final dateKey = date == null
          ? 'unknown'
          : '${date.year.toString().padLeft(4, '0')}-'
              '${date.month.toString().padLeft(2, '0')}-'
              '${date.day.toString().padLeft(2, '0')}';

      final identity = item.eventId != null
          ? 'id:${item.eventId}|$dateKey'
          : '${eventName.toLowerCase()}|$dateKey';

      groups.putIfAbsent(identity, () => <SanctionItem>[]).add(item);
    }

    final List<_EventSanctionCard> cards = [];

    for (final groupItems in groups.values) {
      final eventName = _extractEventName(groupItems.first.title);

      DateTime? eventDate;

      for (final item in groupItems) {
        final candidate = item.eventDate ?? item.issuedAt;

        if (candidate != null &&
            (eventDate == null || candidate.isAfter(eventDate))) {
          eventDate = candidate;
        }
      }

      final isResolved = groupItems.every((item) => item.isResolved);

      final Set<String> missedTags = {};

      for (final item in groupItems) {
        if (item.missedPeriod == 'time_in') {
          missedTags.add('TIME-IN MISSED');
        } else if (item.missedPeriod == 'time_out') {
          missedTags.add('TIME-OUT MISSED');
        }
      }

      if (missedTags.isEmpty) {
        missedTags.add('ATTENDANCE MISSED');
      }

      final sortedTags = missedTags.toList()
        ..sort((a, b) {
          if (a.contains('TIME-IN') && b.contains('TIME-OUT')) {
            return -1;
          }

          if (a.contains('TIME-OUT') && b.contains('TIME-IN')) {
            return 1;
          }

          return a.compareTo(b);
        });

      cards.add(
        _EventSanctionCard(
          eventName: eventName,
          date: eventDate,
          isResolved: isResolved,
          missedTags: sortedTags,
        ),
      );
    }

    cards.sort((a, b) {
      final first = a.date ?? DateTime(0);
      final second = b.date ?? DateTime(0);

      return second.compareTo(first);
    });

    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return cards;
    }

    return cards.where((card) {
      final nameMatches = card.eventName.toLowerCase().contains(query);
      final dateStr = card.date == null
          ? 'date unspecified'
          : DateFormat('MMMM d, yyyy MMM d, yyyy')
              .format(card.date!.toLocal())
              .toLowerCase();
      final dateMatches = dateStr.contains(query);
      final tagMatches =
          card.missedTags.any((tag) => tag.toLowerCase().contains(query));

      return nameMatches || dateMatches || tagMatches;
    }).toList();
  }

  String _extractEventName(String title) {
    final trimmed = title.trim();
    final lower = trimmed.toLowerCase();

    const suffixes = [
      ' - time-in missed',
      ' - time-out missed',
      ' - time in missed',
      ' - time out missed',
    ];

    for (final suffix in suffixes) {
      final index = lower.lastIndexOf(suffix);

      if (index >= 0) {
        return trimmed.substring(0, index).trim();
      }
    }

    if (trimmed.contains(' - ')) {
      return trimmed.split(' - ').first.trim();
    }

    if (trimmed.contains(' : ')) {
      return trimmed.split(' : ').first.trim();
    }

    return trimmed;
  }

  int get _pendingCount =>
      _sanctions.where((item) => !item.isResolved).length;

  int get _resolvedCount =>
      _sanctions.where((item) => item.isResolved).length;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        final isDark = themeController.isDarkMode;

        return Scaffold(
          backgroundColor:
              isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
          appBar: AppBar(
            backgroundColor: isDark ? const Color(0xFF1E293B) : navy,
            foregroundColor: Colors.white,
            elevation: 0,
            title: _isSearching
                ? TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    cursorColor: gold,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search event...',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 15,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  )
                : const Text(
                    'Sanctions',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
            actions: [
              if (_isSearching)
                IconButton(
                  tooltip: 'Clear search',
                  onPressed: () {
                    if (_searchController.text.isNotEmpty) {
                      setState(() {
                        _searchController.clear();
                        _searchQuery = '';
                      });
                    } else {
                      _stopSearch();
                    }
                  },
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                )
              else
                IconButton(
                  tooltip: 'Search event',
                  onPressed: _startSearch,
                  icon: const Icon(Icons.search_rounded, color: Colors.white),
                ),
              const SizedBox(width: 4),
            ],
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
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerDocked,
        );
      },
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 180),
          Center(
            child: CircularProgressIndicator(
              color: gold,
            ),
          ),
        ],
      );
    }

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 100),
          _buildErrorCard(),
        ],
      );
    }

    final cards = _getGroupedSanctions();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        16,
        16,
        16,
        110,
      ),
      children: [
        _buildSegmentedFilter(),
        const SizedBox(height: 16),
        if (cards.isEmpty)
          _buildEmptyState()
        else
          ...cards.map(_buildSanctionCard),
      ],
    );
  }

  Widget _buildSegmentedFilter() {
    final isDark = themeController.isDarkMode;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1E293B)
            : const Color(0xFFE2E8F0).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
          width: 1,
        ),
      ),
      child: Row(
        children: ['All', 'Pending', 'Resolved'].map((tab) {
          final selected = _selectedFilter == tab;

          final count = tab == 'All'
              ? _sanctions.length
              : tab == 'Pending'
                  ? _pendingCount
                  : _resolvedCount;

          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedFilter = tab;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  vertical: 9,
                ),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? (isDark ? const Color(0xFF0F172A) : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$tab ($count)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: selected ? (isDark ? Colors.white : navy) : muted,
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
          width: 1,
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
            children:
                card.missedTags.map((tag) => _buildTag(tag, isDark)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPill(bool isResolved) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: isResolved ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isResolved ? 'RESOLVED' : 'PENDING',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color:
              isResolved ? const Color(0xFF15803D) : const Color(0xFFB45309),
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildTag(String tag, bool isDark) {
    late final Color textColor;
    late final Color backgroundColor;

    if (tag.contains('TIME-IN')) {
      textColor = const Color(0xFFB45309);

      backgroundColor =
          isDark ? const Color(0xFF451A03) : const Color(0xFFFEF3C7);
    } else if (tag.contains('TIME-OUT')) {
      textColor = const Color(0xFFC2410C);

      backgroundColor =
          isDark ? const Color(0xFF431407) : const Color(0xFFFFEDD5);
    } else {
      textColor = const Color(0xFF475569);

      backgroundColor =
          isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9);
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
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
    final hasSearch = _searchQuery.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: 48,
        horizontal: 20,
      ),
      alignment: Alignment.center,
      child: Column(
        children: [
          if (hasSearch) ...[
            Icon(
              Icons.search_off_rounded,
              size: 36,
              color: isDark ? Colors.white54 : muted,
            ),
            const SizedBox(height: 10),
          ],
          Text(
            hasSearch ? 'No Matching Events' : 'No Sanctions',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : navy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hasSearch
                ? 'No sanctions matched "${_searchQuery.trim()}".'
                : 'You currently have no recorded attendance sanctions.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: muted,
            ),
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
            style: const TextStyle(
              fontSize: 12,
              color: muted,
            ),
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
            child: const Text(
              'Try Again',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
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

  const _EventSanctionCard({
    required this.eventName,
    required this.date,
    required this.isResolved,
    required this.missedTags,
  });
}