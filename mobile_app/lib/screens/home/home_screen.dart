import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/event_item.dart';
import '../../services/auth_service.dart';
import '../../services/event_service.dart';
import '../attendance/attendance_face_verification_screen.dart';
import '../attendance/attendance_history_screen.dart';
import '../auth/auth_gate.dart';
import '../calendar/calendar_screen.dart';
import '../sanctions/sanctions_screen.dart';
import '../profile/profile_screen.dart';
import '../notifications/notifications_screen.dart';

class HomeScreen extends StatefulWidget {
  final Map<String, dynamic>? user;
  final Map<String, dynamic>? student;

  const HomeScreen({super.key, this.user, this.student});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const Color _navy = Color(0xFF080878);
  static const Color _gold = Color(0xFFFFC800);
  static const Color _background = Color(0xFFF6F6F6);
  static const Color _muted = Color(0xFF808080);
  static const Color _softGold = Color(0xFFFFE9A3);

  bool _loading = true;
  String? _error;

  List<EventItem> _events = const [];

  int? _expandedEventId;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  // ===========================================================================
  // STUDENT INFORMATION
  // ===========================================================================

  String get _firstName {
    final firstName = _readStudent(['firstname', 'first_name']);

    if (firstName.isNotEmpty) {
      return firstName.split(RegExp(r'\s+')).first;
    }

    final userName = widget.user?['name']?.toString().trim();

    if (userName != null && userName.isNotEmpty) {
      return userName.split(RegExp(r'\s+')).first;
    }

    return 'Student';
  }

  String get _fullName {
    final first = _readStudent(['firstname', 'first_name']);

    final middle = _readStudent(['middlename', 'middle_name']);

    final last = _readStudent(['lastname', 'last_name', 'surname']);

    final extension = _readStudent(['ext', 'extension']);

    final name = [
      first,
      middle,
      last,
      extension,
    ].where((value) => value.isNotEmpty).join(' ');

    if (name.isNotEmpty) {
      return name;
    }

    final userName = widget.user?['name']?.toString().trim();

    if (userName != null && userName.isNotEmpty) {
      return userName;
    }

    return 'Student';
  }

  String get _studentNumber {
    return _readStudent(['student_number', 'student_no']);
  }

  String _readStudent(List<String> keys) {
    for (final key in keys) {
      final value = widget.student?[key]?.toString().trim();

      if (value != null && value.isNotEmpty && value.toLowerCase() != 'null') {
        return value;
      }
    }

    return '';
  }

  // ===========================================================================
  // EVENTS
  // ===========================================================================

  Future<void> _loadEvents() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    final result = await EventService.instance.getEvents();

    if (!mounted) {
      return;
    }

