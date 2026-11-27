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
  bool _showUnreadOnly = false;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  int get _unreadCount => _notifications.where((n) => !n.isRead).length;

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
        // Sort notifications: Latest (newest timestamp) on top
        final sortedList = List<NotificationItem>.from(result.notifications);
        sortedList.sort((a, b) {
          final first = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final second = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return second.compareTo(first); // Descending order
        });

        _notifications = sortedList;
        _error = null;
      } else {
        _notifications = const [];
        _error = result.message;
      }
    });
  }

  Future<void> _markRead(NotificationItem notification) async {
    if (!notification.isRead) {
      // Optimistic local update while preserving list order
      setState(() {
        _notifications = _notifications.map((item) {
          if (item.id == notification.id) {
            return item.copyWith(isRead: true, readAt: DateTime.now());
          }
          return item;
        }).toList();
      });

      // Background API call
      await NotificationService.instance.markAsRead(notification.id);
    }

    if (!mounted) return;
    _showCenteredNotificationModal(notification);
  }

  Future<void> _markAllRead() async {
    if (_markingAll || _unreadCount == 0) return;
    setState(() => _markingAll = true);

    final now = DateTime.now();

    // Optimistically mark all as read locally
    setState(() {
      _notifications = _notifications.map((item) {
        return item.copyWith(isRead: true, readAt: now);
      }).toList();
    });

    final result = await NotificationService.instance.markAllAsRead();
    if (!mounted) return;

    setState(() => _markingAll = false);

    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    }
  }

  void _showCenteredNotificationModal(NotificationItem notification) {
    final isDark = themeController.isDarkMode;
    final parsed = _parseNotificationDetails(notification);

    final dateStr = notification.createdAt == null
        ? 'Recent'
        : DateFormat('MMMM d, yyyy • h:mm a').format(notification.createdAt!.toLocal());

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext ctx) {
        return Dialog(
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              width: 1.0,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? parsed.badgeBgDark : parsed.badgeBgLight,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        parsed.badgeLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                          color: isDark ? parsed.badgeTextDark : parsed.badgeTextColor,
                        ),
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Text(
                        'Close',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? gold : navy,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(height: 1, color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                const SizedBox(height: 14),
                Text(
                  dateStr,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: muted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  notification.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : navy,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  notification.message,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark ? gold : navy,
                      foregroundColor: isDark ? navy : Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Done',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeController.isDarkMode;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E293B) : navy,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              Navigator.of(context).pushReplacementNamed('/home');
            }
          },
        ),
        title: const Text(
          'Notifications',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markingAll ? null : _markAllRead,
              style: TextButton.styleFrom(
                foregroundColor: gold,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
          const SizedBox(width: 6),
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
        const SizedBox(height: 16),
        if (filtered.isEmpty)
          _buildEmptyState()
        else
          ..._buildNotificationList(filtered),
      ],
    );
  }

  Widget _buildSegmentedFilter() {
    final isDark = themeController.isDarkMode;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _showUnreadOnly = false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 8),
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
                    fontWeight: FontWeight.w700,
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
              onTap: () => setState(() => _showUnreadOnly = true),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 8),
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
                    fontWeight: FontWeight.w700,
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
          : DateFormat('EEEE, MMMM d').format(notification.createdAt!.toLocal());

      if (day != currentDay) {
        if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 12));
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Text(
              day.toUpperCase(),
              style: const TextStyle(
                color: muted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
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
    final parsed = _parseNotificationDetails(notification);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _markRead(notification),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: notification.isRead
                  ? (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0))
                  : parsed.borderColor,
              width: notification.isRead ? 1.0 : 1.2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDark ? parsed.badgeBgDark : parsed.badgeBgLight,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      parsed.badgeLabel,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                        color: isDark ? parsed.badgeTextDark : parsed.badgeTextColor,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (notification.createdAt != null)
                    Text(
                      DateFormat('h:mm a').format(notification.createdAt!.toLocal()),
                      style: const TextStyle(
                        fontSize: 11,
                        color: muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  if (!notification.isRead) ...[
                    const SizedBox(width: 8),
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: parsed.borderColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Text(
                notification.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: notification.isRead ? FontWeight.w600 : FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                notification.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
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
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
      alignment: Alignment.center,
      child: Column(
        children: [
          Text(
            'All caught up',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : navy,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'You have no unread updates to review.',
            style: TextStyle(fontSize: 12, color: muted),
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
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        children: [
          Text(
            _error ?? 'Failed to load notifications.',
            style: const TextStyle(fontSize: 12, color: muted),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _loadNotifications,
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? gold : navy,
              foregroundColor: isDark ? navy : Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: const Text('Try Again', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  _ParsedNotification _parseNotificationDetails(NotificationItem notification) {
    final title = notification.title.trim().toLowerCase();
    final message = notification.message.trim().toLowerCase();
    final type = notification.type.trim().toLowerCase();
    final combined = '$title $message $type';

    // 1. Missed Attendance / Absent / Record Error
    if (type.contains('missed') ||
        type.contains('absent') ||
        combined.contains('missed attendance') ||
        combined.contains('did not attend') ||
        type.contains('error') ||
        type.contains('fail') ||
        combined.contains('error') ||
        combined.contains('failed') ||
        combined.contains('absent')) {
      return const _ParsedNotification(
        badgeLabel: 'MISSED ATTENDANCE',
        badgeTextColor: Color(0xFFB91C1C),
        badgeBgLight: Color(0xFFFEE2E2),
        borderColor: Color(0xFFEF4444),
        badgeBgDark: Color(0xFF7F1D1D),
        badgeTextDark: Color(0xFFFECACA),
      );
    }

    // 2. New Event Creation
    if (type.contains('event_created') ||
        combined.contains('new event') ||
        combined.contains('created a new event') ||
        combined.contains('event scheduled')) {
      return const _ParsedNotification(
        badgeLabel: 'NEW EVENT',
        badgeTextColor: Color(0xFF4338CA),
        badgeBgLight: Color(0xFFE0E7FF),
        borderColor: Color(0xFF6366F1),
        badgeBgDark: Color(0xFF312E81),
        badgeTextDark: Color(0xFFC7D2FE),
      );
    }

    // 3. Admin Event Update / Reschedule
    if (type.contains('event_updated') ||
        combined.contains('event updated') ||
        combined.contains('rescheduled') ||
        combined.contains('updated event') ||
        combined.contains('admin updated')) {
      return const _ParsedNotification(
        badgeLabel: 'EVENT UPDATED',
        badgeTextColor: Color(0xFFC2410C),
        badgeBgLight: Color(0xFFFFEDD5),
        borderColor: Color(0xFFF97316),
        badgeBgDark: Color(0xFF7C2D12),
        badgeTextDark: Color(0xFFFDBA74),
      );
    }

    // 4. Sanction / Warning
    if (type.contains('sanction') ||
        combined.contains('sanction') ||
        combined.contains('warning') ||
        combined.contains('penalty')) {
      return const _ParsedNotification(
        badgeLabel: 'SANCTION NOTICE',
        badgeTextColor: Color(0xFFBE123C),
        badgeBgLight: Color(0xFFFFE4E6),
        borderColor: Color(0xFFF43F5E),
        badgeBgDark: Color(0xFF881337),
        badgeTextDark: Color(0xFFFDA4AF),
      );
    }

    // 5. Default: Attendance Success
    return const _ParsedNotification(
      badgeLabel: 'ATTENDANCE SUCCESS',
      badgeTextColor: Color(0xFF15803D),
      badgeBgLight: Color(0xFFDCFCE7),
      borderColor: Color(0xFF22C55E),
      badgeBgDark: Color(0xFF064E3B),
      badgeTextDark: Color(0xFF86EFAC),
    );
  }
}

class _ParsedNotification {
  final String badgeLabel;
  final Color badgeTextColor;
  final Color badgeBgLight;
  final Color borderColor;
  final Color badgeBgDark;
  final Color badgeTextDark;

  const _ParsedNotification({
    required this.badgeLabel,
    required this.badgeTextColor,
    required this.badgeBgLight,
    required this.borderColor,
    required this.badgeBgDark,
    required this.badgeTextDark,
  });
}