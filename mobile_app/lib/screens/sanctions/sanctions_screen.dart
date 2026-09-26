import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

  static const Color background = Color(0xFFF6F6F6);

  static const Color muted = Color(0xFF777783);

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

      if (!mounted) {
        return;
      }

      if (result.success) {
        final sorted = List<SanctionItem>.from(result.sanctions);

        /*
         * Oldest to newest.
         * This makes the attendance issues increase
         * naturally over time.
         */
        sorted.sort((a, b) {
          final first = a.issuedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

          final second = b.issuedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

          return first.compareTo(second);
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

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _sanctions = const [];
        _error = 'Unable to load attendance issues.';
      });
    }
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
          'Sanctions',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),

      body: RefreshIndicator(
        color: navy,
        onRefresh: _loadSanctions,

        child: _buildBody(),
      ),
      bottomNavigationBar: const MainBottomNavigation(currentIndex: 3),
      floatingActionButton: MainBottomNavigation.scannerButton(context),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),

        children: const [
          SizedBox(height: 180),

          Center(child: CircularProgressIndicator(color: navy)),
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
        if (index == 0) {
          return _buildTableHeader();
        }

        final sanction = _sanctions[index - 1];

        return _buildTableRow(sanction, index - 1);
      },
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),

      decoration: const BoxDecoration(
        color: Color(0xFFEDEDF8),

        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),

      child: const Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(
              'Date',
              style: TextStyle(
                color: navy,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),

          Expanded(
            child: Text(
              'Attendance issue',
              style: TextStyle(
                color: navy,
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
                color: navy,
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
    final resolved = sanction.isResolved;

    final statusColor = resolved ? resolvedColor : pendingColor;

    final dateText = sanction.issuedAt == null
        ? '--'
        : DateFormat('MMM d, yyyy').format(sanction.issuedAt!.toLocal());

    String title = sanction.title.trim();

    if (title.isEmpty) {
      title = 'Attendance issue';
    }

    String reason = sanction.reason.trim();

    if (reason.isEmpty) {
      reason = 'Attendance was not recorded for the scheduled activity.';
    }

    /*
     * Slightly alternate the background to make a long
     * table easier to scan without creating large cards.
     */
    final rowColor = index.isEven ? Colors.white : const Color(0xFFFAFAFC);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),

      decoration: BoxDecoration(
        color: rowColor,

        border: const Border(
          left: BorderSide(color: Color(0xFFE2E2E8)),
          right: BorderSide(color: Color(0xFFE2E2E8)),
          bottom: BorderSide(color: Color(0xFFE2E2E8)),
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

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  Text(
                    title,

                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,

                    style: const TextStyle(
                      color: navy,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    reason,

                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,

                    style: const TextStyle(
                      color: muted,
                      fontSize: 10.5,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          ),

          SizedBox(
            width: 72,

            child: Align(
              alignment: Alignment.topRight,

              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),

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
    return Container(
      padding: const EdgeInsets.all(28),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(18),

        border: Border.all(color: const Color(0xFFE2E2E8)),
      ),

      child: const Column(
        children: [
          Icon(Icons.event_available_rounded, color: navy, size: 45),

          SizedBox(height: 12),

          Text(
            'No attendance issues',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),

          SizedBox(height: 7),

          Text(
            'You currently have no recorded attendance issues.',
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
          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 44),

          const SizedBox(height: 12),

          const Text(
            'Unable to load attendance issues',
            textAlign: TextAlign.center,

            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
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
              backgroundColor: navy,
              foregroundColor: Colors.white,
            ),

            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }
}
