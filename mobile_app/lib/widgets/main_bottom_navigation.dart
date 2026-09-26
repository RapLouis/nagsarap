import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../screens/calendar/calendar_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/sanctions/sanctions_screen.dart';

class MainBottomNavigation extends StatelessWidget {
  final int currentIndex;
  final int notificationBadge;
  final VoidCallback? onHomeRefresh;
  final VoidCallback? onScan;

  const MainBottomNavigation({
    super.key,
    required this.currentIndex,
    this.notificationBadge = 0,
    this.onHomeRefresh,
    this.onScan,
  });

  void _open(BuildContext context, int index) {
    if (index == currentIndex) {
      if (index == 0) {
        onHomeRefresh?.call();
      }
      return;
    }

    // Keep the Home screen as the root route. This preserves the loaded
    // student identity and dashboard state when the user returns Home.
    Navigator.of(context).popUntil((route) => route.isFirst);

    if (index == 0) {
      onHomeRefresh?.call();
      return;
    }

    final Widget page = switch (index) {
      1 => const NotificationsScreen(),
      2 => const CalendarScreen(),
      3 => const SanctionsScreen(),
      _ => const HomeScreen(),
    };

    Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, animation, __) =>
            FadeTransition(opacity: animation, child: page),
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 140),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      height: 82,
      padding: EdgeInsets.zero,
      color: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 12,
      notchMargin: 8,
      shape: const CircularNotchedRectangle(),
      child: Row(
        children: [
          _item(context, 0, Icons.home_rounded, Icons.home_outlined, 'Home'),
          _item(
            context,
            1,
            Icons.notifications_rounded,
            Icons.notifications_none_rounded,
            'Notifications',
            badge: notificationBadge,
          ),
          const SizedBox(width: 76),
          _item(
            context,
            2,
            Icons.calendar_month_rounded,
            Icons.calendar_today_outlined,
            'Calendar',
          ),
          _item(
            context,
            3,
            Icons.assignment_rounded,
            Icons.assignment_outlined,
            'Sanction',
          ),
        ],
      ),
    );
  }

  Widget _item(
    BuildContext context,
    int index,
    IconData selectedIcon,
    IconData icon,
    String label, {
    int badge = 0,
  }) {
    final selected = currentIndex == index;
    final color = selected ? AppColors.navy : AppColors.textMuted;

    return Expanded(
      child: InkWell(
        onTap: () => _open(context, index),
        child: Padding(
          padding: const EdgeInsets.only(top: 9, bottom: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: Icon(
                      selected ? selectedIcon : icon,
                      key: ValueKey<bool>(selected),
                      color: color,
                      size: 24,
                    ),
                  ),
                  if (badge > 0)
                    Positioned(
                      right: -10,
                      top: -7,
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: AppColors.error,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          badge > 99 ? '99+' : '$badge',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: color,
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget scannerButton(BuildContext context, {VoidCallback? onPressed}) {
    return SizedBox(
      width: 72,
      height: 72,
      child: FloatingActionButton(
        heroTag: null,
        elevation: 5,
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.navyDark,
        shape: const CircleBorder(),
        onPressed:
            onPressed ??
            () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const HomeScreen(openScannerOnLoad: true),
                ),
              );
            },
        child: const Icon(Icons.center_focus_strong_rounded, size: 34),
      ),
    );
  }
}
