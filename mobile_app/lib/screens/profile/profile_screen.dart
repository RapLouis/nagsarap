import 'package:flutter/material.dart';

import '../../models/student_profile.dart';
import '../../services/profile_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const Color navy = Color(0xFF080878);

  static const Color gold = Color(0xFFFFC800);

  static const Color background = Color(0xFFF6F6F6);

  static const Color muted = Color(0xFF777783);

  bool _loading = true;
  String? _error;

  StudentProfile? _profile;

  @override
  void initState() {
    super.initState();

    _loadProfile();
  }

  Future<void> _loadProfile() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    final result = await ProfileService.instance.getProfile();

    if (!mounted) {
      return;
    }

    setState(() {
      _loading = false;

      if (result.success && result.profile != null) {
        _profile = result.profile;
        _error = null;
      } else {
        _profile = null;
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
          'Profile',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: RefreshIndicator(
        color: navy,
        onRefresh: _loadProfile,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 200),
          Center(child: CircularProgressIndicator(color: navy)),
        ],
      );
    }

    if (_error != null || _profile == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [const SizedBox(height: 100), _buildError()],
      );
    }

    final profile = _profile!;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 32),
      children: [
        _buildProfileHeader(profile),

        const SizedBox(height: 18),

        _buildSection(
          title: 'Personal Information',
          children: [
            _ProfileRow(
              icon: Icons.badge_outlined,
              label: 'Student Number',
              value: _display(profile.studentNumber),
            ),
            _ProfileRow(
              icon: Icons.person_outline_rounded,
              label: 'Full Name',
              value: _display(profile.fullName),
            ),
            _ProfileRow(
              icon: Icons.email_outlined,
              label: 'Email',
              value: _display(profile.email),
              showDivider: false,
            ),
          ],
        ),

        const SizedBox(height: 16),

        _buildSection(
          title: 'Academic Information',
          children: [
            _ProfileRow(
              icon: Icons.school_outlined,
              label: 'Degree / Course',
              value: _display(profile.degree),
            ),
            _ProfileRow(
              icon: Icons.groups_outlined,
              label: 'Year & Section',
              value: _display(profile.yearSection),
            ),
            _ProfileRow(
              icon: Icons.calendar_month_outlined,
              label: 'Semester',
              value: _display(profile.semester),
            ),
            _ProfileRow(
              icon: Icons.date_range_outlined,
              label: 'Academic Year',
              value: _display(profile.academicYear),
              showDivider: false,
            ),
          ],
        ),

        const SizedBox(height: 16),

        _buildVerificationCard(profile),
      ],
    );
  }

  Widget _buildProfileHeader(StudentProfile profile) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: navy,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Container(
            width: 82,
            height: 82,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: gold, width: 4),
            ),
            child: const Icon(Icons.person_rounded, color: navy, size: 50),
          ),

          const SizedBox(height: 15),

          Text(
            profile.displayName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),

          if (profile.studentNumber.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              profile.studentNumber,
              style: const TextStyle(
                color: Color(0xFFD7D7F0),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E2E8)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(17, 16, 17, 12),
            child: Text(
              title,
              style: const TextStyle(
                color: navy,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }

  Widget _buildVerificationCard(StudentProfile profile) {
    final verified = profile.isVerified;

    final statusColor = verified
        ? const Color(0xFF159947)
        : const Color(0xFFD97706);

    final statusBackground = verified
        ? const Color(0xFFE8F6EC)
        : const Color(0xFFFFF3CD);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E2E8)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: statusBackground,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              verified
                  ? Icons.verified_user_rounded
                  : Icons.warning_amber_rounded,
              color: statusColor,
              size: 27,
            ),
          ),

          const SizedBox(width: 13),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Biometric Verification',
                  style: TextStyle(
                    color: navy,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  verified
                      ? 'Your biometric registration is verified.'
                      : _verificationMessage(profile),
                  style: const TextStyle(
                    color: muted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: statusBackground,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              verified ? 'Verified' : _statusLabel(profile.verificationStatus),
              style: TextStyle(
                color: statusColor,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
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
            'Unable to load profile',
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
            onPressed: _loadProfile,
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

  String _display(String value) {
    final clean = value.trim();

    if (clean.isEmpty) {
      return 'Not available';
    }

    return clean;
  }

  String _verificationMessage(StudentProfile profile) {
    if (profile.verificationStatus.trim().isEmpty) {
      return 'Verification status is not available.';
    }

    return 'Current status: ${_statusLabel(profile.verificationStatus)}.';
  }

  String _statusLabel(String value) {
    final clean = value.trim();

    if (clean.isEmpty) {
      return 'Pending';
    }

    return clean
        .split(RegExp(r'[_\s]+'))
        .where((word) => word.isNotEmpty)
        .map(
          (word) =>
              '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
        )
        .join(' ');
  }
}

class _ProfileRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool showDivider;

  const _ProfileRow({
    required this.icon,
    required this.label,
    required this.value,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F1FB),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: _ProfileScreenState.navy, size: 20),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: _ProfileScreenState.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      value,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        if (showDivider)
          const Padding(
            padding: EdgeInsets.only(left: 67),
            child: Divider(height: 1),
          ),
      ],
    );
  }
}
