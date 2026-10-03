import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/attendance_history_item.dart';
import '../../models/event_item.dart';
import '../../services/attendance_history_service.dart';
import '../../services/event_service.dart';
import '../../widgets/main_bottom_navigation.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  static const Color navy = Color(0xFF1B1F5C);
  static const Color gold = Color(0xFFC9973E);
  static const Color background = Color(0xFFF9FAFB);
  static const Color muted = Color(0xFF777783);

  static const Color todayBorderColor = Color(0xFF1B1F5C);
  static const Color eventColor = Color(0xFFD97706);
  static const Color partialColor = Color(0xFFF59E0B);
  static const Color attendedColor = Color(0xFF10B981);
  static const Color missedColor = Color(0xFFEF4444);

  bool _loading = true;
  String? _error;

  List<EventItem> _events = const [];
  List<AttendanceHistoryItem> _attendanceRecords = const [];

  late DateTime _selectedDate;
  late DateTime _displayedMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _displayedMonth = DateTime(now.year, now.month);
    _loadCalendar();
  }

  Future<void> _loadCalendar() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final eventResult = await EventService.instance.getEvents();
      final historyResult = await AttendanceHistoryService.instance.getHistory();

      if (!mounted) return;

      if (!eventResult.success) {
        setState(() {
          _loading = false;
          _events = const [];
          _attendanceRecords = historyResult.success ? historyResult.records : const [];
          _error = eventResult.message;
        });
        return;
      }

      setState(() {
        _loading = false;
        _events = eventResult.events;
        _attendanceRecords = historyResult.success ? historyResult.records : const [];
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load Smart Attendance System calendar data.';
      });
    }
  }

  List<EventItem> get _selectedEvents {
    final events = _events.where((event) {
      final date = event.date;
      if (date == null) return false;
      return _sameDay(date, _selectedDate);
    }).toList();

    events.sort((a, b) => a.startTime.compareTo(b.startTime));
    return events;
  }

  List<EventItem> _eventsOn(DateTime date) {
    return _events.where((event) {
      final eventDate = event.date;
      if (eventDate == null) return false;
      return _sameDay(eventDate, date);
    }).toList();
  }

  bool _hasEvent(DateTime date) => _eventsOn(date).isNotEmpty;

  int _eventAttendanceCount(EventItem event) {
    final eventId = event.id;
    if (eventId != null) {
      return _attendanceRecords.where((record) => record.eventId == eventId).length;
    }
    final eventName = event.name.trim().toLowerCase();
    if (eventName.isEmpty) return 0;
    return _attendanceRecords.where(
      (record) => record.eventName.trim().toLowerCase() == eventName,
    ).length;
  }

  bool _isEventFullyAttended(EventItem event) {
    return _eventAttendanceCount(event) >= 2;
  }

  bool _isEventPartiallyAttended(EventItem event) {
    return _eventAttendanceCount(event) == 1;
  }

  bool _allEventsAttendedOn(DateTime date) {
    final events = _eventsOn(date);
    if (events.isEmpty) return false;
    return events.every(_isEventFullyAttended);
  }

  bool _hasPartiallyAttendedEventOn(DateTime date) {
    final events = _eventsOn(date);
    if (events.isEmpty) return false;

    bool hasPartial = events.any(_isEventPartiallyAttended);
    bool hasFullAndMissing = events.any(_isEventFullyAttended) && events.any((e) => _eventAttendanceCount(e) == 0);

    return hasPartial || hasFullAndMissing;
  }

  bool _hasMissedEventOn(DateTime date) {
    final events = _eventsOn(date);
    if (events.isEmpty) return false;
    final now = DateTime.now();

    return events.every((event) {
      if (_isEventFullyAttended(event)) return false;
      return _eventHasEnded(event, now);
    });
  }

  bool _eventHasEnded(EventItem event, DateTime now) {
    final eventDate = event.date;
    if (eventDate == null) return false;

    final day = DateTime(eventDate.year, eventDate.month, eventDate.day);
    if (day.isBefore(DateTime(now.year, now.month, now.day))) return true;
    if (!day.isAtSameMomentAs(DateTime(now.year, now.month, now.day))) return false;

    final end = _parseEventTime(event.endTime);
    if (end == null) return false;
    return !end.isAfter(now);
  }

  DateTime? _parseEventTime(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return null;

    const formats = ['HH:mm:ss', 'HH:mm', 'h:mm a', 'hh:mm a'];
    for (final format in formats) {
      try {
        final parsed = DateFormat(format, 'en_US').parseLoose(clean);
        final now = DateTime.now();
        return DateTime(now.year, now.month, now.day, parsed.hour, parsed.minute, parsed.second);
      } catch (_) {}
    }
    return null;
  }

  void _previousMonth() {
    setState(() {
      _displayedMonth = DateTime(_displayedMonth.year, _displayedMonth.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _displayedMonth = DateTime(_displayedMonth.year, _displayedMonth.month + 1);
    });
  }

  void _selectDate(DateTime date) {
    setState(() {
      _selectedDate = DateTime(date.year, date.month, date.day);
    });
  }

  void _goToToday() {
    final now = DateTime.now();
    setState(() {
      _selectedDate = DateTime(now.year, now.month, now.day);
      _displayedMonth = DateTime(now.year, now.month);
    });
  }

  void _showEventDetailsModal(EventItem event) {
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        final count = _eventAttendanceCount(event);
        final bool isFullyAttended = count >= 2;
        final bool isPartial = count == 1;
        final bool hasGeofence = event.geofenceEnabled;

        final Color statusColor = isFullyAttended
            ? attendedColor
            : (isPartial ? partialColor : missedColor);

        final String statusLabel = isFullyAttended
            ? 'Fully Attended (Time-In & Time-Out Complete)'
            : (isPartial ? 'In Progress (Time-In Recorded)' : 'Pending Attendance');

        return Dialog(
          elevation: 12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 6,
                width: double.infinity,
                color: statusColor,
              ),
              Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            event.name,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: navy,
                              height: 1.2,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => Navigator.of(ctx).pop(),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              color: Colors.grey,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: statusColor.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isFullyAttended
                                ? Icons.check_circle_rounded
                                : (isPartial ? Icons.timelapse_rounded : Icons.error_outline_rounded),
                            size: 14,
                            color: statusColor,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              statusLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    const SizedBox(height: 18),

                    _buildModalDetailRow(
                      icon: Icons.access_time_filled_rounded,
                      iconColor: gold,
                      title: 'Schedule Window',
                      subtitle: _formatTimeRange(event),
                    ),
                    const SizedBox(height: 14),

                    _buildModalDetailRow(
                      icon: Icons.location_on_rounded,
                      iconColor: navy,
                      title: 'Venue Location',
                      subtitle: event.venue.isEmpty ? 'Main Campus' : event.venue,
                    ),
                    const SizedBox(height: 14),

                    _buildModalDetailRow(
                      icon: Icons.radar_rounded,
                      iconColor: hasGeofence ? attendedColor : Colors.grey,
                      title: 'Geofence Requirement',
                      subtitle: hasGeofence
                          ? 'Active (${event.geofenceRadius.round()}m radius enforced)'
                          : 'Disabled (Any location allowed)',
                    ),

                    if (event.description.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Description',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              event.description,
                              style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: navy,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Close', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModalDetailRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: navy)),
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
      appBar: AppBar(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Calendar', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
        actions: [
          TextButton(
            onPressed: _goToToday,
            child: const Text('Today', style: TextStyle(color: gold, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 5),
        ],
      ),
      body: RefreshIndicator(
        color: navy,
        onRefresh: _loadCalendar,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 110),
          children: [
            _buildCalendar(),
            const SizedBox(height: 14),
            _buildCompactLegend(),
            const SizedBox(height: 22),
            Text(
              DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: navy),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 70),
                child: Center(child: CircularProgressIndicator(color: navy)),
              )
            else if (_error != null)
              _buildError()
            else if (_selectedEvents.isEmpty)
              _buildEmpty()
            else
              ..._selectedEvents.map(_buildEventCard),
          ],
        ),
      ),
      bottomNavigationBar: const MainBottomNavigation(currentIndex: 2),
      floatingActionButton: MainBottomNavigation.scannerButton(
        context,
        currentIndex: 2,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _buildCalendar() {
    final firstDay = DateTime(_displayedMonth.year, _displayedMonth.month, 1);
    final lastDay = DateTime(_displayedMonth.year, _displayedMonth.month + 1, 0);
    final leadingDays = firstDay.weekday % 7;
    final totalCells = leadingDays + lastDay.day;
    final rows = (totalCells / 7).ceil();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: _previousMonth,
                icon: const Icon(Icons.chevron_left_rounded, color: navy),
              ),
              Expanded(
                child: Text(
                  DateFormat('MMMM yyyy').format(_displayedMonth),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: navy, fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                onPressed: _nextMonth,
                icon: const Icon(Icons.chevron_right_rounded, color: navy),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              _DayLabel('S'),
              _DayLabel('M'),
              _DayLabel('T'),
              _DayLabel('W'),
              _DayLabel('T'),
              _DayLabel('F'),
              _DayLabel('S'),
            ],
          ),
          const SizedBox(height: 6),
          for (var row = 0; row < rows; row++)
            Row(
              children: List.generate(7, (column) {
                final cell = row * 7 + column;
                final day = cell - leadingDays + 1;

                if (day < 1 || day > lastDay.day) {
                  return const Expanded(child: SizedBox(height: 48));
                }

                final date = DateTime(_displayedMonth.year, _displayedMonth.month, day);
                return Expanded(child: _buildDay(date));
              }),
            ),
        ],
      ),
    );
  }

  Widget _buildDay(DateTime date) {
    final selected = _sameDay(date, _selectedDate);
    final today = _sameDay(date, DateTime.now());
    final hasEvent = _hasEvent(date);

    final allAttended = _allEventsAttendedOn(date);
    final partialAttendance = _hasPartiallyAttendedEventOn(date);
    final missed = _hasMissedEventOn(date);

    double progress = 0.0;
    Color ringColor = Colors.transparent;

    if (allAttended) {
      progress = 1.0;
      ringColor = attendedColor;
    } else if (partialAttendance) {
      progress = 0.55;
      ringColor = partialColor;
    } else if (missed) {
      progress = 1.0;
      ringColor = missedColor;
    } else if (hasEvent) {
      progress = 0.25;
      ringColor = eventColor;
    }

    return InkWell(
      onTap: () => _selectDate(date),
      borderRadius: BorderRadius.circular(28),
      child: SizedBox(
        height: 48,
        child: Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (hasEvent || allAttended || partialAttendance || missed)
                CustomPaint(
                  size: const Size(38, 38),
                  painter: _CircularProgressRingPainter(
                    progress: progress,
                    color: ringColor,
                    strokeWidth: 3.5,
                  ),
                ),

              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? navy
                      : (today ? navy.withValues(alpha: 0.1) : Colors.transparent),
                  border: Border.all(
                    color: selected
                        ? gold
                        : (today ? todayBorderColor : Colors.transparent),
                    width: selected ? 2 : (today ? 1.5 : 0),
                  ),
                ),
                child: Text(
                  '${date.day}',
                  style: TextStyle(
                    color: selected
                        ? Colors.white
                        : (today ? navy : Colors.black87),
                    fontSize: 12,
                    fontWeight: (selected || today) ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _RingLegendItem(
            color: attendedColor,
            label: 'Fully Attended',
            progress: 1.0,
          ),
          _RingLegendItem(
            color: partialColor,
            label: 'In Progress',
            progress: 0.55,
          ),
          _RingLegendItem(
            color: missedColor,
            label: 'Missed',
            progress: 1.0,
          ),
        ],
      ),
    );
  }

  Widget _buildEventCard(EventItem event) {
    final count = _eventAttendanceCount(event);
    final fullyAttended = count >= 2;
    final partiallyAttended = count == 1;
    final today = event.date != null && _sameDay(event.date!, DateTime.now());
    final ended = event.date != null && _eventHasEnded(event, DateTime.now());

    final statusColor = fullyAttended
        ? attendedColor
        : (partiallyAttended ? partialColor : (ended ? missedColor : eventColor));

    final statusText = fullyAttended
        ? 'Fully Attended'
        : (partiallyAttended ? 'Time-In Recorded' : (ended ? 'Not Attended' : (today ? 'Scheduled Today' : 'Upcoming Event')));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showEventDetailsModal(event),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: statusColor.withValues(alpha: 0.3),
            ),
            boxShadow: const [
              BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 72,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
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
                            style: const TextStyle(
                              color: navy,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: statusColor.withValues(alpha: 0.2)),
                          ),
                          child: Text(
                            statusText,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.access_time_rounded, color: navy, size: 15),
                        const SizedBox(width: 6),
                        Text(
                          _formatTimeRange(event),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    if (event.venue.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, color: navy, size: 15),
                          const SizedBox(width: 6),
                          Text(
                            event.venue,
                            style: const TextStyle(color: muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Column(
        children: [
          Icon(Icons.event_busy_outlined, color: navy, size: 40),
          SizedBox(height: 12),
          Text('No events', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          SizedBox(height: 6),
          Text(
            'There are no events scheduled for this date.',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 12),
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
          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 40),
          const SizedBox(height: 12),
          const Text('Unable to load events', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            _error ?? 'Please try again.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _loadCalendar,
            style: FilledButton.styleFrom(backgroundColor: navy, foregroundColor: Colors.white),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  bool _sameDay(DateTime first, DateTime second) {
    return first.year == second.year && first.month == second.month && first.day == second.day;
  }

  String _formatTimeRange(EventItem event) {
    final start = _formatTime(event.startTime);
    final end = _formatTime(event.endTime);

    if (start.isNotEmpty && end.isNotEmpty) {
      return '$start - $end';
    }
    if (start.isNotEmpty) return start;
    if (end.isNotEmpty) return end;
    return 'Time not specified';
  }

  String _formatTime(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return '';

    const formats = ['HH:mm:ss', 'HH:mm', 'h:mm a', 'hh:mm a'];
    for (final format in formats) {
      try {
        final parsed = DateFormat(format, 'en_US').parseLoose(clean);
        return DateFormat('h:mm a').format(parsed);
      } catch (_) {}
    }
    return clean;
  }
}

class _CircularProgressRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;

  _CircularProgressRingPainter({
    required this.progress,
    required this.color,
    this.strokeWidth = 3.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final trackPaint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, trackPaint);

    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final sweepAngle = 2 * math.pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CircularProgressRingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class _DayLabel extends StatelessWidget {
  final String text;

  const _DayLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            color: Color(0xFF777783),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _RingLegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final double progress;

  const _RingLegendItem({
    required this.color,
    required this.label,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: const Size(14, 14),
          painter: _CircularProgressRingPainter(
            progress: progress,
            color: color,
            strokeWidth: 2.5,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(color: Color(0xFF475569), fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}