    setState(() {
      _loading = false;

      if (result.success) {
        _events = result.events;
        _error = null;
      } else {
        _events = const [];
        _error = result.message;
      }
    });
  }

  List<EventItem> get _todayEvents {
    return _events.where((event) => event.isToday).toList();
  }

  List<EventItem> get _upcomingEvents {
    return _events.where((event) => event.isUpcoming).toList();
  }

  // ===========================================================================
  // STAGE 17 - ATTENDANCE HISTORY
  // ===========================================================================

  Future<void> _openAttendanceHistory() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AttendanceHistoryScreen()));
  }

  // ===========================================================================
  // STAGE 16 - RECORD ATTENDANCE
  // ===========================================================================

  Future<void> _openAttendanceScanner() async {
    final today = _todayEvents;

    if (today.isEmpty) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('There is no event scheduled for today.')),
      );

      return;
    }

    EventItem? selectedEvent;

    if (today.length == 1) {
      selectedEvent = today.first;
    } else {
      selectedEvent = await showModalBottomSheet<EventItem>(
        context: context,
        backgroundColor: Colors.white,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (BuildContext sheetContext) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select Event',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Choose the event where you want to record attendance.',
                    style: TextStyle(color: _muted, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  for (final event in today)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                        backgroundColor: _gold,
                        foregroundColor: Colors.black,
                        child: Icon(Icons.event_available_rounded),
                      ),
                      title: Text(
                        event.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        [
                          _formatTimeRange(event),
                          if (event.venue.isNotEmpty) event.venue,
                        ].join(' • '),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        Navigator.pop(sheetContext, event);
                      },
                    ),
                ],
              ),
            ),
          );
        },
      );
    }

    if (selectedEvent == null || !mounted) {
      return;
    }

    final recorded = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AttendanceFaceVerificationScreen(event: selectedEvent!),
      ),
    );

    if (recorded == true && mounted) {
      await _loadEvents();
    }
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: RefreshIndicator(
                color: _navy,
                onRefresh: _loadEvents,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(18, 30, 18, 115),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  "Today's Activity",
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 28,
                                    height: 1.1,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Attendance History',
                                onPressed: _openAttendanceHistory,
                                icon: const Icon(
                                  Icons.history_rounded,
                                  color: _navy,
                                  size: 29,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          _buildHistoryButton(),

                          const SizedBox(height: 25),

                          _buildContent(),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavigation(),
      floatingActionButton: _buildScannerButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  // ===========================================================================
  // HEADER
  // ===========================================================================

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      height: 82,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: _navy,
      child: Row(
        children: [
          const CircleAvatar(
            radius: 25,
            backgroundColor: Color(0xFFE0E0E0),
            child: Icon(
              Icons.person_rounded,
              color: Color(0xFF777777),
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome, $_firstName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (_studentNumber.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _studentNumber,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF9999C8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(30),
              onTap: _showProfileMenu,
              child: const Padding(
                padding: EdgeInsets.all(3),
                child: Icon(
                  Icons.account_circle_outlined,
                  color: _gold,
                  size: 44,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // ATTENDANCE HISTORY BUTTON
  // ===========================================================================

  Widget _buildHistoryButton() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: _openAttendanceHistory,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0xFFE1E1E8)),
          ),
          child: const Row(
            children: [
              SizedBox(
                width: 42,
                height: 42,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xFFFFF4C8),
                    borderRadius: BorderRadius.all(Radius.circular(11)),
                  ),
                  child: Icon(Icons.history_rounded, color: _navy, size: 24),
                ),
              ),
              SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Attendance History',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'View your recorded attendance',
                      style: TextStyle(color: _muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.black54),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // HOME CONTENT
  // ===========================================================================

  Widget _buildContent() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.only(top: 70),
        child: Center(child: CircularProgressIndicator(color: _navy)),
      );
    }

    if (_error != null) {
      return _buildErrorState();
    }

    final today = _todayEvents;

    if (today.isEmpty) {
      return _buildNoEventsState();
    }

    return Column(
      children: [
        for (final event in today) ...[
          _buildTodayEventCard(event),
          const SizedBox(height: 23),
        ],
      ],
    );
  }

  // ===========================================================================
  // TODAY EVENT
  // ===========================================================================

  Widget _buildTodayEventCard(EventItem event) {
    final expanded = _expandedEventId == event.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(17),
            onTap: () {
              setState(() {
                _expandedEventId = expanded ? null : event.id;
              });
            },
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 96),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: Colors.black, width: 1),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 18,
                            height: 1.25,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatDate(event),
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 17,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 15),
                  Container(
                    constraints: const BoxConstraints(minWidth: 95),
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _softGold,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Ongoing',
                      style: TextStyle(
                        color: Color(0xFFFF8A00),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: expanded
              ? _buildExpandedEvent(event)
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  // ===========================================================================
  // EXPANDED EVENT
  // ===========================================================================

  Widget _buildExpandedEvent(EventItem selectedEvent) {
    final upcoming = _upcomingEvents.take(3).toList();

    return Padding(
      key: ValueKey('event-${selectedEvent.id}'),
      padding: const EdgeInsets.fromLTRB(17, 18, 17, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (selectedEvent.startTime.isNotEmpty ||
              selectedEvent.endTime.isNotEmpty ||
              selectedEvent.venue.isNotEmpty)
            _buildSelectedEventDetails(selectedEvent),
          if (upcoming.isNotEmpty) ...[
            const SizedBox(height: 22),
            const Text(
              'See Events',
              style: TextStyle(
                color: Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 17),
            for (var index = 0; index < upcoming.length; index++) ...[
              _buildSmallEventCard(upcoming[index], goldAccent: index.isEven),
              if (index < upcoming.length - 1) const SizedBox(height: 16),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildSelectedEventDetails(EventItem event) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (event.startTime.isNotEmpty || event.endTime.isNotEmpty)
            Row(
              children: [
                const Icon(Icons.access_time_rounded, color: _navy, size: 17),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    _formatTimeRange(event),
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          if (event.venue.isNotEmpty) ...[
            if (event.startTime.isNotEmpty || event.endTime.isNotEmpty)
              const SizedBox(height: 9),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on_outlined, color: _navy, size: 17),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    event.venue,
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ===========================================================================
  // UPCOMING EVENT CARD
  // ===========================================================================

  Widget _buildSmallEventCard(EventItem event, {required bool goldAccent}) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 96),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 96,
            decoration: BoxDecoration(
              color: goldAccent ? _gold : _navy,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(17),
                bottomLeft: Radius.circular(17),
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 16, 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDate(event),
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _formatTimeRange(event),
                    style: const TextStyle(color: _muted, fontSize: 11),
                  ),
                  if (event.venue.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      event.venue,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // EMPTY
  // ===========================================================================

  Widget _buildNoEventsState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFD4D4D4)),
      ),
      child: const Column(
        children: [
          Icon(Icons.event_busy_outlined, color: _navy, size: 42),
          SizedBox(height: 12),
          Text(
            'No activity today',
            style: TextStyle(
              color: Colors.black,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 7),
          Text(
            'There are no active events scheduled for today.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // ERROR
  // ===========================================================================

  Widget _buildErrorState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFD4D4D4)),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 42),
          const SizedBox(height: 12),
          const Text(
            'Unable to load events',
            style: TextStyle(
              color: Colors.black,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _error ?? 'Please try again.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 13),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: 150,
            height: 42,
            child: FilledButton(
              onPressed: _loadEvents,
              style: FilledButton.styleFrom(
                backgroundColor: _navy,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
              child: const Text('Try Again'),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // PROFILE MENU
  // ===========================================================================

  Future<void> _showProfileMenu() async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Profile',
      barrierColor: Colors.black.withValues(alpha: 0.40),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder:
          (
            BuildContext dialogContext,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
          ) {
            final screenWidth = MediaQuery.sizeOf(dialogContext).width;

            return SafeArea(
              child: Stack(
                children: [
                  Positioned(
                    top: 75,
                    right: 12,
                    child: Material(
                      color: Colors.transparent,
                      child: Container(
                        width: screenWidth < 390 ? 245 : 255,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.10),
                              blurRadius: 16,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                18,
                                15,
                                14,
                                14,
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.person,
                                    color: Colors.black,
                                    size: 31,
                                  ),
                                  const SizedBox(width: 13),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _fullName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.black,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        if (_studentNumber.isNotEmpty)
                                          Text(
                                            _studentNumber,
                                            style: const TextStyle(
                                              color: _muted,
                                              fontSize: 13,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            _profileMenuItem(
                              icon: Icons.history_rounded,
                              label: 'Attendance History',
                              onTap: () {
                                Navigator.pop(dialogContext);
                                _openAttendanceHistory();
                              },
                            ),

                            _profileMenuItem(
                              icon: Icons.person_outline_rounded,
                              label: 'Personal Information',
                              onTap: () {
                                Navigator.pop(dialogContext);

                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const ProfileScreen(),
                                  ),
                                );
                              },
                            ),

                            _profileMenuItem(
                              icon: Icons.settings_outlined,
                              label: 'Settings',
                              onTap: () {
                                Navigator.pop(dialogContext);
                              },
                            ),

                            _profileMenuItem(
                              icon: Icons.info_outline_rounded,
                              label: 'About',
                              onTap: () {
                                Navigator.pop(dialogContext);
                              },
                            ),

                            const Divider(height: 1),

                            InkWell(
                              onTap: () {
                                Navigator.pop(dialogContext);
                                _confirmLogout();
                              },
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 14,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.logout_rounded,
                                      color: Color(0xFFFF3B30),
                                      size: 19,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Log Out',
                                      style: TextStyle(
                                        color: Color(0xFFFF3B30),
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
    );
  }

  Widget _profileMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: Colors.black, size: 22),
            const SizedBox(width: 15),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: Color(0xFF333333), fontSize: 14),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.black,
              size: 21,
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // LOGOUT
  // ===========================================================================

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          contentPadding: const EdgeInsets.fromLTRB(28, 25, 28, 24),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE5E5E5)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: Color(0xFFFF3B30),
                  size: 32,
                ),
              ),
              const SizedBox(height: 13),
              const Text(
                'Log Out',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 23,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 7),
              const Text(
                'Are you sure you want to log out?',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, fontSize: 12),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        Navigator.pop(dialogContext, false);
                      },
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: Colors.black, fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: FilledButton(
                        onPressed: () {
                          Navigator.pop(dialogContext, true);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: _navy,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(7),
                          ),
                        ),
                        child: const Text(
                          'Yes',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await AuthService.instance.logout();

    if (!mounted) {
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (route) => false,
    );
  }

  // ===========================================================================
  // BOTTOM NAVIGATION
  // ===========================================================================
  Widget _buildBottomNavigation() {
    return BottomAppBar(
      height: 83,
      padding: EdgeInsets.zero,
      color: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 8,
      notchMargin: 8,
      shape: const CircularNotchedRectangle(),
      child: Row(
        children: [
          Expanded(
            child: _bottomItem(
              icon: Icons.home_outlined,
              selectedIcon: Icons.home_rounded,
              label: 'Home',
              selected: true,
              onTap: () {},
            ),
          ),
          Expanded(
            child: _bottomItem(
              icon: Icons.notifications_none_rounded,
              selectedIcon: Icons.notifications_rounded,
              label: 'Notification',
              selected: false,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const NotificationsScreen(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 78),
          Expanded(
            child: _bottomItem(
              icon: Icons.calendar_today_outlined,
              selectedIcon: Icons.calendar_today_rounded,
              label: 'Calendar',
              selected: false,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CalendarScreen()),
                );
              },
            ),
          ),
          Expanded(
            child: _bottomItem(
              icon: Icons.event_note_outlined,
              selectedIcon: Icons.event_note_rounded,
              label: 'Sanction',
              selected: false,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SanctionsScreen()),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomItem({
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final color = selected ? Colors.black : _muted;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 7),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? selectedIcon : icon, color: color, size: 25),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // CENTER ATTENDANCE SCANNER
  // ===========================================================================

  Widget _buildScannerButton() {
    return SizedBox(
      width: 78,
      height: 78,
      child: FloatingActionButton(
        heroTag: 'record-attendance',
        elevation: 0,
        highlightElevation: 2,
        backgroundColor: _gold,
        foregroundColor: Colors.black,
        shape: const CircleBorder(),
        onPressed: _openAttendanceScanner,
        child: const Icon(Icons.center_focus_strong_rounded, size: 37),
      ),
    );
  }

  // ===========================================================================
  // DATE / TIME FORMATTERS
  // ===========================================================================

  String _formatDate(EventItem event) {
    final date = event.date;

    if (date == null) {
      if (event.eventDate.isNotEmpty) {
        return event.eventDate;
      }

      return 'Date not specified';
    }

    return DateFormat('MMMM d, yyyy').format(date);
  }

  String _formatTimeRange(EventItem event) {
    final start = _formatTime(event.startTime);

    final end = _formatTime(event.endTime);

    if (start.isNotEmpty && end.isNotEmpty) {
      return '$start - $end';
    }

    if (start.isNotEmpty) {
      return start;
    }

    if (end.isNotEmpty) {
      return end;
    }

    return 'Time not specified';
  }

  String _formatTime(String value) {
    final clean = value.trim();

    if (clean.isEmpty) {
      return '';
    }

    const formats = ['HH:mm:ss', 'HH:mm', 'h:mm a'];

    for (final format in formats) {
      try {
        final parsed = DateFormat(format).parseStrict(clean);

        return DateFormat('h:mm a').format(parsed);
      } catch (_) {
        // Try next supported format.
      }
    }

    return clean;
  }
}
