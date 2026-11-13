import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  bool _readBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1';
    }
    return false;
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

  Widget _profileAvatar({double radius = 17}) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFE2E8F0),
      backgroundImage:
          _profilePhoto != null ? MemoryImage(_profilePhoto!) : null,
      child: _profilePhoto == null
          ? Icon(
              Icons.person_rounded,
              color: navy,
              size: radius * 1.15,
            )
          : null,
    );
  }

  Future<void> _reloadPage() async {
    HapticFeedback.lightImpact();
    await Future.wait([
      _loadDashboard(showMainLoader: true),
      _restoreIdentity(),
      _loadProfilePhoto(),
    ]);
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
        } else {
          _historyRecords = const [];
          _attendanceCount = 0;
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

  bool _hasRawTimeIn(EventItem event) {
    final raw = event.raw;
    return _readBool(
      raw['has_time_in'] ??
          raw['student_has_time_in'] ??
          raw['time_in_recorded'],
    );
  }

  bool _hasRawTimeOut(EventItem event) {
    final raw = event.raw;
    return _readBool(
      raw['has_time_out'] ??
          raw['student_has_time_out'] ??
          raw['time_out_recorded'],
    );
  }

  int _getAttendanceCountForEvent(EventItem event) {
    int historyCount = 0;
    if (event.id != null) {
      historyCount = _historyRecords.where((r) => r.eventId == event.id).length;
    } else {
      final cleanName = event.name.trim().toLowerCase();
      historyCount = _historyRecords
          .where((r) => r.eventName.trim().toLowerCase() == cleanName)
          .length;
    }

    int rawCount = 0;
    if (_hasRawTimeIn(event)) rawCount++;
    if (_hasRawTimeOut(event)) rawCount++;

    return historyCount > rawCount ? historyCount : rawCount;
  }

  bool _hasTimeInForEvent(EventItem event) =>
      _hasRawTimeIn(event) || _getAttendanceCountForEvent(event) >= 1;

  bool _hasTimeOutForEvent(EventItem event) =>
      _hasRawTimeOut(event) || _getAttendanceCountForEvent(event) >= 2;

  bool _isEventWindowActive(EventItem event) {
    final now = DateTime.now();

    final timeInStr = _getTimeInWindow(event);
    final timeOutStr = _getTimeOutWindow(event);

    final timeInParts = timeInStr.split('–').map((s) => s.trim()).toList();
    final timeOutParts = timeOutStr.split('–').map((s) => s.trim()).toList();

    final inStart =
        timeInParts.isNotEmpty ? _parseTimeToDateTime(timeInParts[0]) : null;
    final inEnd =
        timeInParts.length > 1 ? _parseTimeToDateTime(timeInParts[1]) : null;

    final outStart =
        timeOutParts.isNotEmpty ? _parseTimeToDateTime(timeOutParts[0]) : null;
    final outEnd =
        timeOutParts.length > 1 ? _parseTimeToDateTime(timeOutParts[1]) : null;

    final count = _getAttendanceCountForEvent(event);
    if (count >= 2) return false;

    const margin = Duration(minutes: 15);

    // 1. Check Time-Out Window (if Time-Out not yet completed)
    if (count < 2 && outStart != null) {
      final startBound = outStart.subtract(margin);
      DateTime rawEnd = outEnd ?? outStart.add(const Duration(hours: 4));
      if (rawEnd.isBefore(outStart)) {
        rawEnd = rawEnd.add(const Duration(days: 1));
      }
      final endBound = rawEnd.add(margin);

      if ((now.isAfter(startBound) || now.isAtSameMomentAs(startBound)) &&
          (now.isBefore(endBound) || now.isAtSameMomentAs(endBound))) {
        return true;
      }
    }

    // 2. Check Time-In Window (if Time-In not yet completed)
    if (count == 0 && inStart != null) {
      final startBound = inStart.subtract(margin);
      DateTime rawEnd =
          inEnd ?? outStart ?? inStart.add(const Duration(hours: 4));
      if (rawEnd.isBefore(inStart)) {
        rawEnd = rawEnd.add(const Duration(days: 1));
      }
      final endBound = rawEnd.add(margin);

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
          timeInWindow: _getTimeInWindow(event),
          timeOutWindow: _getTimeOutWindow(event),
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
              Icon(Icons.info_outline_rounded, color: gold, size: 18),
              SizedBox(width: 10),
              Text('No event is scheduled for today.'),
            ],
          ),
          backgroundColor: navy,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                    'Choose an active event to record attendance.',
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
                          opacity: isActive ? 1.0 : 0.6,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF1E293B)
                                  : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isActive
                                    ? gold
                                    : (isDark
                                        ? const Color(0xFF334155)
                                        : const Color(0xFFE2E8F0)),
                                width: isActive ? 1.4 : 1.0,
                              ),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 4,
                              ),
                              leading: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: (isActive
                                          ? const Color(0xFF10B981)
                                          : muted)
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  isActive
                                      ? Icons.qr_code_scanner_rounded
                                      : Icons.lock_clock_rounded,
                                  color: isActive
                                      ? const Color(0xFF10B981)
                                      : muted,
                                  size: 19,
                                ),
                              ),
                              title: Text(
                                event.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: isDark ? Colors.white : navy,
                                ),
                              ),
                              subtitle: Text(
                                isCompleted
                                    ? 'Completed (2/2)'
                                    : (isActive
                                        ? 'Open now for verification'
                                        : 'Outside attendance window'),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: isActive
                                      ? const Color(0xFF16A34A)
                                      : muted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              trailing: Icon(
                                isActive
                                    ? Icons.arrow_forward_ios_rounded
                                    : Icons.info_outline_rounded,
                                color: isActive ? navy : muted,
                                size: 15,
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
    final venueLocation =
        event.venue.isNotEmpty ? event.venue : 'Main Campus';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.name,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : navy,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isCompleted
                                  ? const Color(0xFFDCFCE7)
                                  : (isTimeInDone
                                      ? const Color(0xFFFEF3C7)
                                      : (isDark
                                          ? const Color(0xFF334155)
                                          : const Color(0xFFEEF2FF))),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isCompleted
                                  ? 'Completed ($count/2)'
                                  : (isTimeInDone
                                      ? 'Time-In Recorded ($count/2)'
                                      : 'Attendance Status ($count/2)'),
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: isCompleted
                                    ? const Color(0xFF15803D)
                                    : (isTimeInDone
                                        ? const Color(0xFF92400E)
                                        : (isDark ? gold : navy)),
                              ),
                            ),
                          ),
                        ],
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
                if (event.description.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    event.description,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: isDark
                          ? const Color(0xFFCBD5E1)
                          : const Color(0xFF334155),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Divider(
                  height: 1,
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0),
                ),
                const SizedBox(height: 14),
                _modalDetailRow(
                  Icons.person_outline_rounded,
                  'Student',
                  _fullName,
                  const Color(0xFF3B82F6),
                ),
                const SizedBox(height: 10),
                _modalDetailRow(
                  Icons.calendar_today_rounded,
                  'Date',
                  _formatDate(event),
                  navy,
                ),
                const SizedBox(height: 10),
                _modalDetailRow(
                  Icons.login_rounded,
                  'Time-In Window',
                  timeInWindow,
                  const Color(0xFF16A34A),
                ),
                const SizedBox(height: 10),
                _modalDetailRow(
                  Icons.logout_rounded,
                  'Time-Out Window',
                  timeOutWindow,
                  const Color(0xFFDC2626),
                ),
                const SizedBox(height: 10),
                _modalDetailRow(
                  Icons.place_outlined,
                  'Venue',
                  venueLocation,
                  const Color(0xFFD97706),
                ),
                const SizedBox(height: 22),
                if (isWindowActive && !isCompleted)
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _openAttendanceScannerForEvent(event);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? gold : navy,
                        foregroundColor: isDark ? navy : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      icon: const Icon(
                        Icons.face_retouching_natural_rounded,
                        size: 19,
                      ),
                      label: Text(
                        isTimeInDone
                            ? 'Verify Time-Out Now'
                            : 'Verify Time-In Now',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF0F172A)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isCompleted
                              ? Icons.check_circle_rounded
                              : Icons.lock_outline_rounded,
                          size: 16,
                          color: isCompleted ? const Color(0xFF16A34A) : muted,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isCompleted
                              ? 'Attendance completed for this event.'
                              : 'Attendance window is currently closed.',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: isCompleted
                                ? const Color(0xFF16A34A)
                                : (isDark
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF64748B)),
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

  Widget _modalDetailRow(
    IconData icon,
    String label,
    String value,
    Color iconColor,
  ) {
    final isDark = themeController.isDarkMode;
    final effectiveColor =
        (isDark && iconColor == navy) ? gold : iconColor;

    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: effectiveColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: effectiveColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: muted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
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

    final parsed = _parseTimeToDateTime(clean);
    if (parsed != null) {
      return DateFormat('h:mm a').format(parsed);
    }
    return clean;
  }

  DateTime? _parseTimeToDateTime(String timeStr) {
    final clean = timeStr.trim();
    if (clean.isEmpty || clean.toLowerCase() == 'tba') return null;
    final now = DateTime.now();

    final amPmMatch = RegExp(
      r'(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(AM|PM)',
      caseSensitive: false,
    ).firstMatch(clean);

    if (amPmMatch != null) {
      int hour = int.parse(amPmMatch.group(1)!);
      final minute = int.parse(amPmMatch.group(2)!);
      final second =
          amPmMatch.group(3) != null ? int.parse(amPmMatch.group(3)!) : 0;
      final period = amPmMatch.group(4)!.toUpperCase();

      if (period == 'PM' && hour < 12) hour += 12;
      if (period == 'AM' && hour == 12) hour = 0;

      return DateTime(now.year, now.month, now.day, hour, minute, second);
    }

    final h24Match = RegExp(
      r'\b([01]?\d|2[0-3]):([0-5]\d)(?::([0-5]\d))?\b',
    ).firstMatch(clean);

    if (h24Match != null) {
      final hour = int.parse(h24Match.group(1)!);
      final minute = int.parse(h24Match.group(2)!);
      final second =
          h24Match.group(3) != null ? int.parse(h24Match.group(3)!) : 0;

      return DateTime(now.year, now.month, now.day, hour, minute, second);
    }

    final iso = DateTime.tryParse(clean);
    if (iso != null) {
      final local = iso.toLocal();
      return DateTime(
        now.year,
        now.month,
        now.day,
        local.hour,
        local.minute,
        local.second,
      );
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
        ]) ??
        event.startTime;

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
        ]) ??
        event.endTime;

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
    final cleanTargets =
        targetKeys.map((k) => k.toLowerCase().replaceAll('_', '')).toList();

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

    final cleanTargets =
        keys.map((k) => k.toLowerCase().replaceAll('_', '')).toList();
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
      backgroundColor:
          isDark ? const Color(0xFF0F172A) : const Color(0xFFF4F6FA),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(68),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : navy,
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? const Color(0xFF334155)
                    : gold.withValues(alpha: 0.35),
                width: 1.5,
              ),
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _dashboardBusy ? null : _reloadPage,
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: gold.withValues(alpha: 0.8),
                              width: 1.5,
                            ),
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
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1,
                        ),
                      ),
                      if (_studentNumber.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _studentNumber,
                            style: const TextStyle(
                              color: gold,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(width: 10),
                  InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: _openProfile,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: gold, width: 1.8),
                      ),
                      child: _profileAvatar(radius: 17),
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
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 110),
                children: [
                  if (_pendingOfflineCount > 0 || _syncingOffline) ...[
                    _buildPendingOfflineCard(),
                    const SizedBox(height: 16),
                  ],
                  _buildHeaderSection(dateString),
                  const SizedBox(height: 14),
                  _buildOverviewSection(),
                  const SizedBox(height: 22),
                  _buildEventsSectionHeader(),
                  const SizedBox(height: 10),
                  if (_error != null)
                    _buildErrorWidget()
                  else if (_todayEvents.isEmpty)
                    _buildEmptyEventsWidget()
                  else
                    ..._todayEvents.map(
                      (evt) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _buildEventCard(evt, today: true),
                      ),
                    ),
                  if (_upcomingEvents.isNotEmpty) ...[
                    const SizedBox(height: 14),
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

  BoxDecoration _cardDecoration(bool isDark, {Color? borderColor}) {
    return BoxDecoration(
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: borderColor ??
            (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
      ),
      boxShadow: isDark
          ? null
          : [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
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
              'Dashboard',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: isDark ? Colors.white : navy,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Your schedule and check-in summary',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? const Color(0xFF94A3B8) : muted,
              ),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.calendar_today_rounded,
                size: 13,
                color: isDark ? gold : navy,
              ),
              const SizedBox(width: 6),
              Text(
                dateString,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: isDark ? gold : navy,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOverviewSection() {
    final isDark = themeController.isDarkMode;

    return Row(
      children: [
        Expanded(
          child: _statTile(
            value: '${_todayEvents.length}',
            label: 'Today',
            icon: Icons.today_rounded,
            accent: const Color(0xFF2563EB),
            isDark: isDark,
            onTap: () => _showSummaryDetails('Today'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statTile(
            value: '${_upcomingEvents.length}',
            label: 'Upcoming',
            icon: Icons.event_repeat_rounded,
            accent: const Color(0xFFD97706),
            isDark: isDark,
            onTap: () => _showSummaryDetails('Upcoming'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statTile(
            value: '$_attendanceCount',
            label: 'Records',
            icon: Icons.verified_outlined,
            accent: const Color(0xFF059669),
            isDark: isDark,
            onTap: _openHistory,
          ),
        ),
      ],
    );
  }

  Widget _statTile({
    required String value,
    required String label,
    required IconData icon,
    required Color accent,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: _cardDecoration(isDark),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, size: 16, color: accent),
                    ),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : navy,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFFCBD5E1)
                        : const Color(0xFF334155),
                  ),
                ),
              ],
            ),
          ),
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
            Container(
              width: 4,
              height: 16,
              decoration: BoxDecoration(
                color: gold,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              "Today's Events",
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : navy,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
        if (_todayEvents.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${_todayEvents.length} Scheduled',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF059669),
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
                Container(
                  width: 4,
                  height: 16,
                  decoration: BoxDecoration(
                    color: isDark ? gold : navy,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Upcoming Events',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : navy,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
            TextButton.icon(
              onPressed: _openCalendar,
              style: TextButton.styleFrom(
                foregroundColor: isDark ? gold : navy,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: const Size(50, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.calendar_month_rounded, size: 15),
              label: const Text(
                'Calendar',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
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
    final isLiveNow = today && !isCompleted && _isEventWindowActive(event);

    final String statusLabel = isCompleted
        ? 'Completed'
        : (isLiveNow
            ? 'Open Now'
            : (count == 1 ? '1/2 Recorded' : '0/2'));

    final Color statusBg = isCompleted
        ? (isDark ? const Color(0xFF064E3B) : const Color(0xFFDCFCE7))
        : (isLiveNow
            ? (isDark ? const Color(0xFF422006) : const Color(0xFFFEF3C7))
            : (count == 1
                ? (isDark ? const Color(0xFF451A03) : const Color(0xFFFEF3C7))
                : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9))));

    final Color statusFg = isCompleted
        ? (isDark ? const Color(0xFF6EE7B7) : const Color(0xFF15803D))
        : (isLiveNow
            ? (isDark ? gold : const Color(0xFFB45309))
            : (count == 1
                ? (isDark ? const Color(0xFFFCD34D) : const Color(0xFF92400E))
                : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569))));

    final Color cardBorder = isCompleted
        ? (isDark ? const Color(0xFF065F46) : const Color(0xFF86EFAC))
        : (isLiveNow
            ? gold
            : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)));

    final bool hasVenue =
        event.venue.isNotEmpty && event.venue != 'Unspecified Venue';

    return Container(
      decoration: _cardDecoration(isDark, borderColor: cardBorder),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showEventDetailModal(event),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!today && event.date != null) ...[
                  _dateBadge(event.date!, isDark),
                  const SizedBox(width: 12),
                ],
                Expanded(
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
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : navy,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: statusBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isLiveNow) ...[
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF16A34A),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                ],
                                Text(
                                  statusLabel,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: statusFg,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _scheduleIconLine(
                        icon: Icons.login_rounded,
                        iconColor: const Color(0xFF16A34A),
                        text: 'Time-In: $timeInWindow',
                        isDark: isDark,
                      ),
                      const SizedBox(height: 5),
                      _scheduleIconLine(
                        icon: Icons.logout_rounded,
                        iconColor: const Color(0xFFDC2626),
                        text: 'Time-Out: $timeOutWindow',
                        isDark: isDark,
                      ),
                      if (hasVenue) ...[
                        const SizedBox(height: 5),
                        _scheduleIconLine(
                          icon: Icons.place_outlined,
                          iconColor: const Color(0xFF2563EB),
                          text: event.venue,
                          isDark: isDark,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dateBadge(DateTime date, bool isDark) {
    final month = DateFormat('MMM').format(date).toUpperCase();
    final day = DateFormat('d').format(date);

    return Container(
      width: 46,
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFDBEAFE),
        ),
      ),
      child: Column(
        children: [
          Text(
            month,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: isDark ? gold : const Color(0xFF2563EB),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            day,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : navy,
            ),
          ),
        ],
      ),
    );
  }

  Widget _scheduleIconLine({
    required IconData icon,
    required Color iconColor,
    required String text,
    required bool isDark,
  }) {
    return Row(
      children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
            ),
          ),
        ),
      ],
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
        border: Border.all(color: gold.withValues(alpha: 0.65)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: gold.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(9),
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
                      ? 'Syncing offline attendance'
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
                      ? 'Uploading saved records to server...'
                      : '$_pendingOfflineCount record${_pendingOfflineCount == 1 ? '' : 's'} queued for upload.',
                  style: const TextStyle(
                    color: Color(0xFF786200),
                    fontSize: 11.5,
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
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: _cardDecoration(isDark),
      child: Column(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: (isDark ? gold : navy).withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.event_available_rounded,
              size: 24,
              color: isDark ? gold : navy,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'No events scheduled today',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Check upcoming dates in the Calendar tab.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: muted),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget() {
    final isDark = themeController.isDarkMode;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(isDark),
      child: Column(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Colors.redAccent,
            size: 30,
          ),
          const SizedBox(height: 8),
          Text(
            _error ?? 'Error loading events.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: muted),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => _loadDashboard(),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? gold : navy,
              foregroundColor: isDark ? navy : Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Retry',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
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
            ? const Color(0xFF2563EB)
            : const Color(0xFFD97706);

        return Dialog(
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(
                          label == 'Today'
                              ? Icons.today_rounded
                              : Icons.event_repeat_rounded,
                          color: accent,
                          size: 17,
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
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(
                          Icons.close_rounded,
                          color: isDark ? Colors.white70 : muted,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: events.isEmpty
                        ? const Center(
                            child: Text(
                              'No events scheduled.',
                              style: TextStyle(color: muted, fontSize: 12.5),
                            ),
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
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13.5,
                                        color: isDark ? Colors.white : navy,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${_formatDate(event)} • ${_getDisplayWindow(event)}',
                                      style: const TextStyle(
                                        fontSize: 11.5,
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
}