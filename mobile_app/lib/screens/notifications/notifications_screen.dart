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
    if (!notification.isRead) {
      final result = await NotificationService.instance.markAsRead(notification.id);
      if (result.success) {
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
    }
    
    if (!mounted) return;
    _showCenteredNotificationModal(notification);
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
          elevation: 8,
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
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isDark ? parsed.config.iconBgDark : parsed.config.iconBgLight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: parsed.config.color.withValues(alpha: 0.3),
                          width: 1.0,
                        ),
                      ),
                      child: Icon(parsed.config.icon, color: parsed.config.color, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: isDark ? parsed.config.badgeBgDark : parsed.config.badgeBgLight,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          parsed.sessionLabel,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: isDark ? parsed.config.badgeTextDark : parsed.config.badgeTextLight,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.close_rounded, size: 20, color: muted),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(height: 1, color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                      width: 1.0,
                    ),
                  ),
                  child: Column(
                    children: [
                      _buildInfoRow('Recorded Date', dateStr, isDark),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Divider(
                          height: 1,
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      _buildInfoRow('Event Session', parsed.eventSessionType, isDark),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  notification.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : navy,
                    letterSpacing: -0.2,
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
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 42,
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
                      'Close Notice',
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

  Widget _buildInfoRow(String label, String value, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: muted,
            fontWeight: FontWeight.w500,
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
        ),
      ],
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
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markingAll ? null : _markAllRead,
              style: TextButton.styleFrom(
                foregroundColor: gold,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
          ..._buildNotificationList(filtered.take(_visibleLimit).toList()),
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
              onTap: () => setState(() {
                _showUnreadOnly = false;
                _visibleLimit = 15;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: !_showUnreadOnly
                      ? (isDark ? const Color(0xFF0F172A) : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: !_showUnreadOnly
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          )
                        ]
                      : null,
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
              onTap: () => setState(() {
                _showUnreadOnly = true;
                _visibleLimit = 15;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _showUnreadOnly
                      ? (isDark ? const Color(0xFF0F172A) : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: _showUnreadOnly
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          )
                        ]
                      : null,
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
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: notification.isRead
                  ? (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0))
                  : parsed.config.color.withValues(alpha: 0.4),
              width: notification.isRead ? 1.0 : 1.2,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isDark ? parsed.config.iconBgDark : parsed.config.iconBgLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: parsed.config.color.withValues(alpha: 0.25),
                    width: 1.0,
                  ),
                ),
                child: Icon(parsed.config.icon, color: parsed.config.color, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: isDark ? parsed.config.badgeBgDark : parsed.config.badgeBgLight,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            parsed.sessionLabel,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                              color: isDark ? parsed.config.badgeTextDark : parsed.config.badgeTextLight,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (notification.createdAt != null)
                          Text(
                            DateFormat('h:mm a').format(notification.createdAt!.toLocal()),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF94A3B8),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        if (!notification.isRead) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: parsed.config.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      notification.title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: notification.isRead ? FontWeight.w600 : FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                        height: 1.2,
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
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.notifications_none_rounded,
              size: 32,
              color: muted.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'All caught up',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
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
          const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 28),
          const SizedBox(height: 8),
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

    if (combined.contains('fail') || combined.contains('error') || combined.contains('absent') || combined.contains('already checked out')) {
      return const _ParsedNotification(
        sessionLabel: 'ATTENDANCE FAILED',
        eventSessionType: 'Failed / Disqualified',
        config: _NotificationConfig(
          color: Color(0xFFDC2626),
          badgeBgLight: Color(0xFFFEE2E2),
          badgeTextLight: Color(0xFFB91C1C),
          iconBgLight: Color(0xFFFEF2F2),
          badgeBgDark: Color(0xFF7F1D1D),
          badgeTextDark: Color(0xFFFECACA),
          iconBgDark: Color(0xFF450A0A),
          icon: Icons.cancel_outlined,
        ),
      );
    }

    bool isTimeIn = combined.contains('time-in') || combined.contains('time in') || combined.contains('timein') || combined.contains('check-in') || combined.contains('check in');
    bool isTimeOut = combined.contains('time-out') || combined.contains('time out') || combined.contains('timeout') || combined.contains('check-out') || combined.contains('check out');

    if (isTimeIn && !isTimeOut) {
      return const _ParsedNotification(
        sessionLabel: 'TIME-IN RECORDED',
        eventSessionType: 'Time-In Session',
        config: _NotificationConfig(
          color: Color(0xFF16A34A),
          badgeBgLight: Color(0xFFDCFCE7),
          badgeTextLight: Color(0xFF15803D),
          iconBgLight: Color(0xFFF0FDF4),
          badgeBgDark: Color(0xFF064E3B),
          badgeTextDark: Color(0xFF86EFAC),
          iconBgDark: Color(0xFF022C22),
          icon: Icons.login_rounded,
        ),
      );
    }

    if (isTimeOut && !isTimeIn) {
      return const _ParsedNotification(
        sessionLabel: 'TIME-OUT RECORDED',
        eventSessionType: 'Time-Out Session',
        config: _NotificationConfig(
          color: Color(0xFF2563EB),
          badgeBgLight: Color(0xFFDBEAFE),
          badgeTextLight: Color(0xFF1D4ED8),
          iconBgLight: Color(0xFFEFF6FF),
          badgeBgDark: Color(0xFF1E3A8A),
          badgeTextDark: Color(0xFF93C5FD),
          iconBgDark: Color(0xFF172554),
          icon: Icons.logout_rounded,
        ),
      );
    }

    if (combined.contains('update') || combined.contains('reschedule') || combined.contains('change')) {
      return const _ParsedNotification(
        sessionLabel: 'EVENT UPDATED',
        eventSessionType: 'Schedule Update',
        config: _NotificationConfig(
          color: Color(0xFFD97706),
          badgeBgLight: Color(0xFFFEF3C7),
          badgeTextLight: Color(0xFFB45309),
          iconBgLight: Color(0xFFFFFBEB),
          badgeBgDark: Color(0xFF78350F),
          badgeTextDark: Color(0xFFFDE68A),
          iconBgDark: Color(0xFF451A03),
          icon: Icons.update_rounded,
        ),
      );
    }

    if (combined.contains('sanction') || combined.contains('warning') || combined.contains('penalty')) {
      return const _ParsedNotification(
        sessionLabel: 'SANCTION NOTICE',
        eventSessionType: 'Warning / Sanction',
        config: _NotificationConfig(
          color: Color(0xFFE11D48),
          badgeBgLight: Color(0xFFFFE4E6),
          badgeTextLight: Color(0xFFBE123C),
          iconBgLight: Color(0xFFFFF1F2),
          badgeBgDark: Color(0xFF881337),
          badgeTextDark: Color(0xFFFDA4AF),
          iconBgDark: Color(0xFF4C0519),
          icon: Icons.gpp_maybe_outlined,
        ),
      );
    }

    return const _ParsedNotification(
      sessionLabel: 'VERIFIED PRESENT',
      eventSessionType: 'General Attendance',
      config: _NotificationConfig(
        color: Color(0xFF16A34A),
        badgeBgLight: Color(0xFFDCFCE7),
        badgeTextLight: Color(0xFF15803D),
        iconBgLight: Color(0xFFF0FDF4),
        badgeBgDark: Color(0xFF064E3B),
        badgeTextDark: Color(0xFF86EFAC),
        iconBgDark: Color(0xFF022C22),
        icon: Icons.check_circle_outline_rounded,
      ),
    );
  }
}

class _ParsedNotification {
  final String sessionLabel;
  final String eventSessionType;
  final _NotificationConfig config;

  const _ParsedNotification({
    required this.sessionLabel,
    required this.eventSessionType,
    required this.config,
  });
}

class _NotificationConfig {
  final Color color;
  final Color badgeBgLight;
  final Color badgeTextLight;
  final Color iconBgLight;
  final Color badgeBgDark;
  final Color badgeTextDark;
  final Color iconBgDark;
  final IconData icon;

  const _NotificationConfig({
    required this.color,
    required this.badgeBgLight,
    required this.badgeTextLight,
    required this.iconBgLight,
    required this.badgeBgDark,
    required this.badgeTextDark,
    required this.iconBgDark,
    required this.icon,
  });
}