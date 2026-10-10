import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../main.dart';
import '../../models/notification_item.dart';
import '../../services/notification_service.dart';
import '../../widgets/main_bottom_navigation.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const Color navy = Color(0xFF080878);
  static const Color gold = Color(0xFFFFC800);
  static const Color muted = Color(0xFF94A3B8);

  bool _loading = true;
  bool _markingAll = false;
  String? _error;

  List<NotificationItem> _notifications = const [];
  int _unreadCount = 0;
  bool _showUnreadOnly = false;
  int _visibleLimit = 15;

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
        _visibleLimit = 15;
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
    final isDark = themeController.isDarkMode;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E293B) : navy,
        foregroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: 86,
        title: const Text(
          'Notifications',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 22,
          ),
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
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          const SizedBox(width: 5),
        ],
      ),
      body: RefreshIndicator(
        color: gold,
        onRefresh: _loadNotifications,
        child: _buildBody(),
      ),
      bottomNavigationBar: MainBottomNavigation(
        currentIndex: 1,
        notificationBadge: _unreadCount,
      ),
      floatingActionButton: MainBottomNavigation.scannerButton(
        context,
        currentIndex: 1,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _buildBody() {
    final isDark = themeController.isDarkMode;

    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 190),
          Center(child: CircularProgressIndicator(color: gold)),
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

    final filtered = _showUnreadOnly
        ? _notifications.where((item) => !item.isRead).toList()
        : _notifications;

    final visible = filtered.take(_visibleLimit).toList();
    final hasMore = visible.length < filtered.length;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 112),
      children: [
        _buildFilterBar(),
        const SizedBox(height: 14),
        if (visible.isEmpty)
          _buildFilteredEmpty()
        else
          ..._buildNotificationList(visible),
        if (hasMore) ...[
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _visibleLimit += 15;
              });
            },
            icon: const Icon(Icons.expand_more_rounded),
            label: Text(
              'Show 15 more • ${filtered.length - visible.length} remaining',
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: isDark ? gold : navy,
              side: BorderSide(
                color:
                    isDark ? const Color(0xFF334155) : const Color(0xFFD7D7E2),
              ),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ] else if (filtered.length > 15) ...[
          const SizedBox(height: 5),
          TextButton(
            onPressed: () {
              setState(() {
                _visibleLimit = 15;
              });
            },
            child: Text(
              'Show latest 15',
              style: TextStyle(
                color: isDark ? gold : navy,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _buildNotificationList(List<NotificationItem> notifications) {
    final widgets = <Widget>[];
    String? currentDay;

    for (final notification in notifications) {
      final day = notification.createdAt == null
          ? 'Earlier'
          : DateFormat('EEEE, MMMM d')
                .format(notification.createdAt!.toLocal());

      if (day != currentDay) {
        if (widgets.isNotEmpty) {
          widgets.add(const SizedBox(height: 12));
        }

        widgets.add(
          Text(
            day,
            style: const TextStyle(
              color: muted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        );
        widgets.add(const SizedBox(height: 7));
        currentDay = day;
      }

      widgets.add(_buildCard(notification));
      widgets.add(const SizedBox(height: 8));
    }

    if (widgets.isNotEmpty) {
      widgets.removeLast();
    }

    return widgets;
  }

  Widget _buildFilterBar() {
    final isDark = themeController.isDarkMode;

    return Row(
      children: [
        ChoiceChip(
          label: const Text('All'),
          selected: !_showUnreadOnly,
          selectedColor: isDark ? gold : navy,
          backgroundColor:
              isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
          labelStyle: TextStyle(
            color: !_showUnreadOnly
                ? (isDark ? navy : Colors.white)
                : (isDark ? Colors.white70 : navy),
            fontWeight: FontWeight.w700,
          ),
          onSelected: (_) {
            setState(() {
              _showUnreadOnly = false;
              _visibleLimit = 15;
            });
          },
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: Text('Unread ($_unreadCount)'),
          selected: _showUnreadOnly,
          selectedColor: isDark ? gold : navy,
          backgroundColor:
              isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
          labelStyle: TextStyle(
            color: _showUnreadOnly
                ? (isDark ? navy : Colors.white)
                : (isDark ? Colors.white70 : navy),
            fontWeight: FontWeight.w700,
          ),
          onSelected: (_) {
            setState(() {
              _showUnreadOnly = true;
              _visibleLimit = 15;
            });
          },
        ),
      ],
    );
  }

  Widget _buildFilteredEmpty() {
    final isDark = themeController.isDarkMode;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E2E8),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.mark_email_read_outlined,
            color: isDark ? gold : navy,
            size: 40,
          ),
          const SizedBox(height: 10),
          Text(
            'No unread notifications',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'You are all caught up.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(NotificationItem notification) {
    final isDark = themeController.isDarkMode;
    final icon = _notificationIcon(notification.type);

    final cardBg = notification.isRead
        ? (isDark ? const Color(0xFF1E293B) : Colors.white)
        : (isDark ? const Color(0xFF332A00) : const Color(0xFFFFFBEB));

    final borderColor = notification.isRead
        ? (isDark ? const Color(0xFF334155) : const Color(0xFFE2E2E8))
        : (isDark ? const Color(0xFF786200) : const Color(0xFFFFD866));

    final titleColor = isDark ? Colors.white : navy;
    final iconColor = notification.isRead ? muted : gold;

    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: () => _markRead(notification),
        borderRadius: BorderRadius.circular(15),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: notification.isRead
                      ? (isDark ? const Color(0xFF0F172A) : const Color(0xFFF0F0F7))
                      : (isDark ? const Color(0xFF423700) : const Color(0xFFFFF0B8)),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: iconColor, size: 21),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: titleColor,
                              fontSize: 13.5,
                              fontWeight: notification.isRead
                                  ? FontWeight.w600
                                  : FontWeight.w800,
                            ),
                          ),
                        ),
                        if (!notification.isRead) ...[
                          const SizedBox(width: 7),
                          const CircleAvatar(radius: 4, backgroundColor: gold),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark
                            ? const Color(0xFFCBD5E1)
                            : const Color(0xFF4F4F59),
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                    if (notification.createdAt != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        _formatDateTime(notification.createdAt!),
                        style: const TextStyle(color: muted, fontSize: 10.5),
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
    final isDark = themeController.isDarkMode;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E2E8),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.notifications_none_rounded,
            color: isDark ? gold : navy,
            size: 51,
          ),
          const SizedBox(height: 15),
          Text(
            'No notifications',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'New updates will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    final isDark = themeController.isDarkMode;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 46),
          const SizedBox(height: 13),
          Text(
            'Unable to load notifications',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
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
              backgroundColor: isDark ? gold : navy,
              foregroundColor: isDark ? navy : Colors.white,
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