import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/notification_item.dart';
import '../../services/notification_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const Color navy = Color(0xFF080878);

  static const Color gold = Color(0xFFFFC800);

  static const Color background = Color(0xFFF6F6F6);

  static const Color muted = Color(0xFF777783);

  bool _loading = true;
  bool _markingAll = false;

  String? _error;

  List<NotificationItem> _notifications = const [];

  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();

    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    final result = await NotificationService.instance.getNotifications();

    if (!mounted) {
      return;
    }

    setState(() {
      _loading = false;

      if (result.success) {
        _notifications = result.notifications;
        _unreadCount = result.unreadCount;
        _error = null;
      } else {
        _notifications = const [];
        _unreadCount = 0;
        _error = result.message;
      }
    });
  }

  Future<void> _markRead(NotificationItem notification) async {
    if (notification.isRead) {
      return;
    }

    final result = await NotificationService.instance.markAsRead(
      notification.id,
    );

    if (!mounted) {
      return;
    }

    if (!result.success) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.message)));

      return;
    }

    setState(() {
      _notifications = _notifications.map((item) {
        if (item.id == notification.id) {
          return item.copyWith(isRead: true, readAt: DateTime.now());
        }

        return item;
      }).toList();

      if (_unreadCount > 0) {
        _unreadCount--;
      }
    });
  }

  Future<void> _markAllRead() async {
    if (_markingAll || _unreadCount == 0) {
      return;
    }

    setState(() {
      _markingAll = true;
    });

    final result = await NotificationService.instance.markAllAsRead();

    if (!mounted) {
      return;
    }

    setState(() {
      _markingAll = false;
    });

    if (!result.success) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.message)));

      return;
    }

    final now = DateTime.now();

    setState(() {
      _notifications = _notifications.map((item) {
        if (item.isRead) {
          return item;
        }

        return item.copyWith(isRead: true, readAt: now);
      }).toList();

      _unreadCount = 0;
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
          'Notifications',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markingAll ? null : _markAllRead,
              child: _markingAll
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: gold,
                      ),
                    )
                  : const Text(
                      'Read All',
                      style: TextStyle(
                        color: gold,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          const SizedBox(width: 5),
        ],
      ),
      body: RefreshIndicator(
        color: navy,
        onRefresh: _loadNotifications,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 190),
          Center(child: CircularProgressIndicator(color: navy)),
        ],
      );
    }

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [const SizedBox(height: 100), _buildError()],
      );
    }

    if (_notifications.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [const SizedBox(height: 100), _buildEmpty()],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),
      itemCount: _notifications.length,
      separatorBuilder: (BuildContext context, int index) =>
          const SizedBox(height: 10),
      itemBuilder: (BuildContext context, int index) {
        return _buildCard(_notifications[index]);
      },
    );
  }

  Widget _buildCard(NotificationItem notification) {
    final icon = _notificationIcon(notification.type);

    return Material(
      color: notification.isRead ? Colors.white : const Color(0xFFFFFBEB),
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: () {
          _markRead(notification);
        },
        borderRadius: BorderRadius.circular(17),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: notification.isRead
                  ? const Color(0xFFE2E2E8)
                  : const Color(0xFFFFD866),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 45,
                height: 45,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F0FA),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: navy, size: 24),
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
                            notification.title,
                            style: TextStyle(
                              color: navy,
                              fontSize: 15,
                              fontWeight: notification.isRead
                                  ? FontWeight.w600
                                  : FontWeight.w800,
                            ),
                          ),
                        ),

                        if (!notification.isRead)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(top: 5, left: 8),
                            decoration: const BoxDecoration(
                              color: gold,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 6),

                    Text(
                      notification.message,
                      style: const TextStyle(
                        color: Color(0xFF4F4F59),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),

                    if (notification.createdAt != null) ...[
                      const SizedBox(height: 9),
                      Text(
                        _formatDateTime(notification.createdAt!),
                        style: const TextStyle(color: muted, fontSize: 11),
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
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E2E8)),
      ),
      child: const Column(
        children: [
          Icon(Icons.notifications_none_rounded, color: navy, size: 51),

          SizedBox(height: 15),

          Text(
            'No notifications',
            style: TextStyle(
              color: Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),

          SizedBox(height: 7),

          Text(
            'New updates will appear here.',
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
          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 46),

          const SizedBox(height: 13),

          const Text(
            'Unable to load notifications',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            _error ?? 'Please try again.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted, fontSize: 13),
          ),

          const SizedBox(height: 18),

          FilledButton(
            onPressed: _loadNotifications,
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

  IconData _notificationIcon(String type) {
    switch (type.trim().toLowerCase()) {
      case 'event':
      case 'event_approved':
      case 'upcoming_event':
        return Icons.calendar_month_rounded;

      case 'attendance':
      case 'attendance_recorded':
        return Icons.how_to_reg_rounded;

      case 'sanction':
        return Icons.warning_amber_rounded;

      default:
        return Icons.notifications_rounded;
    }
  }

  String _formatDateTime(DateTime value) {
    return DateFormat('MMM d, yyyy • h:mm a').format(value.toLocal());
  }
}
