import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/attendance_history_item.dart';
import '../../models/event_item.dart';
import '../../services/attendance_history_service.dart';
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
import '../profile/profile_screen.dart';

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
  static const Color background = Color(0xFFF8F9FC);
  static const Color muted = Color(0xFF808080);

  bool _loading = true;
  bool _dashboardBusy = false;
  bool _syncingOffline = false;

  String? _error;

  List<EventItem> _events = const [];
  List<AttendanceHistoryItem> _historyRecords = const [];

  int _attendanceCount = 0;
  int _unreadCount = 0;
  int _pendingOfflineCount = 0;

  String _latestAttendanceStatus = 'No record';

  Uint8List? _profilePhoto;

  Map<String, dynamic>? _currentUser;
  Map<String, dynamic>? _currentStudent;

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

    final result = [first, middle, last, extension]
        .where((value) => value.isNotEmpty)
        .join(' ');

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
      if (!mounted || !result.success) return;

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

  Widget _profileAvatar({double radius = 22}) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFE2E8F0),
      backgroundImage:
          _profilePhoto != null ? MemoryImage(_profilePhoto!) : null,
      child: _profilePhoto == null
          ? Icon(Icons.person_rounded,
              color: const Color(0xFF64748B), size: radius * 1.2)
          : null,
    );
  }

  Future<void> _loadDashboard({bool showMainLoader = true}) async {
    if (_dashboardBusy) return;
    _dashboardBusy = true;

    if (mounted && showMainLoader) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final pendingBefore =
          await AttendanceService.instance.pendingOfflineCount();

      if (mounted) {
        setState(() {
          _pendingOfflineCount = pendingBefore;
        });
      }

      final eventResult = await EventService.instance.getEvents();
      if (!mounted) return;

      if (pendingBefore > 0) {
        setState(() {
          _syncingOffline = true;
        });

        try {
          final syncResult =
              await AttendanceService.instance.syncPendingAttendances();
          if (mounted) {
            setState(() {
              _pendingOfflineCount = syncResult.remaining;
            });
          }
        } catch (e) {
          debugPrint('HOME OFFLINE SYNC ERROR: $e');
          final remaining =
              await AttendanceService.instance.pendingOfflineCount();
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

      final historyResult =
          await AttendanceHistoryService.instance.getHistory();
      final notificationResult =
          await NotificationService.instance.getNotifications();
      final pendingAfter =
          await AttendanceService.instance.pendingOfflineCount();

      if (!mounted) return;

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
          _historyRecords = historyResult.records;
          _attendanceCount = historyResult.records.length;

          if (historyResult.records.isEmpty) {
            _latestAttendanceStatus = 'No record';
          } else {
            _latestAttendanceStatus = _formatStatus(
              historyResult.records.first.status,
            );
          }
        } else {
          _historyRecords = const [];
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
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load the dashboard.';
      });
    } finally {
      _dashboardBusy = false;
    }
  }

  List<EventItem> get _todayEvents =>
      _events.where((event) => event.isToday).toList();

  List<EventItem> get _upcomingEvents =>
      _events.where((event) => event.isUpcoming).toList();

  int _getAttendanceCountForEvent(EventItem event) {
    if (event.id != null) {
      return _historyRecords.where((r) => r.eventId == event.id).length;
    }
    final cleanName = event.name.trim().toLowerCase();
    return _historyRecords
        .where((r) => r.eventName.trim().toLowerCase() == cleanName)
        .length;
  }

  bool _hasTimeInForEvent(EventItem event) =>
      _getAttendanceCountForEvent(event) >= 1;

  bool _hasTimeOutForEvent(EventItem event) =>
      _getAttendanceCountForEvent(event) >= 2;

  Future<void> _openHistory() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AttendanceHistoryScreen()),
    );
    if (mounted) await _loadDashboard(showMainLoader: false);
  }

  Future<void> _openCalendar() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CalendarScreen()),
    );
    if (mounted) await _loadDashboard(showMainLoader: false);
  }

  Future<void> _openProfile() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
    );
    if (mounted) {
      await _loadProfilePhoto();
      await _loadDashboard(showMainLoader: false);
    }
  }

  Future<void> _openAttendanceScannerForEvent(EventItem event) async {
    final hasTimeIn = _hasTimeInForEvent(event);
    final hasTimeOut = _hasTimeOutForEvent(event);

    final recorded = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AttendanceFaceVerificationScreen(
          event: event,
          studentName: _firstName,
          hasTimeIn: hasTimeIn,
          hasTimeOut: hasTimeOut,
        ),
      ),
    );

    if (recorded == true && mounted) {
      await _loadDashboard(showMainLoader: false);
    }
  }

  Future<void> _openAttendanceScanner() async {
    final today = _todayEvents;

    if (today.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.info_outline_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text('There is no event scheduled for today.'),
            ],
          ),
          backgroundColor: navy,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    if (today.length == 1) {
      _openAttendanceScannerForEvent(today.first);
    } else {
      final selectedEvent = await showModalBottomSheet<EventItem>(
        context: context,
        backgroundColor: Colors.white,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                        fontSize: 22, fontWeight: FontWeight.w800, color: navy),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Choose an event to record attendance.',
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  for (final event in today)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        leading: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: gold.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.event_available_rounded,
                              color: navy),
                        ),
                        title: Text(
                          event.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: navy),
                        ),
                        subtitle: Text(_eventSubtitle(event),
                            style: const TextStyle(fontSize: 12)),
                        trailing:
                            const Icon(Icons.chevron_right_rounded, color: navy),
                        onTap: () => Navigator.pop(sheetContext, event),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );

      if (selectedEvent != null && mounted) {
        _openAttendanceScannerForEvent(selectedEvent);
      }
    }
  }

  void _showEventDetailModal(EventItem event) {
    final count = _getAttendanceCountForEvent(event);
    final isCompleted = count >= 2;
    final isTimeInDone = count == 1;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        event.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: navy,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, color: muted),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? const Color(0xFFDCFCE7)
                        : (isTimeInDone
                            ? const Color(0xFFFEF3C7)
                            : const Color(0xFFEEF2FF)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isCompleted
                            ? Icons.check_circle_rounded
                            : (isTimeInDone
                                ? Icons.hourglass_top_rounded
                                : Icons.event_available_rounded),
                        size: 16,
                        color: isCompleted
                            ? const Color(0xFF15803D)
                            : (isTimeInDone
                                ? const Color(0xFF92400E)
                                : navy),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isCompleted
                            ? 'Attendance Completed (2/2)'
                            : (isTimeInDone
                                ? 'Time-In Recorded (1/2)'
                                : 'Scheduled Today'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: isCompleted
                              ? const Color(0xFF15803D)
                              : (isTimeInDone
                                  ? const Color(0xFF92400E)
                                  : navy),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Divider(color: Color(0xFFE2E8F0)),
                const SizedBox(height: 16),
                _modalInfoRow(
                  Icons.calendar_today_rounded,
                  'Date',
                  _formatDate(event),
                ),
                const SizedBox(height: 12),
                _modalInfoRow(
                  Icons.access_time_rounded,
                  'Schedule Window',
                  _formatTimeRange(event),
                ),
                if (event.venue.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _modalInfoRow(
                    Icons.location_on_outlined,
                    'Venue',
                    event.venue,
                  ),
                ],
                if (event.description.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Event Details',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: navy,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    event.description,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF475569),
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openAttendanceScannerForEvent(event);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: navy,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                    label: Text(
                      isTimeInDone ? 'Scan Time-Out' : 'Scan Face Attendance',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _modalInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: navy),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: muted),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: navy,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

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
                onRefresh: () => _loadDashboard(showMainLoader: false),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(18, 22, 18, 115),
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Today's Activity",
                          style: TextStyle(
                            color: navy,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: navy.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            DateFormat('E, MMM d').format(DateTime.now()),
                            style: const TextStyle(
                              color: navy,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 80),
                        child: Center(
                            child: CircularProgressIndicator(color: navy)),
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
                          const SizedBox(height: 26),
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

  Widget _buildHeader() {
    return Container(
      height: 84,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: navy,
        boxShadow: [
          BoxShadow(
              color: Color(0x1A080878), blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: gold, width: 2),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.school_rounded, color: navy, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Welcome, $_firstName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (_studentNumber.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: gold,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _studentNumber,
                            style: const TextStyle(
                              color: Color(0xFFC0C0E8),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
                const SizedBox(width: 10),
                InkWell(
                  borderRadius: BorderRadius.circular(30),
                  onTap: _showProfileMenu,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: gold, width: 2),
                    ),
                    child: _profileAvatar(radius: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingOfflineCard() {
    final syncing = _syncingOffline;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: gold.withValues(alpha: 0.6)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x08000000), blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: gold.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(14),
            ),
            child: syncing
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: navy),
                  )
                : const Icon(Icons.cloud_upload_outlined,
                    color: navy, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  syncing
                      ? 'Synchronizing attendance'
                      : 'Pending offline attendance',
                  style: const TextStyle(
                      color: navy, fontSize: 14, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  syncing
                      ? 'Verifying saved records with server.'
                      : '$_pendingOfflineCount record${_pendingOfflineCount == 1 ? '' : 's'} waiting for sync.',
                  style: const TextStyle(
                      color: Color(0xFF786200), fontSize: 11.5, height: 1.35),
                ),
              ],
            ),
          ),
          if (!syncing)
            IconButton(
              tooltip: 'Sync now',
              onPressed: () => _loadDashboard(showMainLoader: false),
              icon: const Icon(Icons.sync_rounded, color: navy),
            ),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    return Row(
      children: [
        Expanded(
          child: _summaryStatCard(
            title: 'Today',
            count: '${_todayEvents.length}',
            icon: Icons.event_available_rounded,
            iconBgColor: const Color(0xFFEEF2FF),
            iconColor: navy,
            accentColor: const Color(0xFF6366F1),
            onTap: () => _showSummaryDetails('Today'),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _summaryStatCard(
            title: 'Upcoming',
            count: '${_upcomingEvents.length}',
            icon: Icons.calendar_month_rounded,
            iconBgColor: const Color(0xFFFFFBEB),
            iconColor: const Color(0xFFD97706),
            accentColor: const Color(0xFFF59E0B),
            onTap: () => _showSummaryDetails('Upcoming'),
          ),
        ),
      ],
    );
  }

  Widget _summaryStatCard({
    required String title,
    required String count,
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(height: 12),
              Text(
                count,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: navy,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: muted,
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
        final Color accent = label == 'Today'
            ? const Color(0xFF6366F1)
            : const Color(0xFFF59E0B);

        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          label == 'Today'
                              ? Icons.today_rounded
                              : Icons.upcoming_rounded,
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
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: events.isEmpty
                        ? const Center(
                            child: Text('No events scheduled.',
                                style: TextStyle(color: muted)),
                          )
                        : ListView.separated(
                            itemCount: events.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, index) {
                              final event = events[index];
                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: const Color(0xFFE2E8F0)),
                                ),
                                child: Text(event.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: navy)),
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

  Widget _buildHistoryCard() {
    final hasRecords = _attendanceCount > 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openHistory,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x06000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: navy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.history_rounded, color: navy, size: 26),
              ),
              const SizedBox(width: 14),
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
                    const SizedBox(height: 3),
                    Text(
                      hasRecords
                          ? '$_attendanceCount recorded • Latest: $_latestAttendanceStatus'
                          : 'No attendance records yet',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded,
                  color: navy, size: 14),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTodaySection() {
    if (_todayEvents.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Column(
          children: [
            Icon(Icons.event_busy_outlined, color: navy, size: 40),
            SizedBox(height: 10),
            Text('No activity today',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: navy)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Today's Events",
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: navy)),
        const SizedBox(height: 12),
        for (final event in _todayEvents) ...[
          _buildEventCard(event, today: true),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildUpcomingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Upcoming Events',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: navy)),
            TextButton(
              onPressed: _openCalendar,
              child: const Text('View Calendar',
                  style: TextStyle(color: navy, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final event in _upcomingEvents.take(3)) ...[
          _buildEventCard(event),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildEventCard(EventItem event, {bool today = false}) {
    final count = _getAttendanceCountForEvent(event);
    final isCompleted = count >= 2;
    final isTimeInDone = count == 1;

    final Color statusColor = isCompleted
        ? const Color(0xFF16A34A)
        : (isTimeInDone ? const Color(0xFFD97706) : (today ? gold : navy));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showEventDetailModal(event),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isCompleted
                ? const Color(0xFFF0FDF4)
                : (isTimeInDone ? const Color(0xFFFFFBEB) : Colors.white),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isCompleted
                  ? const Color(0xFFBBF7D0)
                  : (isTimeInDone ? const Color(0xFFFDE68A) : const Color(0xFFE2E8F0)),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x06000000),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 72,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            event.name,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold, color: navy),
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: muted, size: 20),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${_formatDate(event)} • ${_formatTimeRange(event)}',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 40),
          const SizedBox(height: 12),
          Text(_error ?? 'Error loading dashboard.'),
        ],
      ),
    );
  }

  Future<void> _showProfileMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.person_rounded, color: navy),
                  title: Text(_fullName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(_studentNumber),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openProfile();
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.logout_rounded, color: Colors.red),
                  title: const Text('Log Out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmLogout();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmLogout() async {
    await AuthService.instance.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const AuthGate()),
      (route) => false,
    );
  }

  Widget _buildBottomNavigation() {
    return MainBottomNavigation(
      currentIndex: 0,
      notificationBadge: _unreadCount,
      onHomeRefresh: () => _loadDashboard(showMainLoader: false),
      onScan: _openAttendanceScanner,
    );
  }

  Widget? _buildScannerButton() {
    return MainBottomNavigation.scannerButton(
      context,
      currentIndex: 0,
      onPressed: _openAttendanceScanner,
    );
  }

  String _eventSubtitle(EventItem event) {
    return _formatTimeRange(event);
  }

  String _formatDate(EventItem event) {
    final date = event.date;
    if (date == null) return event.eventDate;
    return DateFormat('MMMM d, yyyy').format(date);
  }

  String _formatTimeRange(EventItem event) {
    return '${event.startTime} - ${event.endTime}';
  }

  String _formatStatus(String value) {
    return value.toUpperCase();
  }
}