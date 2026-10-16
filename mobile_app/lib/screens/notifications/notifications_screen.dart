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
  static const Color muted = Color(0xFF64748B);

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
    if (!mounted) return;

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
    if (notification.isRead) return;
    final result = await NotificationService.instance.markAsRead(notification.id);
    if (!mounted) return;

    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
      return;
    }

    setState(() {
      _notifications = _notifications.map((item) {
        if (item.id == notification.id) {
          return item.copyWith(isRead: true, readAt: DateTime.now());
        }
        return item;
      }).toList();

      if (_unreadCount > 0) _unreadCount--;
    });
  }

  Future<void> _markAllRead() async {
    if (_markingAll || _unreadCount == 0) return;
    setState(() => _markingAll = true);

    final result = await NotificationService.instance.markAllAsRead();
    if (!mounted) return;

    setState(() => _markingAll = false);
    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
      return;
    }

    final now = DateTime.now();
    setState(() {
      _notifications = _notifications.map((item) => item.copyWith(isRead: true, readAt: now)).toList();
      _unreadCount = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeController.isDarkMode;

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
                  const Text(
                    'Notifications',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const Spacer(),
                  if (_unreadCount > 0)
                    TextButton(
                      onPressed: _markingAll ? null : _markAllRead,
                      style: TextButton.styleFrom(
                        foregroundColor: gold,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(50, 30),
                      ),
                      child: _markingAll
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: gold,
                              ),
                            )
                          : const Text(
                              'Mark all read',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
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
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 180),
          Center(child: CircularProgressIndicator(color: gold)),
        ],
      );
    }

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [const SizedBox(height: 100), _buildErrorCard()],
      );
    }

    final filtered = _showUnreadOnly
        ? _notifications.where((item) => !item.isRead).toList()
        : _notifications;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
      children: [
        _buildSegmentedFilter(),
        const SizedBox(height: 14),
        if (filtered.isEmpty)
          _buildEmptyState()
        else
          ..._buildNotificationList(filtered.take(_visibleLimit).toList()),
      ],
    );
  }

  Widget _buildSegmentedFilter() {
    final isDark = themeController.isDarkMode;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _showUnreadOnly = false;
                _visibleLimit = 15;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 7),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: !_showUnreadOnly
                      ? (isDark ? const Color(0xFF0F172A) : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'All (${_notifications.length})',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: !_showUnreadOnly
                        ? (isDark ? Colors.white : navy)
                        : muted,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _showUnreadOnly = true;
                _visibleLimit = 15;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 7),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _showUnreadOnly
                      ? (isDark ? const Color(0xFF0F172A) : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Unread ($_unreadCount)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _showUnreadOnly
                        ? (isDark ? Colors.white : navy)
                        : muted,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildNotificationList(List<NotificationItem> notifications) {
    final widgets = <Widget>[];
    String? currentDay;

    for (final notification in notifications) {
      final day = notification.createdAt == null
          ? 'Recent'
          : DateFormat('MMMM d, yyyy').format(notification.createdAt!.toLocal());

      if (day != currentDay) {
        if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 10));
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(
              day.toUpperCase(),
              style: const TextStyle(
                color: muted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
        );
        currentDay = day;
      }

      widgets.add(_buildCleanCard(notification));
      widgets.add(const SizedBox(height: 8));
    }

    return widgets;
  }

  Widget _buildCleanCard(NotificationItem notification) {
    final isDark = themeController.isDarkMode;
    final accentColor = _notificationColor(notification.type);
    final icon = _notificationIcon(notification.type);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _markRead(notification),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              Container(
                width: 3.5,
                height: 68,
                color: notification.isRead ? Colors.transparent : accentColor,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(icon, color: accentColor, size: 18),
                      ),
                      const SizedBox(width: 10),
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
                                      fontSize: 13,
                                      fontWeight: notification.isRead
                                          ? FontWeight.w600
                                          : FontWeight.w700,
                                      color: isDark ? Colors.white : navy,
                                    ),
                                  ),
                                ),
                                if (notification.createdAt != null)
                                  Text(
                                    DateFormat('h:mm a').format(notification.createdAt!.toLocal()),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: muted,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              notification.message,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                height: 1.3,
                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final isDark = themeController.isDarkMode;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(
            Icons.notifications_off_outlined,
            size: 40,
            color: muted.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 10),
          Text(
            'All caught up',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : navy,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'You have no notifications to review.',
            style: TextStyle(fontSize: 11.5, color: muted),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
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
            _error ?? 'Failed to load notifications.',
            style: const TextStyle(fontSize: 12, color: muted),
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: _loadNotifications,
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? gold : navy,
              foregroundColor: isDark ? navy : Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Try Again', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  IconData _notificationIcon(String type) {
    switch (type.trim().toLowerCase()) {
      case 'event':
      case 'upcoming_event':
        return Icons.event_note_rounded;
      case 'attendance':
      case 'attendance_recorded':
        return Icons.verified_rounded;
      case 'sanction':
      case 'warning':
        return Icons.gpp_bad_rounded;
      default:
        return Icons.notifications_active_rounded;
    }
  }

  Color _notificationColor(String type) {
    switch (type.trim().toLowerCase()) {
      case 'attendance':
      case 'attendance_recorded':
        return const Color(0xFF16A34A); // Green for attendance
      case 'sanction':
      case 'warning':
        return const Color(0xFFDC2626); // Red for sanctions
      case 'event':
      case 'upcoming_event':
        return const Color(0xFF3B82F6); // Blue for scheduled events
      default:
        return const Color(0xFFD97706); // Amber for general
    }
  }
}