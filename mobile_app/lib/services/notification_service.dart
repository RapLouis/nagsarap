import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

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
                final notif = NotificationItem.fromJson(
                  Map<String, dynamic>.from(item),
                );
                notifications.add(notif);
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

    // --- CLIENT-SIDE SYNTHETIC EVENT & MISSED ATTENDANCE NOTIFICATIONS ---
    try {
      final eventsResult = await EventService.instance.getEvents();
      if (eventsResult.success) {
        final now = await SecureTimeService.instance.getTrustedTime();
        int syntheticNotifId = 800000;

        for (final event in eventsResult.events) {
          final raw = event.raw;

          // Read attendance state flags from event payload
          final bool hasTimeIn = _readBool(
            raw['has_time_in'] ?? raw['student_has_time_in'] ?? raw['time_in_recorded'],
          );
          final bool hasTimeOut = _readBool(
            raw['has_time_out'] ?? raw['student_has_time_out'] ?? raw['time_out_recorded'],
          );

          // 1. New Event Creation Notification
          final bool newEventExists = notifications.any((n) =>
              n.title.toLowerCase().contains(event.name.toLowerCase()) ||
              n.message.toLowerCase().contains(event.name.toLowerCase()));

          if (!newEventExists && event.date != null) {
            final title = 'New Event Scheduled: ${event.name}';
            final bodyText = 'Admin created a new event on ${event.eventDate}.';

            notifications.add(
              NotificationItem(
                id: syntheticNotifId,
                type: 'event',
                title: title,
                message: bodyText,
                isRead: false,
                readAt: null,
                createdAt: event.date,
              ),
            );

            syntheticNotifId++;
          }

          // 2. Ended Event Missed Attendance Notification (Time-In, Time-Out, or Both)
          final eventDate = event.date;
          if (eventDate != null) {
            final DateTime endDateTime = DateTime(
              eventDate.year,
              eventDate.month,
              eventDate.day,
              23,
              59,
              59,
            );

            // Check if the event day/window has elapsed
            final bool hasEventEnded = now.isAfter(endDateTime) ||
                (!event.isToday && !event.isUpcoming);

            if (hasEventEnded) {
              String? missedSessionType;

              if (!hasTimeIn && !hasTimeOut) {
                missedSessionType = 'both Time-In and Time-Out';
              } else if (!hasTimeIn) {
                missedSessionType = 'Time-In';
              } else if (!hasTimeOut) {
                missedSessionType = 'Time-Out';
              }

              if (missedSessionType != null) {
                final missedTitle = 'Missed Attendance: ${event.name}';
                final timeWindowStr = event.formattedTimeRange ?? 'Scheduled Time';
                final missedMessage =
                    'You did not attend $missedSessionType for ${event.name} scheduled on ${event.eventDate} ($timeWindowStr).';

                final bool missedNotifExists = notifications.any(
                  (n) => n.title.contains(event.name) && n.message.contains(missedSessionType!),
                );

                if (!missedNotifExists) {
                  notifications.add(
                    NotificationItem(
                      id: syntheticNotifId,
                      type: 'missed_attendance',
                      title: missedTitle,
                      message: missedMessage,
                      isRead: false,
                      readAt: null,
                      createdAt: endDateTime,
                    ),
                  );

                  syntheticNotifId++;
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

  Future<NotificationActionResult> markAsRead(int notificationId) async {
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