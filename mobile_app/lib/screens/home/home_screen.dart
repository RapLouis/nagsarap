import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/event_item.dart';
import '../../services/attendance_service.dart';
import '../../services/auth_service.dart';
import '../../services/event_service.dart';
import '../../services/notification_service.dart';
import '../../services/profile_service.dart';
import '../../widgets/main_bottom_navigation.dart';

import '../attendance/attendance_face_verification_screen.dart';
import '../attendance/attendance_history_screen.dart';
import '../auth/auth_gate.dart';
import '../calendar/calendar_screen.dart';
import '../notifications/notifications_screen.dart';
import '../profile/profile_screen.dart';
import '../sanctions/sanctions_screen.dart';

import '../../services/attendance_history_service.dart';

class HomeScreen extends StatefulWidget {
  final Map<String, dynamic>? user;
  final Map<String, dynamic>? student;
  final bool openScannerOnLoad;

  const HomeScreen({
    super.key,
    this.user,
    this.student,
    this.openScannerOnLoad = false,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const Color navy = Color(0xFF080878);
  static const Color gold = Color(0xFFFFC800);
  static const Color background = Color(0xFFF6F6F6);
  static const Color muted = Color(0xFF808080);

  bool _loading = true;
  bool _dashboardBusy = false;
  bool _syncingOffline = false;

  String? _error;

  List<EventItem> _events = const [];

  int _attendanceCount = 0;
  int _unreadCount = 0;
  int _pendingOfflineCount = 0;

  String _latestAttendanceStatus = 'No record';

  Uint8List? _profilePhoto;

  Map<String, dynamic>? _currentUser;
  Map<String, dynamic>? _currentStudent;

  final Set<int> _attendedEventIds = <int>{};

  // ===========================================================================
  // LIFECYCLE
  // ===========================================================================

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    final dashboardLoad = _loadDashboard();

    _restoreIdentity();
    _loadProfilePhoto();

    if (widget.openScannerOnLoad) {
      dashboardLoad.then((_) {
        if (!mounted) return;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _openAttendanceScanner();
          }
        });
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      _loadDashboard(showMainLoader: false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ===========================================================================
  // STUDENT
  // ===========================================================================

  String get _firstName {
    final value = _readStudent(['firstname', 'first_name']);

    if (value.isNotEmpty) {
      return _titleCase(value.split(RegExp(r'\s+')).first);
    }

    final userName =
        _currentUser?['name']?.toString().trim() ??
        widget.user?['name']?.toString().trim();

    if (userName != null && userName.isNotEmpty) {
      return _titleCase(userName.split(RegExp(r'\s+')).first);
    }

    return 'Student';
  }

  String get _fullName {
    final first = _readStudent(['firstname', 'first_name']);

    final middle = _readStudent(['middlename', 'middle_name']);

    final last = _readStudent(['surname', 'lastname', 'last_name']);

    final extension = _readStudent(['ext', 'extension']);

    final result = [
      first,
      middle,
      last,
      extension,
    ].where((value) => value.isNotEmpty).join(' ');

    if (result.isNotEmpty) {
      return _titleCase(result);
    }

    final userName =
        _currentUser?['name']?.toString().trim() ??
        widget.user?['name']?.toString().trim();

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
      final value =
          _currentStudent?[key]?.toString().trim() ??
          widget.student?[key]?.toString().trim();

      if (value != null && value.isNotEmpty && value.toLowerCase() != 'null') {
        return value;
      }
    }

    return '';
  }

  Future<void> _restoreIdentity() async {
    try {
      final result = await AuthService.instance.me();

      if (!mounted || !result.success) {
        return;
      }

      setState(() {
        _currentUser = result.user ?? _currentUser;
        _currentStudent = result.student ?? _currentStudent;
      });
    } catch (e) {
      debugPrint('HOME IDENTITY RESTORE ERROR: $e');
    }
  }

  String _titleCase(String value) {
    return value
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map(
          (part) => part.length == 1
              ? part.toUpperCase()
              : '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  Future<void> _loadProfilePhoto() async {
    final photo = await ProfileService.instance.getProfilePhoto();

    if (!mounted) return;

    setState(() {
      _profilePhoto = photo;
    });
  }

  Widget _profileAvatar({double radius = 25}) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFE0E0E0),
      backgroundImage: _profilePhoto != null
          ? MemoryImage(_profilePhoto!)
          : null,
      child: _profilePhoto == null
          ? const Icon(Icons.person_rounded, color: Color(0xFF777777), size: 30)
          : null,
    );
  }

