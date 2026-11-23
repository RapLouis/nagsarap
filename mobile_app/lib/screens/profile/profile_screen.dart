import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../main.dart';
import '../../models/student_profile.dart';
import '../../services/auth_service.dart';
import '../../services/profile_service.dart';
import '../auth/auth_gate.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const Color navy = Color(0xFF080878);
  static const Color gold = Color(0xFFFFC800);
  static const Color muted = Color(0xFF64748B);

  bool _loading = true;
  String? _error;

  StudentProfile? _profile;
  Uint8List? _profilePhoto;

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

    final results = await Future.wait([
      ProfileService.instance.getProfile(),
      ProfileService.instance.getProfilePhoto(),
    ]);

    final result = results[0] as ProfileResult;
    final photo = results[1] as Uint8List?;

    if (!mounted) return;

    setState(() {
      _loading = false;
      if (result.success && result.profile != null) {
        _profile = result.profile;
        _profilePhoto = photo;
        _error = null;
      } else {
        _profile = null;
        _profilePhoto = null;
        _error = result.message;
      }
    });
  }

  Future<void> _confirmLogout() async {
    final isDark = themeController.isDarkMode;

    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          'Confirm Logout',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : navy,
          ),
        ),
        content: Text(
          'Are you sure you want to log out of your account?',
          style: TextStyle(
            color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Log Out',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      await AuthService.instance.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const AuthGate()),
        (route) => false,
      );
    }
  }

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
            title: const Text(
              'Profile',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                letterSpacing: 0.2,
              ),
            ),
            actions: [
              IconButton(
                tooltip:
                    isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
                onPressed: () {
                  themeController.toggleTheme();
                },
                icon: Icon(
                  isDark ? Icons.wb_sunny_rounded : Icons.dark_mode_rounded,
                  color: gold,
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: RefreshIndicator(
            color: gold,
            onRefresh: _loadProfile,
            child: _buildBody(),
          ),
        );
      },
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 200),
          Center(child: CircularProgressIndicator(color: gold)),
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
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 40),
      children: [
        _buildProfileHeader(profile),
        const SizedBox(height: 20),
        _buildSection(
          title: 'PERSONAL INFORMATION',
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
              label: 'Email Address',
              value: _display(profile.email),
              showDivider: false,
            ),
          ],
        ),
        const SizedBox(height: 18),
        _buildSection(
          title: 'ACADEMIC INFORMATION',
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
        const SizedBox(height: 26),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            onPressed: _confirmLogout,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFDC2626),
              backgroundColor: themeController.isDarkMode
                  ? const Color(0xFF1E293B)
                  : Colors.white,
              side: BorderSide(
                color: themeController.isDarkMode
                    ? const Color(0xFF7F1D1D)
                    : const Color(0xFFFECACA),
                width: 1.2,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.logout_rounded, size: 19),
            label: const Text(
              'Log Out',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileHeader(StudentProfile profile) {
    final isDark = themeController.isDarkMode;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : navy,
        borderRadius: BorderRadius.circular(20),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: navy.withValues(alpha: 0.14),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Column(
        children: [
          Container(
            width: 92,
            height: 92,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: gold, width: 3.5),
            ),
            child: ClipOval(
              child: _profilePhoto != null
                  ? Image.memory(
                      _profilePhoto!,
                      width: 85,
                      height: 85,
                      fit: BoxFit.cover,
                    )
                  : const Icon(Icons.person_rounded, color: navy, size: 52),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            profile.displayName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
          if (profile.studentNumber.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                profile.studentNumber,
                style: const TextStyle(
                  color: Color(0xFFE2E8F0),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
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
    final isDark = themeController.isDarkMode;
    final dividerColor =
        isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: dividerColor, width: 1.0),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Text(
              title,
              style: TextStyle(
                color: isDark ? gold : navy,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Divider(height: 1, thickness: 1, color: dividerColor),
          ...children,
        ],
      ),
    );
  }

  Widget _buildError() {
    final isDark = themeController.isDarkMode;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 44),
          const SizedBox(height: 12),
          Text(
            'Unable to load profile',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : navy,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _error ?? 'Please try again.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted, fontSize: 13),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _loadProfile,
            style: FilledButton.styleFrom(
              backgroundColor: isDark ? gold : navy,
              foregroundColor: isDark ? navy : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Try Again',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  String _display(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return 'Not available';
    return clean;
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
    final isDark = themeController.isDarkMode;
    final dividerColor =
        isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0F172A)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: isDark
                      ? _ProfileScreenState.gold
                      : _ProfileScreenState.navy,
                  size: 19,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: _ProfileScreenState.muted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Padding(
            padding: const EdgeInsets.only(left: 70, right: 18),
            child: Divider(height: 1, thickness: 1, color: dividerColor),
          ),
      ],
    );
  }
}