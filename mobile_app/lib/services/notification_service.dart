import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/notification_item.dart';
import 'api_service.dart';
import 'event_service.dart';

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

      if (raw is! Map) {
        return const NotificationResult(
          success: false,
          message: 'Invalid response from the server.',
          notifications: [],
          unreadCount: 0,
        );
      }

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
    } on DioException catch (e) {
      debugPrint('NOTIFICATION API ERROR: ${_errorMessage(e)}');
    } catch (e) {
      debugPrint('NOTIFICATION ERROR: $e');
    }

    // --- CLIENT-SIDE SYNTHETIC EVENT NOTIFICATIONS ---
    try {
      final eventsResult = await EventService.instance.getEvents();
      if (eventsResult.success) {
        int syntheticNotifId = 800000;
        for (final event in eventsResult.events) {
          final exists = notifications.any((n) =>
              n.title.toLowerCase().contains(event.name.toLowerCase()) ||
              n.message.toLowerCase().contains(event.name.toLowerCase()));

          if (!exists && event.date != null) {
            notifications.add(
              NotificationItem(
                id: syntheticNotifId++,
                type: 'event',
                title: 'New Event Scheduled',
                message: 'Admin created a new event: ${event.name} on ${event.eventDate}.',
                isRead: false,
                readAt: null,
                createdAt: event.date,
              ),
            );
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
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
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