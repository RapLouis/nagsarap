import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../main.dart';
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
  static const Color muted = Color(0xFF64748B);

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

  Widget _profileAvatar({double radius = 18}) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFE2E8F0),
      backgroundImage:
          _profilePhoto != null ? MemoryImage(_profilePhoto!) : null,
      child: _profilePhoto == null
          ? Icon(
              Icons.badge_rounded,
              color: const Color(0xFF64748B),
              size: radius * 1.2,
            )
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

 bool _isEventWindowActive(EventItem event) {
    final now = DateTime.now();

    final timeInStr = _getTimeInWindow(event);
    final timeOutStr = _getTimeOutWindow(event);

    final timeInParts = timeInStr.split('–').map((s) => s.trim()).toList();
    final timeOutParts = timeOutStr.split('–').map((s) => s.trim()).toList();

    final inStart = timeInParts.isNotEmpty ? _parseTimeToDateTime(timeInParts[0]) : null;
    final inEnd = timeInParts.length > 1 ? _parseTimeToDateTime(timeInParts[1]) : null;

    final outStart = timeOutParts.isNotEmpty ? _parseTimeToDateTime(timeOutParts[0]) : null;
    final outEnd = timeOutParts.length > 1 ? _parseTimeToDateTime(timeOutParts[1]) : null;

    final count = _getAttendanceCountForEvent(event);
    if (count >= 2) return false;

    const margin = Duration(minutes: 15);

    // 1. Check Time-Out Window (if Time-Out not yet completed)
    if (count < 2 && outStart != null) {
      final startBound = outStart.subtract(margin);
      final endBound = (outEnd ?? outStart.add(const Duration(hours: 4))).add(margin);
      if ((now.isAfter(startBound) || now.isAtSameMomentAs(startBound)) &&
          (now.isBefore(endBound) || now.isAtSameMomentAs(endBound))) {
        return true;
      }
    }

    // 2. Check Time-In Window (if Time-In not yet completed)
    if (count == 0 && inStart != null) {
      final startBound = inStart.subtract(margin);
      final endBound = (inEnd ?? outStart ?? inStart.add(const Duration(hours: 4))).add(margin);
      if ((now.isAfter(startBound) || now.isAtSameMomentAs(startBound)) &&
          (now.isBefore(endBound) || now.isAtSameMomentAs(endBound))) {
        return true;
      }
    }

    return false;
  }

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
              Icon(Icons.info_outline_rounded, color: Colors.white, size: 18),
              SizedBox(width: 10),
              Text('There is no event scheduled for today.'),
            ],
          ),
          backgroundColor: navy,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
      return;
    }

    if (today.length == 1) {
      final event = today.first;
      if (!_isEventWindowActive(event)) {
        _showEventDetailModal(event);
        return;
      }
      _openAttendanceScannerForEvent(event);
    } else {
      final selectedEvent = await showModalBottomSheet<EventItem>(
        context: context,
        backgroundColor: Theme.of(context).cardColor,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (BuildContext sheetContext) {
          final isDark = themeController.isDarkMode;

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select Event',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : navy,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Choose an event to record attendance.',
                    style: TextStyle(color: muted, fontSize: 12.5),
                  ),
                  const SizedBox(height: 16),
                  for (final event in today) ...[
                    Builder(
                      builder: (ctx) {
                        final isActive = _isEventWindowActive(event);
                        final count = _getAttendanceCountForEvent(event);
                        final isCompleted = count >= 2;

                        return Opacity(
                          opacity: isActive ? 1.0 : 0.5,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF1E293B)
                                  : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isActive
                                    ? gold
                                    : (isDark
                                        ? const Color(0xFF334155)
                                        : const Color(0xFFE2E8F0)),
                              ),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 2,
                              ),
                              leading: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: (isActive ? gold : muted)
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  isActive
                                      ? Icons.event_available_rounded
                                      : Icons.lock_rounded,
                                  color: isActive ? gold : muted,
                                  size: 18,
                                ),
                              ),
                              title: Text(
                                event.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: isDark ? Colors.white : navy,
                                ),
                              ),
                              subtitle: Text(
                                isCompleted
                                    ? 'Completed (2/2)'
                                    : (isActive
                                        ? 'Window Active'
                                        : 'Window Closed / Locked'),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: isActive ? const Color(0xFF16A34A) : muted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              trailing: Icon(
                                isActive
                                    ? Icons.arrow_forward_ios_rounded
                                    : Icons.lock_outline_rounded,
                                color: isActive ? muted : Colors.grey,
                                size: 14,
                              ),
                              onTap: isActive
                                  ? () => Navigator.pop(sheetContext, event)
                                  : () {
                                      Navigator.pop(sheetContext);
                                      _showEventDetailModal(event);
                                    },
                            ),
                          ),
                        );
                      },
                    ),
                  ],
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
    final isWindowActive = _isEventWindowActive(event);
    final isDark = themeController.isDarkMode;

    final timeInWindow = _getTimeInWindow(event);
    final timeOutWindow = _getTimeOutWindow(event);
    final venueLocation = event.venue.isNotEmpty ? event.venue : 'Main Campus';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF475569)
                          : const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        event.name,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : navy,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: Icon(
                        Icons.close_rounded,
                        color: isDark ? Colors.white70 : muted,
                        size: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (event.description.isNotEmpty) ...[
                  Text(
                    'Event Details',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : navy,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    event.description,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: isDark ? const Color(0xFFCBD5E1) : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? const Color(0xFFDCFCE7)
                        : (isTimeInDone
                            ? const Color(0xFFFEF3C7)
                            : (isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFEEF2FF))),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isCompleted
                            ? Icons.verified_rounded
                            : (isTimeInDone
                                ? Icons.pending_actions_rounded
                                : Icons.schedule_rounded),
                        size: 14,
                        color: isCompleted
                            ? const Color(0xFF15803D)
                            : (isTimeInDone
                                ? const Color(0xFF92400E)
                                : (isDark ? gold : navy)),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Attendance Status ($count/2)',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: isCompleted
                              ? const Color(0xFF15803D)
                              : (isTimeInDone
                                  ? const Color(0xFF92400E)
                                  : (isDark ? Colors.white : navy)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Divider(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
                const SizedBox(height: 12),
                _modalInfoRow(
                  Icons.badge_rounded,
                  'Student Name',
                  _fullName,
                ),
                const SizedBox(height: 10),
                _modalInfoRow(
                  Icons.event_available_rounded,
                  'Date',
                  _formatDate(event),
                ),
                const SizedBox(height: 10),
                _modalInfoRow(
                  Icons.login_rounded,
                  'Time-In Window',
                  timeInWindow,
                ),
                const SizedBox(height: 10),
                _modalInfoRow(
                  Icons.logout_rounded,
                  'Time-Out Window',
                  timeOutWindow,
                ),
                const SizedBox(height: 10),
                _modalInfoRow(
                  Icons.place_rounded,
                  'Venue',
                  venueLocation,
                ),
                const SizedBox(height: 20),
                if (isWindowActive && !isCompleted)
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _openAttendanceScannerForEvent(event);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? gold : navy,
                        foregroundColor: isDark ? navy : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                      label: Text(
                        isTimeInDone ? 'Scan Time-Out QR' : 'Scan Face Attendance',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isCompleted ? Icons.task_alt_rounded : Icons.lock_rounded,
                          size: 16,
                          color: isCompleted ? const Color(0xFF16A34A) : muted,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isCompleted
                              ? 'Attendance Completed Successfully'
                              : 'Attendance Window Closed',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: isCompleted
                                ? const Color(0xFF16A34A)
                                : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                          ),
                        ),
                      ],
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
    final isDark = themeController.isDarkMode;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: gold),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: muted),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : navy,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatTime12Hour(String timeStr) {
    final clean = timeStr.trim();
    if (clean.isEmpty || clean.toLowerCase() == 'tba') return 'TBA';

    const formats = ['HH:mm:ss', 'HH:mm', 'h:mm a', 'hh:mm a'];
    for (final format in formats) {
      try {
        final parsed = DateFormat(format, 'en_US').parseLoose(clean);
        return DateFormat('h:mm a').format(parsed);
      } catch (_) {}
    }
    return clean;
  }

  DateTime? _parseTimeToDateTime(String timeStr) {
    final clean = timeStr.trim();
    if (clean.isEmpty || clean.toLowerCase() == 'tba') return null;
    final now = DateTime.now();
    const formats = ['HH:mm:ss', 'HH:mm', 'h:mm a', 'hh:mm a'];
    for (final format in formats) {
      try {
        final parsed = DateFormat(format, 'en_US').parseLoose(clean);
        return DateTime(now.year, now.month, now.day, parsed.hour, parsed.minute, parsed.second);
      } catch (_) {}
    }
    return null;
  }

  String _formatDateTime12Hour(DateTime dt) {
    return DateFormat('h:mm a').format(dt);
  }

  String _getTimeInWindow(EventItem event) {
    final combinedWindow = _extractEventProperty(event, [
      'time_in_window',
      'timeInWindow',
      'time_in_range',
      'time_in_slot',
      'time_in_text',
      'timeInText',
    ]);

    if (combinedWindow != null && combinedWindow.contains(RegExp(r'[-–]'))) {
      final parts = combinedWindow.split(RegExp(r'[-–]'));
      if (parts.length >= 2) {
        final s = _formatTime12Hour(parts[0].trim());
        final e = _formatTime12Hour(parts[1].trim());
        if (s.isNotEmpty && e.isNotEmpty) return '$s – $e';
      }
    }

    final rawStart = _extractEventProperty(event, [
      'time_in_start',
      'timeInStart',
      'time_in_start_time',
      'timeInStartTime',
      'time_in_window_start',
      'timeInWindowStart',
      'time_in_from',
      'timeInFrom',
      'time_in_open',
      'timeInOpen',
      'timein_start',
      'in_start',
    ]) ?? event.startTime;

    final rawEnd = _extractEventProperty(event, [
      'time_in_end',
      'timeInEnd',
      'time_in_end_time',
      'timeInEndTime',
      'time_in_window_end',
      'timeInWindowEnd',
      'time_in_to',
      'timeInTo',
      'time_in_close',
      'timeInClose',
      'timein_end',
      'in_end',
    ]);

    final startStr = _formatTime12Hour(rawStart);

    if (rawEnd != null && rawEnd.isNotEmpty) {
      final endStr = _formatTime12Hour(rawEnd);
      return '$startStr – $endStr';
    }

    final rawOutStart = _extractEventProperty(event, [
      'time_out_start',
      'timeOutStart',
      'time_out_start_time',
      'timeOutStartTime',
      'time_out_window_start',
      'timeOutWindowStart',
      'time_out_from',
      'timeOutFrom',
      'time_out_open',
      'timeOutOpen',
      'timeout_start',
      'out_start',
    ]);

    if (rawOutStart != null && rawOutStart.isNotEmpty) {
      final endStr = _formatTime12Hour(rawOutStart);
      return '$startStr – $endStr';
    }

    final dtStart = _parseTimeToDateTime(rawStart);
    final dtEnd = _parseTimeToDateTime(event.endTime);

    if (dtStart != null && dtEnd != null && dtEnd.isAfter(dtStart)) {
      final midDiff = dtEnd.difference(dtStart).inSeconds ~/ 2;
      final dtMid = dtStart.add(Duration(seconds: midDiff));
      return '$startStr – ${_formatDateTime12Hour(dtMid)}';
    }

    return '$startStr – ${_formatTime12Hour(event.endTime)}';
  }

  String _getTimeOutWindow(EventItem event) {
    final combinedWindow = _extractEventProperty(event, [
      'time_out_window',
      'timeOutWindow',
      'time_out_range',
      'time_out_slot',
      'time_out_text',
      'timeOutText',
    ]);

    if (combinedWindow != null && combinedWindow.contains(RegExp(r'[-–]'))) {
      final parts = combinedWindow.split(RegExp(r'[-–]'));
      if (parts.length >= 2) {
        final s = _formatTime12Hour(parts[0].trim());
        final e = _formatTime12Hour(parts[1].trim());
        if (s.isNotEmpty && e.isNotEmpty) return '$s – $e';
      }
    }

    final rawEnd = _extractEventProperty(event, [
      'time_out_end',
      'timeOutEnd',
      'time_out_end_time',
      'timeOutEndTime',
      'time_out_window_end',
      'timeOutWindowEnd',
      'time_out_to',
      'timeOutTo',
      'time_out_close',
      'timeOutClose',
      'timeout_end',
      'out_end',
    ]) ?? event.endTime;

    final rawStart = _extractEventProperty(event, [
      'time_out_start',
      'timeOutStart',
      'time_out_start_time',
      'timeOutStartTime',
      'time_out_window_start',
      'timeOutWindowStart',
      'time_out_from',
      'timeOutFrom',
      'time_out_open',
      'timeOutOpen',
      'timeout_start',
      'out_start',
    ]);

    final endStr = _formatTime12Hour(rawEnd);

    if (rawStart != null && rawStart.isNotEmpty) {
      final startStr = _formatTime12Hour(rawStart);
      return '$startStr – $endStr';
    }

    final rawInEnd = _extractEventProperty(event, [
      'time_in_end',
      'timeInEnd',
      'time_in_end_time',
      'timeInEndTime',
      'time_in_window_end',
      'timeInWindowEnd',
      'time_in_to',
      'timeInTo',
      'time_in_close',
      'timeInClose',
      'timein_end',
      'in_end',
    ]);

    if (rawInEnd != null && rawInEnd.isNotEmpty) {
      final startStr = _formatTime12Hour(rawInEnd);
      return '$startStr – $endStr';
    }

    final dtStart = _parseTimeToDateTime(event.startTime);
    final dtEnd = _parseTimeToDateTime(rawEnd);

    if (dtStart != null && dtEnd != null && dtEnd.isAfter(dtStart)) {
      final midDiff = dtEnd.difference(dtStart).inSeconds ~/ 2;
      final dtMid = dtStart.add(Duration(seconds: midDiff));
      return '${_formatDateTime12Hour(dtMid)} – $endStr';
    }

    return '${_formatTime12Hour(event.startTime)} – $endStr';
  }

  String _getDisplayWindow(EventItem event) {
    return _getTimeInWindow(event);
  }

  String? _findInMap(Map map, List<String> targetKeys) {
    final cleanTargets = targetKeys.map((k) => k.toLowerCase().replaceAll('_', '')).toList();

    for (final entry in map.entries) {
      final keyStr = entry.key.toString().toLowerCase().replaceAll('_', '');
      if (cleanTargets.contains(keyStr) && entry.value != null) {
        final val = entry.value.toString().trim();
        if (val.isNotEmpty && val.toLowerCase() != 'null') {
          return val;
        }
      }
    }

    for (final value in map.values) {
      if (value is Map) {
        final found = _findInMap(value, targetKeys);
        if (found != null) return found;
      } else if (value is List) {
        for (final item in value) {
          if (item is Map) {
            final found = _findInMap(item, targetKeys);
            if (found != null) return found;
          }
        }
      }
    }

    return null;
  }

  String? _extractEventProperty(EventItem event, List<String> keys) {
    final foundInRaw = _findInMap(event.raw, keys);
    if (foundInRaw != null) return foundInRaw;

    final cleanTargets = keys.map((k) => k.toLowerCase().replaceAll('_', '')).toList();
    for (final entry in event.raw.entries) {
      final keyClean = entry.key.toString().toLowerCase().replaceAll('_', '');
      if (cleanTargets.contains(keyClean) && entry.value != null) {
        final val = entry.value.toString().trim();
        if (val.isNotEmpty && val.toLowerCase() != 'null') {
          return val;
        }
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeController.isDarkMode;
    final dateString = DateFormat('EEE, MMM d').format(DateTime.now());

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(68),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : navy,
            border: Border(
              bottom: BorderSide(
                color: isDark ? const Color(0xFF334155) : Colors.transparent,
              ),
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  SizedBox(
                    width: 52,
                    height: 52,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Transform.scale(
                        scale: 1.45,
                        child: Image.asset(
                          'lib/screens/images/logo.jpeg',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
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
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (_studentNumber.isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 4,
                              height: 4,
                              decoration: const BoxDecoration(
                                color: gold,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _studentNumber,
                              style: const TextStyle(
                                color: Color(0xFFCBD5E1),
                                fontSize: 11,
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
                    borderRadius: BorderRadius.circular(20),
                    onTap: _openProfile,
                    child: Container(
                      padding: const EdgeInsets.all(1.5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: gold, width: 1.5),
                      ),
                      child: _profileAvatar(radius: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        color: gold,
        onRefresh: () => _loadDashboard(showMainLoader: false),
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: gold),
              )
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
                children: [
                  if (_pendingOfflineCount > 0 || _syncingOffline) ...[
                    _buildPendingOfflineCard(),
                    const SizedBox(height: 14),
                  ],
                  _buildHeaderSection(dateString),
                  const SizedBox(height: 14),
                  _buildMetricsRow(),
                  const SizedBox(height: 10),
                  _buildHistoryCard(),
                  const SizedBox(height: 20),
                  _buildEventsSectionHeader(),
                  const SizedBox(height: 10),
                  if (_error != null)
                    _buildErrorWidget()
                  else if (_todayEvents.isEmpty)
                    _buildEmptyEventsWidget()
                  else
                    ..._todayEvents.map((evt) => _buildEventCard(evt, today: true)),
                  if (_upcomingEvents.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _buildUpcomingSection(),
                  ],
                ],
              ),
      ),
      bottomNavigationBar: MainBottomNavigation(
        currentIndex: 0,
        notificationBadge: _unreadCount,
        onHomeRefresh: () => _loadDashboard(showMainLoader: false),
        onScan: _openAttendanceScanner,
      ),
      floatingActionButton: MainBottomNavigation.scannerButton(
        context,
        currentIndex: 0,
        onPressed: _openAttendanceScanner,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _buildHeaderSection(String dateString) {
    final isDark = themeController.isDarkMode;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Today's Activity",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: isDark ? Colors.white : navy,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              'Overview of schedule & check-ins',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_today_rounded, size: 12, color: isDark ? gold : navy),
              const SizedBox(width: 5),
              Text(
                dateString,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? gold : navy,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricsRow() {
    final isDark = themeController.isDarkMode;

    return Row(
      children: [
        Expanded(
          child: _metricBox(
            title: 'Today',
            count: '${_todayEvents.length}',
            subtitle: 'Scheduled',
            icon: Icons.today_rounded,
            iconColor: const Color(0xFF3B82F6),
            isDark: isDark,
            onTap: () => _showSummaryDetails('Today'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _metricBox(
            title: 'Upcoming',
            count: '${_upcomingEvents.length}',
            subtitle: 'Future events',
            icon: Icons.upcoming_rounded,
            iconColor: const Color(0xFFF59E0B),
            isDark: isDark,
            onTap: () => _showSummaryDetails('Upcoming'),
          ),
        ),
      ],
    );
  }

  Widget _metricBox({
    required String title,
    required String count,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, color: iconColor, size: 18),
                    ),
                    Text(
                      count,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : navy,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: muted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryCard() {
    final isDark = themeController.isDarkMode;
    final hasRecords = _attendanceCount > 0;

    return InkWell(
      onTap: _openHistory,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: gold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.history_toggle_off_rounded,
                color: gold,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Attendance History Logs',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : navy,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    hasRecords
                        ? '$_attendanceCount recorded • Latest: $_latestAttendanceStatus'
                        : 'No attendance records logged yet',
                    style: const TextStyle(
                      fontSize: 11,
                      color: muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: muted,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventsSectionHeader() {
    final isDark = themeController.isDarkMode;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(Icons.event_note_rounded, size: 16, color: isDark ? gold : navy),
            const SizedBox(width: 6),
            Text(
              "Today's Events",
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : navy,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
        if (_todayEvents.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${_todayEvents.length} Active',
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF10B981),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildUpcomingSection() {
    final isDark = themeController.isDarkMode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.upcoming_rounded, size: 16, color: isDark ? gold : navy),
                const SizedBox(width: 6),
                Text(
                  'Upcoming Events',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : navy,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: _openCalendar,
              style: TextButton.styleFrom(
                foregroundColor: gold,
                padding: EdgeInsets.zero,
                minimumSize: const Size(50, 30),
              ),
              child: const Text(
                'View Calendar',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final event in _upcomingEvents.take(3)) ...[
          _buildEventCard(event),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildEventCard(EventItem event, {bool today = false}) {
    final isDark = themeController.isDarkMode;

    final timeInWindow = _getTimeInWindow(event);
    final timeOutWindow = _getTimeOutWindow(event);

    final count = _getAttendanceCountForEvent(event);
    final isCompleted = count >= 2;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCompleted
              ? const Color(0xFF86EFAC)
              : (count == 1
                  ? const Color(0xFFFDE68A)
                  : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0))),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showEventDetailModal(event),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        event.name,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : navy,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isCompleted
                            ? const Color(0xFFDCFCE7)
                            : (count == 1
                                ? const Color(0xFFFEF3C7)
                                : navy.withValues(alpha: isDark ? 0.2 : 0.06)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$count/2',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: isCompleted
                              ? const Color(0xFF15803D)
                              : (count == 1
                                  ? const Color(0xFF92400E)
                                  : gold),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.login_rounded,
                      size: 13,
                      color: Color(0xFF16A34A),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Time-In: $timeInWindow',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(
                      Icons.logout_rounded,
                      size: 13,
                      color: Color(0xFFDC2626),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Time-Out: $timeOutWindow',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                if (event.venue.isNotEmpty &&
                    event.venue != 'Unspecified Venue') ...[
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(
                        Icons.place_rounded,
                        size: 13,
                        color: Color(0xFF3B82F6),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          event.venue,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: muted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPendingOfflineCard() {
    final syncing = _syncingOffline;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: gold.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: gold.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: syncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: navy,
                    ),
                  )
                : const Icon(
                    Icons.cloud_sync_rounded,
                    color: navy,
                    size: 20,
                  ),
          ),
          const SizedBox(width: 12),
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
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  syncing
                      ? 'Verifying saved records with server.'
                      : '$_pendingOfflineCount record${_pendingOfflineCount == 1 ? '' : 's'} waiting for sync.',
                  style: const TextStyle(
                    color: Color(0xFF786200),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (!syncing)
            IconButton(
              tooltip: 'Sync now',
              onPressed: () => _loadDashboard(showMainLoader: false),
              icon: const Icon(Icons.sync_rounded, color: navy, size: 20),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyEventsWidget() {
    final isDark = themeController.isDarkMode;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.event_busy_rounded,
            size: 32,
            color: isDark ? gold : navy,
          ),
          const SizedBox(height: 8),
          Text(
            'No events scheduled today',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Check back later or view upcoming events in Calendar.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: muted),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget() {
    final isDark = themeController.isDarkMode;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 30),
          const SizedBox(height: 6),
          Text(
            _error ?? 'Error loading events.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: muted),
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: () => _loadDashboard(),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? gold : navy,
              foregroundColor: isDark ? navy : Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Retry', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Future<void> _showSummaryDetails(String label) async {
    final events = label == 'Today' ? _todayEvents : _upcomingEvents;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final isDark = themeController.isDarkMode;
        final Color accent = label == 'Today'
            ? const Color(0xFF3B82F6)
            : const Color(0xFFF59E0B);

        return Dialog(
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 440),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          label == 'Today'
                              ? Icons.today_rounded
                              : Icons.upcoming_rounded,
                          color: accent,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '$label Events',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : navy,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: Icon(
                          Icons.close_rounded,
                          color: isDark ? Colors.white70 : muted,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: events.isEmpty
                        ? const Center(
                            child: Text(
                              'No events scheduled.',
                              style: TextStyle(color: muted, fontSize: 12),
                            ),
                          )
                        : ListView.separated(
                            itemCount: events.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, index) {
                              final event = events[index];
                              return Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF0F172A)
                                      : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isDark
                                        ? const Color(0xFF334155)
                                        : const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      event.name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        color: isDark ? Colors.white : navy,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${_formatDate(event)} • ${_getDisplayWindow(event)}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: muted,
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

  String _formatDate(EventItem event) {
    final date = event.date;
    if (date == null) return event.eventDate;
    return DateFormat('MMMM d, yyyy').format(date);
  }

  String _formatStatus(String value) {
    return value.toUpperCase();
  }
}