  // ===========================================================================
  // DASHBOARD
  // ===========================================================================

  Future<void> _loadDashboard({bool showMainLoader = true}) async {
    if (_dashboardBusy) {
      return;
    }

    _dashboardBusy = true;

    if (mounted && showMainLoader) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      // -----------------------------------------------------------------------
      // 1. LOCAL PENDING COUNT
      // -----------------------------------------------------------------------

      final pendingBefore = await AttendanceService.instance
          .pendingOfflineCount();

      if (mounted) {
        setState(() {
          _pendingOfflineCount = pendingBefore;
        });
      }

      // -----------------------------------------------------------------------
      // 2. EVENTS
      // -----------------------------------------------------------------------

      final eventResult = await EventService.instance.getEvents();

      if (!mounted) {
        return;
      }

      // -----------------------------------------------------------------------
      // 3. OFFLINE SYNC
      // -----------------------------------------------------------------------

      if (pendingBefore > 0) {
        setState(() {
          _syncingOffline = true;
        });

        try {
          final syncResult = await AttendanceService.instance
              .syncPendingAttendances();

          if (mounted) {
            setState(() {
              _pendingOfflineCount = syncResult.remaining;
            });
          }
        } catch (e) {
          debugPrint('HOME OFFLINE SYNC ERROR: $e');

          final remaining = await AttendanceService.instance
              .pendingOfflineCount();

          if (mounted) {
            setState(() {
              _pendingOfflineCount = remaining;
            });
          }
        } finally {
          if (mounted) {
            setState(() {
              _syncingOffline = false;
            });
          }
        }
      }

      // -----------------------------------------------------------------------
      // 4. HISTORY
      // -----------------------------------------------------------------------

      final historyResult = await AttendanceHistoryService.instance
          .getHistory();

      // -----------------------------------------------------------------------
      // 5. NOTIFICATIONS
      // -----------------------------------------------------------------------

      final notificationResult = await NotificationService.instance
          .getNotifications();

      // -----------------------------------------------------------------------
      // 6. FINAL PENDING COUNT
      // -----------------------------------------------------------------------

      final pendingAfter = await AttendanceService.instance
          .pendingOfflineCount();

      if (!mounted) {
        return;
      }

      // -----------------------------------------------------------------------
      // 7. UPDATE UI
      // -----------------------------------------------------------------------

      setState(() {
        _pendingOfflineCount = pendingAfter;

        if (eventResult.success) {
          _events = eventResult.events;
          _error = null;
        } else {
          _events = const [];
          _error = eventResult.message;
        }

        if (historyResult.success) {
          _attendanceCount = historyResult.records.length;

          _attendedEventIds
            ..clear()
            ..addAll(
              historyResult.records
                  .map((record) => record.eventId)
                  .whereType<int>(),
            );

          if (historyResult.records.isEmpty) {
            _latestAttendanceStatus = 'No record';
          } else {
            _latestAttendanceStatus = _formatStatus(
              historyResult.records.first.status,
            );
          }
        } else {
          _attendedEventIds.clear();
          _attendanceCount = 0;
          _latestAttendanceStatus = 'Unavailable';
        }

        if (notificationResult.success) {
          _unreadCount = notificationResult.unreadCount;
        } else {
          _unreadCount = 0;
        }

        _loading = false;
      });
    } catch (e) {
      debugPrint('HOME DASHBOARD ERROR: $e');

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error = 'Unable to load the dashboard.';
      });
    } finally {
      _dashboardBusy = false;
    }
  }

  // ===========================================================================
  // EVENTS
  // ===========================================================================

  List<EventItem> get _todayEvents {
    return _events.where((event) => event.isToday).toList();
  }

  List<EventItem> get _upcomingEvents {
    return _events.where((event) => event.isUpcoming).toList();
  }

  // ===========================================================================
  // NAVIGATION
  // ===========================================================================

  Future<void> _openHistory() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AttendanceHistoryScreen()),
    );

    if (mounted) {
      await _loadDashboard(showMainLoader: false);
    }
  }

  Future<void> _openCalendar() async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const CalendarScreen()));

    if (!mounted) return;

    await _loadDashboard(showMainLoader: false);
  }

  Future<void> _openProfile() async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const ProfileScreen()));

    if (mounted) {
      await _loadProfilePhoto();

      await _loadDashboard(showMainLoader: false);
    }
  }

  // ===========================================================================
  // ATTENDANCE
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
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Choose an event to record attendance.',
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  for (final event in today)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                        backgroundColor: gold,
                        foregroundColor: Colors.black,
                        child: Icon(Icons.event_available_rounded),
                      ),
                      title: Text(
                        event.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(_eventSubtitle(event)),
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
      MaterialPageRoute<bool>(
        builder: (_) => AttendanceFaceVerificationScreen(event: selectedEvent!),
      ),
    );

    if (recorded == true && mounted) {
      await _loadDashboard(showMainLoader: false);
    }
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: RefreshIndicator(
                color: navy,
                onRefresh: () {
                  return _loadDashboard(showMainLoader: false);
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(18, 26, 18, 115),
                  children: [
                    const Text(
                      "Today's Activity",
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 80),
                        child: Center(
                          child: CircularProgressIndicator(color: navy),
                        ),
                      )
                    else ...[
                      if (_pendingOfflineCount > 0 || _syncingOffline) ...[
                        _buildPendingOfflineCard(),
                        const SizedBox(height: 16),
                      ],
                      if (_error != null)
                        _buildError()
                      else ...[
                        _buildSummary(),
                        const SizedBox(height: 16),
                        _buildHistoryCard(),
                        const SizedBox(height: 22),
                        _buildTodaySection(),
                        if (_upcomingEvents.isNotEmpty) ...[
                          const SizedBox(height: 28),
                          _buildUpcomingSection(),
                        ],
                      ],
                    ],
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
      height: 82,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: navy,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              shape: BoxShape.circle,
              border: Border.all(
                color: gold.withValues(alpha: 0.75),
                width: 1.5,
              ),
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
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (_studentNumber.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _studentNumber,
                    style: const TextStyle(
                      color: Color(0xFF9999C8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(30),
            onTap: _showProfileMenu,
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: _profileAvatar(radius: 22),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // OFFLINE PENDING CARD
  // ===========================================================================

  Widget _buildPendingOfflineCard() {
    final syncing = _syncingOffline;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6D6),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: gold),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFFFE9A3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: syncing
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: navy,
                    ),
                  )
                : const Icon(
                    Icons.cloud_upload_outlined,
                    color: navy,
                    size: 26,
                  ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  syncing
                      ? 'Synchronizing attendance'
                      : 'Pending offline attendance',
                  style: const TextStyle(
                    color: navy,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  syncing
                      ? 'Verifying the saved attendance with the server.'
                      : '$_pendingOfflineCount record${_pendingOfflineCount == 1 ? '' : 's'} waiting for verification and sync.',
                  style: const TextStyle(
                    color: Color(0xFF6C6200),
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (!syncing)
            IconButton(
              tooltip: 'Sync now',
              onPressed: () {
                _loadDashboard(showMainLoader: false);
              },
              icon: const Icon(Icons.sync_rounded, color: navy),
            ),
        ],
      ),
    );
  }

  // ===========================================================================
  // SUMMARY
  // ===========================================================================

  Widget _buildSummary() {
    return Row(
      children: [
        Expanded(
          child: _summaryCard(
            icon: Icons.event_available_outlined,
            value: '${_todayEvents.length}',
            label: 'Today',
            onTap: () => _showSummaryDetails('Today'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _summaryCard(
            icon: Icons.upcoming_outlined,
            value: '${_upcomingEvents.length}',
            label: 'Upcoming',
            onTap: () => _showSummaryDetails('Upcoming'),
          ),
        ),
      ],
    );
  }

  Widget _summaryCard({
    required IconData icon,
    required String value,
    required String label,
    required VoidCallback onTap,
  }) {
    final Color accent = switch (label) {
      'Today' => const Color(0xFF6D5CE7),
      'Upcoming' => const Color(0xFFFF9F1C),
      _ => const Color(0xFF5D6B82),
    };

    final soft = accent.withValues(alpha: 0.10);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: accent.withValues(alpha: 0.20)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0B000000),
                blurRadius: 14,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: soft,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: accent, size: 21),
              ),
              const SizedBox(height: 7),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Text(
                  value,
                  key: ValueKey('$label-$value'),
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSummaryDetails(String label) async {
    final events = label == 'Today' ? _todayEvents : _upcomingEvents;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final Color accent = switch (label) {
          'Today' => const Color(0xFF6D5CE7),
          'Upcoming' => const Color(0xFFFF9F1C),
          _ => const Color(0xFF5D6B82),
        };

        return Dialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 22,
            vertical: 30,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          label == 'Today'
                              ? Icons.today_rounded
                              : label == 'Upcoming'
                              ? Icons.upcoming_rounded
                              : Icons.how_to_reg_rounded,
                          color: accent,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          label,
                          style: const TextStyle(
                            color: navy,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${events.length} event${events.length == 1 ? '' : 's'}',
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: events.isEmpty
                        ? const Center(
                            child: Text(
                              'No events to show.',
                              style: TextStyle(color: muted),
                            ),
                          )
                        : ListView.separated(
                            itemCount: events.length > 12 ? 12 : events.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, index) {
                              final event = events[index];
                              final attended = _isEventAttended(event);

                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 11,
                                ),
                                decoration: BoxDecoration(
                                  color: attended
                                      ? const Color(0xFFF0F9F5)
                                      : const Color(0xFFF7F7FB),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: attended
                                        ? const Color(0xFFB8E3CF)
                                        : const Color(0xFFE5E5ED),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      attended
                                          ? Icons.check_circle_rounded
                                          : Icons.event_available_rounded,
                                      color: attended
                                          ? const Color(0xFF159947)
                                          : navy,
                                      size: 23,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            event.name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            '${_formatDate(event)} • ${_formatTimeRange(event)}',
                                            style: const TextStyle(
                                              color: muted,
                                              fontSize: 10.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (attended)
                                      const Text(
                                        'Attended',
                                        style: TextStyle(
                                          color: Color(0xFF159947),
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  bool _isEventAttended(EventItem event) {
    final eventId = event.id;
    return eventId != null && _attendedEventIds.contains(eventId);
  }

  // ===========================================================================
  // HISTORY
  // ===========================================================================

  Widget _buildHistoryCard() {
    final hasRecords = _attendanceCount > 0;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: _openHistory,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE0E1E8)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 16,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F1FA),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.history_rounded, color: navy, size: 24),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Attendance History',
                      style: TextStyle(
                        color: navy,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasRecords
                          ? '$_attendanceCount recorded • Latest: $_latestAttendanceStatus'
                          : 'No attendance records yet',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: muted,
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 7),
                    const Text(
                      'View all attendance records',
                      style: TextStyle(
                        color: Color(0xFF5D6472),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7FB),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.arrow_forward_rounded,
                  color: navy,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // TODAY
  // ===========================================================================

  Widget _buildTodaySection() {
    if (_todayEvents.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: const Color(0xFFD4D4D4)),
        ),
        child: const Column(
          children: [
            Icon(Icons.event_busy_outlined, color: navy, size: 42),
            SizedBox(height: 10),
            Text(
              'No activity today',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 5),
            Text(
              'There are no events scheduled for today.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Today's Events",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        for (final event in _todayEvents) ...[
          _buildEventCard(event, today: true),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  // ===========================================================================
  // UPCOMING
  // ===========================================================================

  Widget _buildUpcomingSection() {
    final upcoming = _upcomingEvents.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Upcoming Events',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
            TextButton(
              onPressed: _openCalendar,
              child: const Text(
                'View Calendar',
                style: TextStyle(color: navy, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final event in upcoming) ...[
          _buildEventCard(event),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  // ===========================================================================
  // EVENT CARD
  // ===========================================================================

  Widget _buildEventCard(EventItem event, {bool today = false}) {
    final attended = _isEventAttended(event);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: attended ? const Color(0xFFF0F9F5) : Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: attended ? const Color(0xFF9FD8BA) : const Color(0xFFE1E1E8),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 70,
            decoration: BoxDecoration(
              color: attended
                  ? const Color(0xFF159947)
                  : today
                  ? gold
                  : navy,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _formatDate(event),
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 3),
                Text(
                  _formatTimeRange(event),
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
                if (event.venue.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    event.venue,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                ],
                if (attended) ...[
                  const SizedBox(height: 6),
                  const Row(
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF159947),
                        size: 14,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'Attendance recorded for this event',
                        style: TextStyle(
                          color: Color(0xFF159947),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (attended)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFDDF4E8),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                '✓ Attended',
                style: TextStyle(
                  color: Color(0xFF159947),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          else if (today)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFFFE9A3),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Today',
                style: TextStyle(
                  color: Color(0xFFFF8A00),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ===========================================================================
  // ERROR
  // ===========================================================================

  Widget _buildError() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 42),
          const SizedBox(height: 10),
          const Text(
            'Unable to load dashboard',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            _error ?? 'Please try again.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              _loadDashboard();
            },
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

  // ===========================================================================
  // PROFILE MENU
  // ===========================================================================

  Future<void> _showProfileMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 24,
                  offset: Offset(0, -6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD7D7DE),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    _profileAvatar(radius: 30),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _fullName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Colors.black,
                            ),
                          ),
                          if (_studentNumber.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              _studentNumber,
                              style: const TextStyle(
                                color: muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Container(
                      width: 38,
                      height: 38,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFF4C8),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.verified_user_outlined,
                        color: navy,
                        size: 21,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Divider(height: 1),
                const SizedBox(height: 10),
                _profileMenuTile(
                  Icons.person_outline_rounded,
                  'Personal Information',
                  'View your student profile',
                  () {
                    Navigator.pop(sheetContext);

                    _openProfile();
                  },
                ),
                _profileMenuTile(
                  Icons.history_rounded,
                  'Attendance History',
                  'Review your attendance records',
                  () {
                    Navigator.pop(sheetContext);

                    _openHistory();
                  },
                ),
                const SizedBox(height: 6),
                Material(
                  color: const Color(0xFFFFF1F0),
                  borderRadius: BorderRadius.circular(15),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    leading: const Icon(
                      Icons.logout_rounded,
                      color: Colors.red,
                    ),
                    title: const Text(
                      'Log Out',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: const Text(
                      'Sign out of this device',
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);

                      _confirmLogout();
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _profileMenuTile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(15),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        leading: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: Color(0xFFF0F0FA),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: navy, size: 21),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 11, color: muted),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, color: muted),
        onTap: onTap,
      ),
    );
  }

  // ===========================================================================
  // LOGOUT
  // ===========================================================================

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Log Out'),
          content: const Text('Are you sure you want to log out?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              style: FilledButton.styleFrom(backgroundColor: navy),
              child: const Text('Yes'),
            ),
          ],
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
      MaterialPageRoute<void>(builder: (_) => const AuthGate()),
      (route) => false,
    );
  }

  // ===========================================================================
  // BOTTOM NAVIGATION
  // ===========================================================================

  Widget _buildBottomNavigation() {
    return MainBottomNavigation(
      currentIndex: 0,
      notificationBadge: _unreadCount,
      onHomeRefresh: () {
        _loadDashboard(showMainLoader: false);
      },
      onScan: _openAttendanceScanner,
    );
  }

  Widget _buildScannerButton() {
    return MainBottomNavigation.scannerButton(
      context,
      onPressed: _openAttendanceScanner,
    );
  }

  // ===========================================================================
  // FORMATTERS
  // ===========================================================================

  String _eventSubtitle(EventItem event) {
    final parts = <String>[_formatTimeRange(event)];

    if (event.venue.isNotEmpty) {
      parts.add(event.venue);
    }

    return parts.join(' • ');
  }

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
        // Try next format.
      }
    }

    return clean;
  }

  String _formatStatus(String value) {
    final clean = value.trim();

    if (clean.isEmpty) {
      return 'Recorded';
    }

    return clean
        .split(RegExp(r'[_\s]+'))
        .where((word) => word.isNotEmpty)
        .map(
          (word) =>
              '${word[0].toUpperCase()}'
              '${word.substring(1).toLowerCase()}',
        )
        .join(' ');
  }
}
