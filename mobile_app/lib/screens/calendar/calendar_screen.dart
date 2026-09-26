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
  static const Color navy = Color(0xFF080878);
  static const Color gold = Color(0xFFFFB000);
  static const Color background = Color(0xFFF6F6F6);
  static const Color muted = Color(0xFF777783);

  static const Color todayColor = Color(0xFF667085);
  static const Color eventColor = Color(0xFFD39B2A);
  static const Color partialColor = Color(0xFF6D8B7A);
  static const Color attendedColor = Color(0xFF2F8F63);
  static const Color missedColor = Color(0xFFC45B5B);

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

      final historyResult = await AttendanceHistoryService.instance
          .getHistory();

      if (!mounted) {
        return;
      }

      if (!eventResult.success) {
        setState(() {
          _loading = false;
          _events = const [];
          _attendanceRecords = historyResult.success
              ? historyResult.records
              : const [];
          _error = eventResult.message;
        });

        return;
      }

      setState(() {
        _loading = false;
        _events = eventResult.events;
        _attendanceRecords = historyResult.success
            ? historyResult.records
            : const [];
        _error = null;
      });
    } catch (e) {
      debugPrint('CALENDAR ERROR: $e');

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error = 'Unable to load calendar data.';
      });
    }
  }

  List<EventItem> get _selectedEvents {
    final events = _events.where((event) {
      final date = event.date;

      if (date == null) {
        return false;
      }

      return _sameDay(date, _selectedDate);
    }).toList();

    events.sort((a, b) => a.startTime.compareTo(b.startTime));

    return events;
  }

  List<EventItem> _eventsOn(DateTime date) {
    return _events.where((event) {
      final eventDate = event.date;

      if (eventDate == null) {
        return false;
      }

      return _sameDay(eventDate, date);
    }).toList();
  }

  bool _hasEvent(DateTime date) {
    return _eventsOn(date).isNotEmpty;
  }

  bool _isEventAttended(EventItem event) {
    final eventId = event.id;

    if (eventId != null) {
      return _attendanceRecords.any((record) => record.eventId == eventId);
    }

    final eventName = event.name.trim().toLowerCase();

    if (eventName.isEmpty) {
      return false;
    }

    return _attendanceRecords.any(
      (record) => record.eventName.trim().toLowerCase() == eventName,
    );
  }

  bool _allEventsAttendedOn(DateTime date) {
    final events = _eventsOn(date);

    if (events.isEmpty) {
      return false;
    }

    return events.every(_isEventAttended);
  }

  bool _hasPartiallyAttendedEventOn(DateTime date) {
    final events = _eventsOn(date);

    if (events.isEmpty) {
      return false;
    }

    final attendedCount = events.where(_isEventAttended).length;

    return attendedCount > 0 && attendedCount < events.length;
  }

  bool _hasMissedEventOn(DateTime date) {
    final events = _eventsOn(date);

    if (events.isEmpty) {
      return false;
    }

    final now = DateTime.now();

    return events.every((event) {
      if (_isEventAttended(event)) {
        return false;
      }

      return _eventHasEnded(event, now);
    });
  }

  bool _eventHasEnded(EventItem event, DateTime now) {
    final eventDate = event.date;

    if (eventDate == null) {
      return false;
    }

    final day = DateTime(eventDate.year, eventDate.month, eventDate.day);

    if (day.isBefore(DateTime(now.year, now.month, now.day))) {
      return true;
    }

    if (!day.isAtSameMomentAs(DateTime(now.year, now.month, now.day))) {
      return false;
    }

    final end = _parseEventTime(event.endTime);

    if (end == null) {
      return false;
    }

    return !end.isAfter(now);
  }

  DateTime? _parseEventTime(String value) {
    final clean = value.trim();

    if (clean.isEmpty) {
      return null;
    }

    const formats = ['HH:mm:ss', 'HH:mm', 'h:mm a'];

    for (final format in formats) {
      try {
        final parsed = DateFormat(format).parseStrict(clean);
        final now = DateTime.now();

        return DateTime(
          now.year,
          now.month,
          now.day,
          parsed.hour,
          parsed.minute,
          parsed.second,
        );
      } catch (_) {}
    }

    return null;
  }

  void _previousMonth() {
    setState(() {
      _displayedMonth = DateTime(
        _displayedMonth.year,
        _displayedMonth.month - 1,
      );
    });
  }

  void _nextMonth() {
    setState(() {
      _displayedMonth = DateTime(
        _displayedMonth.year,
        _displayedMonth.month + 1,
      );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Calendar',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: _goToToday,
            child: const Text(
              'Today',
              style: TextStyle(color: gold, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 5),
        ],
      ),
      body: RefreshIndicator(
        color: navy,
        onRefresh: _loadCalendar,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 110),
          children: [
            _buildCalendar(),
            const SizedBox(height: 12),
            _buildLegend(),
            const SizedBox(height: 24),
            Text(
              DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
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
      floatingActionButton: MainBottomNavigation.scannerButton(context),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _buildCalendar() {
    final firstDay = DateTime(_displayedMonth.year, _displayedMonth.month, 1);

    final lastDay = DateTime(
      _displayedMonth.year,
      _displayedMonth.month + 1,
      0,
    );

    final leadingDays = firstDay.weekday % 7;

    final totalCells = leadingDays + lastDay.day;

    final rows = (totalCells / 7).ceil();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE0E1E8)),
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
                  style: const TextStyle(
                    color: navy,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
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
                  return const Expanded(child: SizedBox(height: 54));
                }

                final date = DateTime(
                  _displayedMonth.year,
                  _displayedMonth.month,
                  day,
                );

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

    Color fill = Colors.transparent;
    Color textColor = Colors.black;

    if (allAttended) {
      fill = attendedColor;
      textColor = Colors.white;
    } else if (missed) {
      fill = missedColor;
      textColor = Colors.white;
    } else if (partialAttendance) {
      fill = partialColor;
      textColor = Colors.white;
    } else if (hasEvent) {
      fill = eventColor;
      textColor = Colors.white;
    } else if (today) {
      fill = todayColor;
      textColor = Colors.white;
    }

    return InkWell(
      onTap: () => _selectDate(date),
      borderRadius: BorderRadius.circular(28),
      child: SizedBox(
        height: 54,
        child: Center(
          child: Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fill,
              border: Border.all(
                color: selected
                    ? navy
                    : today
                    ? todayColor
                    : Colors.transparent,
                width: selected
                    ? 3
                    : today
                    ? 2
                    : 0,
              ),
            ),
            child: Text(
              '${date.day}',
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontWeight:
                    selected ||
                        today ||
                        allAttended ||
                        partialAttendance ||
                        missed ||
                        hasEvent
                    ? FontWeight.w800
                    : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0E1E8)),
      ),
      child: const Wrap(
        spacing: 14,
        runSpacing: 10,
        children: [
          _LegendItem('Selected', navy, outlined: true),
          _LegendItem('Today', todayColor),
          _LegendItem('Event', eventColor),
          _LegendItem('Partial attendance', partialColor),
          _LegendItem('All attended', attendedColor),
          _LegendItem('Not attended', missedColor),
        ],
      ),
    );
  }

  Widget _buildEventCard(EventItem event) {
    final attended = _isEventAttended(event);

    final today = event.date != null && _sameDay(event.date!, DateTime.now());

    final ended = event.date != null && _eventHasEnded(event, DateTime.now());

    final statusColor = attended
        ? attendedColor
        : ended
        ? missedColor
        : eventColor;

    final statusText = attended
        ? 'Attendance recorded'
        : ended
        ? 'Not attended'
        : today
        ? 'Scheduled today'
        : 'Event';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: attended
              ? attendedColor.withValues(alpha: 0.35)
              : const Color(0xFFE1E1E8),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 5,
            height: 88,
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(width: 13),
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
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          statusText,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(
                      Icons.access_time_rounded,
                      color: navy,
                      size: 17,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        _formatTimeRange(event),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (event.venue.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        color: navy,
                        size: 17,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          event.venue,
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
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
        border: Border.all(color: const Color(0xFFE0E1E8)),
      ),
      child: const Column(
        children: [
          Icon(Icons.event_busy_outlined, color: navy, size: 43),
          SizedBox(height: 12),
          Text(
            'No events',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 6),
          Text(
            'There are no events scheduled for this date.',
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
            'Unable to load events',
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
            onPressed: _loadCalendar,
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

  bool _sameDay(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
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
      } catch (_) {}
    }

    return clean;
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

class _LegendItem extends StatelessWidget {
  final String label;
  final Color color;
  final bool outlined;

  const _LegendItem(this.label, this.color, {this.outlined = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            color: outlined ? Colors.white : color,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: outlined ? 3 : 1),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF666673),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
