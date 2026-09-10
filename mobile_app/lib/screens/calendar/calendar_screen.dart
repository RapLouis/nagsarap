import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/event_item.dart';
import '../../services/event_service.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  static const Color navy = Color(0xFF080878);
  static const Color gold = Color(0xFFFFC800);
  static const Color background = Color(0xFFF6F6F6);
  static const Color muted = Color(0xFF777783);

  bool _loading = true;
  String? _error;

  List<EventItem> _events = const [];

  late DateTime _selectedDate;
  late DateTime _displayedMonth;

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();

    _selectedDate = DateTime(now.year, now.month, now.day);

    _displayedMonth = DateTime(now.year, now.month);

    _loadEvents();
  }

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

  bool _hasEvent(DateTime date) {
    return _events.any((event) {
      final eventDate = event.date;

      if (eventDate == null) {
        return false;
      }

      return _sameDay(eventDate, date);
    });
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
        onRefresh: _loadEvents,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 30),
          children: [
            _buildCalendar(),

            const SizedBox(height: 24),

            Text(
              DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate),
              style: const TextStyle(
                color: Colors.black,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),

            const SizedBox(height: 14),

            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
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
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E2E8)),
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

          const SizedBox(height: 12),

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

          const SizedBox(height: 8),

          for (var row = 0; row < rows; row++)
            Row(
              children: List.generate(7, (column) {
                final cell = (row * 7) + column;

                final day = cell - leadingDays + 1;

                if (day < 1 || day > lastDay.day) {
                  return const Expanded(child: SizedBox(height: 52));
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

    return InkWell(
      onTap: () {
        _selectDate(date);
      },
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 52,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? navy
                    : today
                    ? const Color(0xFFFFF1B8)
                    : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${date.day}',
                style: TextStyle(
                  color: selected ? Colors.white : Colors.black,
                  fontSize: 13,
                  fontWeight: selected || today
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: hasEvent ? gold : Colors.transparent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventCard(EventItem event) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFE2E2E8)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 5, height: 122, color: gold),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (event.isToday) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF1B8),
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
                    ],
                  ),

                  const SizedBox(height: 11),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                            color: Colors.black,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),

                  if (event.venue.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E2E8)),
      ),
      child: const Column(
        children: [
          Icon(Icons.event_busy_outlined, color: navy, size: 43),
          SizedBox(height: 12),
          Text(
            'No events',
            style: TextStyle(
              color: Colors.black,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
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
      width: double.infinity,
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
            style: TextStyle(
              color: Colors.black,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            _error ?? 'Please try again.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted, fontSize: 13),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _loadEvents,
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
      } catch (_) {
        // Try next format.
      }
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
