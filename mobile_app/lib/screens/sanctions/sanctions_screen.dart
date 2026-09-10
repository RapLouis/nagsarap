import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/sanction_item.dart';
import '../../services/sanction_service.dart';

class SanctionsScreen extends StatefulWidget {
  const SanctionsScreen({super.key});

  @override
  State<SanctionsScreen> createState() => _SanctionsScreenState();
}

class _SanctionsScreenState extends State<SanctionsScreen> {
  static const Color navy = Color(0xFF080878);

  static const Color background = Color(0xFFF6F6F6);

  static const Color muted = Color(0xFF777783);

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

    final result = await SanctionService.instance.getSanctions();

    if (!mounted) {
      return;
    }

    setState(() {
      _loading = false;

      if (result.success) {
        _sanctions = result.sanctions;
        _error = null;
      } else {
        _sanctions = const [];
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
          'Sanctions',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: RefreshIndicator(
        color: navy,
        onRefresh: _loadSanctions,
        child: _buildBody(),
      ),
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

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 30),
      itemCount: _sanctions.length,
      separatorBuilder: (BuildContext context, int index) =>
          const SizedBox(height: 14),
      itemBuilder: (BuildContext context, int index) {
        return _buildSanctionCard(_sanctions[index]);
      },
    );
  }

  Widget _buildSanctionCard(SanctionItem sanction) {
    final resolved = sanction.isResolved;

    final statusColor = resolved
        ? const Color(0xFF159947)
        : const Color(0xFFD97706);

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
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: resolved
                      ? const Color(0xFFE8F6EC)
                      : const Color(0xFFFFF3CD),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  resolved
                      ? Icons.check_circle_outline_rounded
                      : Icons.warning_amber_rounded,
                  color: resolved
                      ? const Color(0xFF159947)
                      : const Color(0xFFD97706),
                  size: 25,
                ),
              ),

              const SizedBox(width: 13),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sanction.title,
                      style: const TextStyle(
                        color: navy,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    if (sanction.issuedAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('MMMM d, yyyy')
                            .format(sanction.issuedAt!.toLocal()),
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 8),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _displayStatus(sanction.status),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 15),

          const Divider(height: 1),

          const SizedBox(height: 14),

          const Text(
            'Reason',
            style: TextStyle(
              color: muted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 5),

          Text(
            sanction.reason.isEmpty ? 'No reason provided.' : sanction.reason,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 13,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),

          if (resolved && sanction.resolvedAt != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF159947),
                  size: 17,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Resolved ${DateFormat('MMMM d, yyyy').format(sanction.resolvedAt!.toLocal())}',
                    style: const TextStyle(
                      color: Color(0xFF159947),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E2E8)),
      ),
      child: const Column(
        children: [
          Icon(Icons.verified_outlined, color: Color(0xFF159947), size: 50),

          SizedBox(height: 15),

          Text(
            'No sanctions',
            style: TextStyle(
              color: Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),

          SizedBox(height: 7),

          Text(
            'You currently have no sanctions.',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Container(
      width: double.infinity,
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
            'Unable to load sanctions',
            style: TextStyle(
              color: Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),

          const SizedBox(height: 8),

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

  String _displayStatus(String value) {
    final normalized = value.trim().toLowerCase();

    if (normalized.isEmpty) {
      return 'Pending';
    }

    return normalized
        .split('_')
        .map(
          (word) => word.isEmpty
              ? ''
              : '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }
}
