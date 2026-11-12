import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/event_item.dart';
import '../models/notification_item.dart';
import 'api_service.dart';
import 'event_service.dart';
import 'secure_time_service.dart';

class NotificationResult {
  final bool success;
  final String message;
  final List<NotificationItem> notifications;
  final int unreadCount;

  const NotificationResult({
    required this.success,
    required this.message,
    required this.notifications,
    required this.unreadCount,
  });
}

class NotificationActionResult {
  final bool success;
  final String message;

  const NotificationActionResult({
    required this.success,
    required this.message,
  });
}

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final ApiService _api = ApiService.instance;

  Future<NotificationResult> getNotifications() async {
    final notifications = <NotificationItem>[];
    int serverUnreadCount = 0;

    try {
      final response = await _api.dio.get('/api/v1/notifications');
      final raw = response.data;

      if (raw is Map) {
        final body = Map<String, dynamic>.from(raw);
        if (body['success'] == true) {
          final rawData = body['data'];
          if (rawData is List) {
            for (final item in rawData) {
              if (item is Map) {
                notifications.add(
                  NotificationItem.fromJson(Map<String, dynamic>.from(item)),
                );
              }
            }
          }
          serverUnreadCount = _intValue(body['unread_count']);
        }
      }
    } on DioException catch (e) {
      debugPrint('NOTIFICATION API ERROR: ${_errorMessage(e)}');
    } catch (e) {
      debugPrint('NOTIFICATION ERROR: $e');
    }

    // --- CLIENT-SIDE SYNTHETIC ADMIN EVENT, UPDATE & MISSED ATTENDANCE NOTIFICATIONS ---
    try {
      final eventsResult = await EventService.instance.getEvents();
      if (eventsResult.success) {
        final now = await SecureTimeService.instance.getTrustedTime();
        int syntheticNotifId = 800000;

        for (final event in eventsResult.events) {
          final raw = event.raw;
          final eventNameLower = event.name.trim().toLowerCase();
          final baseDate = event.date ?? now;

          final DateTime? createdAt = _parseDateTime(
            raw['created_at'] ?? raw['createdAt'],
          );
          final DateTime? updatedAt = _parseDateTime(
            raw['updated_at'] ?? raw['updatedAt'],
          );

          final bool hasTimeIn = _readBool(
            raw['has_time_in'] ??
                raw['student_has_time_in'] ??
                raw['time_in_recorded'],
          );
          final bool hasTimeOut = _readBool(
            raw['has_time_out'] ??
                raw['student_has_time_out'] ??
                raw['time_out_recorded'],
          );

          // Extract the admin's exact Time-In and Time-Out windows
          final timeInWin = _extractWindow(
            event: event,
            isTimeOut: false,
            baseDate: baseDate,
          );
          final timeOutWin = _extractWindow(
            event: event,
            isTimeOut: true,
            baseDate: baseDate,
          );

          final String timeInText = _formatWindow(timeInWin);
          final String timeOutText = _formatWindow(timeOutWin);

          final String scheduleSummary = _buildWindowSummary(
            timeInText: timeInText,
            timeOutText: timeOutText,
          );

          final String venueStr = event.venue.trim().isNotEmpty
              ? ' at ${event.venue.trim()}'
              : '';

          // 1. Admin Created a New Event
          final bool newEventExists = notifications.any((n) {
            final t = n.title.toLowerCase();
            final type = n.type.toLowerCase();
            final isCreationNotif = type.contains('event_created') ||
                t.contains('new event') ||
                t.contains('event scheduled');
            return isCreationNotif && t.contains(eventNameLower);
          });

          if (!newEventExists) {
            notifications.add(
              NotificationItem(
                id: syntheticNotifId++,
                type: 'event_created',
                title: 'New Event Scheduled: ${event.name}',
                message:
                    'Admin created a new event on ${event.eventDate}$venueStr ($scheduleSummary).',
                isRead: false,
                readAt: null,
                createdAt: createdAt ?? event.date ?? now,
              ),
            );
          }

          // 2. Admin Updated an Existing Event
          if (createdAt != null &&
              updatedAt != null &&
              updatedAt.difference(createdAt).inSeconds > 60) {
            final bool updateNotifExists = notifications.any((n) {
              final t = n.title.toLowerCase();
              final type = n.type.toLowerCase();
              final isUpdateNotif = type.contains('event_updated') ||
                  t.contains('event updated') ||
                  t.contains('rescheduled');
              return isUpdateNotif && t.contains(eventNameLower);
            });

            if (!updateNotifExists) {
              notifications.add(
                NotificationItem(
                  id: syntheticNotifId++,
                  type: 'event_updated',
                  title: 'Event Updated: ${event.name}',
                  message:
                      'Admin updated ${event.name} (${event.eventDate}$venueStr • $scheduleSummary). Please review the updated details.',
                  isRead: false,
                  readAt: null,
                  createdAt: updatedAt,
                ),
              );
            }
          }

          // 3. Ended Event Missed Attendance Notification (Time-In, Time-Out, or Both)
          final eventDate = event.date;
          if (eventDate != null) {
            final DateTime eventConclusion = timeOutWin.end ??
                timeInWin.end ??
                DateTime(
                  eventDate.year,
                  eventDate.month,
                  eventDate.day,
                  23,
                  59,
                  59,
                );

            final bool hasEventEnded = now.isAfter(eventConclusion) ||
                (!event.isToday && !event.isUpcoming);

            if (hasEventEnded) {
              String? missedSessionType;
              String missedWindowDetail = scheduleSummary;

              if (!hasTimeIn && !hasTimeOut) {
                missedSessionType = 'both Time-In and Time-Out';
                missedWindowDetail = scheduleSummary;
              } else if (!hasTimeIn) {
                missedSessionType = 'Time-In';
                missedWindowDetail = timeInText.isNotEmpty
                    ? 'Time-In Window: $timeInText'
                    : scheduleSummary;
              } else if (!hasTimeOut) {
                missedSessionType = 'Time-Out';
                missedWindowDetail = timeOutText.isNotEmpty
                    ? 'Time-Out Window: $timeOutText'
                    : scheduleSummary;
              }

              if (missedSessionType != null) {
                final missedTitle = 'Missed Attendance: ${event.name}';
                final missedMessage =
                    'You did not attend $missedSessionType for ${event.name} scheduled on ${event.eventDate} ($missedWindowDetail).';

                final bool missedNotifExists = notifications.any(
                  (n) =>
                      n.title.toLowerCase().contains(eventNameLower) &&
                      n.message.contains(missedSessionType!),
                );

                if (!missedNotifExists) {
                  notifications.add(
                    NotificationItem(
                      id: syntheticNotifId++,
                      type: 'missed_attendance',
                      title: missedTitle,
                      message: missedMessage,
                      isRead: false,
                      readAt: null,
                      createdAt: eventConclusion,
                    ),
                  );
                }
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('EVENT NOTIFICATION GENERATION ERROR: $e');
    }

    final unreadCount = notifications.where((n) => !n.isRead).length;

    return NotificationResult(
      success: true,
      message: 'Notifications loaded.',
      notifications: notifications,
      unreadCount: unreadCount > 0 ? unreadCount : serverUnreadCount,
    );
  }

  // --------------------------------------------------------------------------
  // TIME-IN / TIME-OUT WINDOW EXTRACTION & 12-HOUR AM/PM FORMATTING
  // --------------------------------------------------------------------------

  _EventTimeWindow _extractWindow({
    required EventItem event,
    required bool isTimeOut,
    required DateTime baseDate,
  }) {
    final rawMap = event.raw;
    final foundTimes = <DateTime>[];

    final targetKeywords = isTimeOut
        ? ['timeout', 'time_out', 'out']
        : ['timein', 'time_in', 'in_start', 'in_end', 'time_in_window'];

    void collectFromValue(dynamic value) {
      if (value == null) return;
      final str = value.toString().trim();
      if (str.isEmpty ||
          str.toLowerCase() == 'null' ||
          str.toLowerCase() == 'tba') {
        return;
      }

      final amPmRegex = RegExp(
        r'(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(AM|PM)',
        caseSensitive: false,
      );
      final amPmMatches = amPmRegex.allMatches(str);

      if (amPmMatches.isNotEmpty) {
        for (final m in amPmMatches) {
          int hour = int.parse(m.group(1)!);
          final minute = int.parse(m.group(2)!);
          final second = m.group(3) != null ? int.parse(m.group(3)!) : 0;
          final period = m.group(4)!.toUpperCase();

          if (period == 'PM' && hour < 12) hour += 12;
          if (period == 'AM' && hour == 12) hour = 0;

          foundTimes.add(
            DateTime(
              baseDate.year,
              baseDate.month,
              baseDate.day,
              hour,
              minute,
              second,
            ),
          );
        }
        return;
      }

      final h24Regex = RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)(?::([0-5]\d))?\b');
      final h24Matches = h24Regex.allMatches(str);

      if (h24Matches.isNotEmpty) {
        for (final m in h24Matches) {
          final hour = int.parse(m.group(1)!);
          final minute = int.parse(m.group(2)!);
          final second = m.group(3) != null ? int.parse(m.group(3)!) : 0;

          foundTimes.add(
            DateTime(
              baseDate.year,
              baseDate.month,
              baseDate.day,
              hour,
              minute,
              second,
            ),
          );
        }
        return;
      }

      final iso = DateTime.tryParse(str);
      if (iso != null) {
        final local = iso.toLocal();
        foundTimes.add(
          DateTime(
            baseDate.year,
            baseDate.month,
            baseDate.day,
            local.hour,
            local.minute,
            local.second,
          ),
        );
      }
    }

    void scanMap(dynamic data) {
      if (data is Map) {
        for (final entry in data.entries) {
          final keyStr = entry.key
              .toString()
              .toLowerCase()
              .replaceAll('_', '')
              .replaceAll('-', '');

          bool matchesKey = false;
          for (final tk in targetKeywords) {
            final cleanTk = tk.replaceAll('_', '').replaceAll('-', '');
            if (keyStr.contains(cleanTk)) {
              if (!isTimeOut && keyStr.contains('out')) continue;
              matchesKey = true;
              break;
            }
          }

          if (matchesKey && entry.value != null) {
            collectFromValue(entry.value);
          }
          scanMap(entry.value);
        }
      } else if (data is List) {
        for (final item in data) {
          scanMap(item);
        }
      }
    }

    scanMap(rawMap);

    foundTimes.sort();

    final start = foundTimes.isNotEmpty ? foundTimes.first : null;
    final end = foundTimes.length > 1 ? foundTimes.last : null;

    return _EventTimeWindow(start, end);
  }

  String _formatSingleTime(DateTime dt) {
    if (dt.second > 0) {
      return DateFormat('h:mm:ss a').format(dt);
    }
    return DateFormat('h:mm a').format(dt);
  }

  String _formatWindow(_EventTimeWindow win) {
    if (win.start == null) return '';
    final startStr = _formatSingleTime(win.start!);
    if (win.end == null || win.end!.isAtSameMomentAs(win.start!)) {
      return startStr;
    }
    final endStr = _formatSingleTime(win.end!);
    return '$startStr - $endStr';
  }

  String _buildWindowSummary({
    required String timeInText,
    required String timeOutText,
  }) {
    if (timeInText.isNotEmpty && timeOutText.isNotEmpty) {
      return 'Time-In: $timeInText • Time-Out: $timeOutText';
    }
    if (timeInText.isNotEmpty) {
      return 'Time-In: $timeInText';
    }
    if (timeOutText.isNotEmpty) {
      return 'Time-Out: $timeOutText';
    }
    return 'Scheduled Time';
  }

  Future<NotificationActionResult> markAsRead(int notificationId) async {
    if (notificationId >= 800000) {
      return const NotificationActionResult(
        success: true,
        message: 'Notification marked as read.',
      );
    }

    try {
      final response = await _api.dio.patch(
        '/api/v1/notifications/$notificationId/read',
      );

      final raw = response.data;
      if (raw is Map) {
        final body = Map<String, dynamic>.from(raw);
        return NotificationActionResult(
          success: body['success'] == true,
          message: body['message']?.toString() ?? 'Notification updated.',
        );
      }

      return const NotificationActionResult(
        success: true,
        message: 'Notification marked as read.',
      );
    } on DioException catch (e) {
      return NotificationActionResult(
        success: false,
        message: _errorMessage(e),
      );
    } catch (e) {
      debugPrint('MARK NOTIFICATION READ ERROR: $e');
      return const NotificationActionResult(
        success: false,
        message: 'Unable to update notification.',
      );
    }
  }

  Future<NotificationActionResult> markAllAsRead() async {
    try {
      final response = await _api.dio.patch('/api/v1/notifications/read-all');

      final raw = response.data;
      if (raw is Map) {
        final body = Map<String, dynamic>.from(raw);
        return NotificationActionResult(
          success: body['success'] == true,
          message: body['message']?.toString() ?? 'Notifications updated.',
        );
      }

      return const NotificationActionResult(
        success: true,
        message: 'All notifications marked as read.',
      );
    } on DioException catch (e) {
      return NotificationActionResult(
        success: false,
        message: _errorMessage(e),
      );
    } catch (e) {
      debugPrint('MARK ALL NOTIFICATIONS ERROR: $e');
      return const NotificationActionResult(
        success: false,
        message: 'Unable to update notifications.',
      );
    }
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    final str = value.toString().trim();
    if (str.isEmpty || str.toLowerCase() == 'null') return null;
    return DateTime.tryParse(str);
  }

  int _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
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

  String _errorMessage(DioException exception) {
    final response = exception.response;
    if (response == null) {
      return 'Unable to connect to Laravel.';
    }

    final raw = response.data;
    if (raw is Map) {
      final body = Map<String, dynamic>.from(raw);
      final message = body['message']?.toString();
      if (message != null && message.trim().isNotEmpty) {
        return message;
      }
    }

    if (response.statusCode == 401) {
      return 'Your session has expired. Please log in again.';
    }

    return 'Unable to process the notification request.';
  }
}

class _EventTimeWindow {
  final DateTime? start;
  final DateTime? end;
  const _EventTimeWindow(this.start, this.end);
}