import 'package:flutter/material.dart';

import '../screens/calendar/calendar_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/sanctions/sanctions_screen.dart';

class MainBottomNavigation extends StatelessWidget {
  const MainBottomNavigation({
    super.key,
    required this.currentIndex,
    this.notificationBadge = 0,
    this.onHomeRefresh,
    this.onScan,
  });

  final int currentIndex;
  final int notificationBadge;
  final VoidCallback? onHomeRefresh;
  final VoidCallback? onScan;

  static const Color brandNavy = Color(0xFF080878);
  static const Color brandGold = Color(0xFFFFC800);

  void _onItemTapped(BuildContext context, int index) {
    if (index == currentIndex) {
      if (index == 0 && onHomeRefresh != null) {
        onHomeRefresh!();
      }
      return;
    }

    Widget destination;
    switch (index) {
      case 0:
        destination = const HomeScreen();
        break;
      case 1:
        destination = const NotificationsScreen();
        break;
      case 2:
        destination = const CalendarScreen();
        break;
      case 3:
        destination = const SanctionsScreen();
        break;
      default:
        destination = const HomeScreen();
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => destination,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      shape: currentIndex == 0 ? const CircularNotchedRectangle() : null,
      notchMargin: 8,
      color: Colors.white,
      elevation: 12,
      child: SizedBox(
        height: 60,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(
              context: context,
              index: 0,
              icon: Icons.home_rounded,
              label: 'Home',
            ),
            _buildNavItem(
              context: context,
              index: 1,
              icon: Icons.notifications_rounded,
              label: 'Notifications',
              badgeCount: notificationBadge,
            ),
            if (currentIndex == 0) const SizedBox(width: 48),
            _buildNavItem(
              context: context,
              index: 2,
              icon: Icons.calendar_month_rounded,
              label: 'Calendar',
            ),
            _buildNavItem(
              context: context,
              index: 3,
              icon: Icons.assignment_late_rounded,
              label: 'Sanction',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required BuildContext context,
    required int index,
    required IconData icon,
    required String label,
    int badgeCount = 0,
  }) {
    final bool isSelected = currentIndex == index;
    final Color color = isSelected ? brandNavy : Colors.grey.shade500;

    return InkWell(
      onTap: () => _onItemTapped(context, index),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: color, size: 22),
                if (badgeCount > 0)
                  Positioned(
                    right: -6,
                    top: -3,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 14,
                        minHeight: 14,
                      ),
                      child: Text(
                        badgeCount > 9 ? '9+' : '$badgeCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Scanner button helper that only renders when currentIndex == 0 (Home Screen)
  static Widget? scannerButton(
    BuildContext context, {
    int currentIndex = 0,
    VoidCallback? onPressed,
  }) {
    if (currentIndex != 0) return null;

    return FloatingActionButton(
      backgroundColor: brandGold,
      elevation: 4,
      onPressed: onPressed ??
          () {
            Navigator.of(context).pushNamed('/scan');
          },
      child: const Icon(
        Icons.qr_code_scanner_rounded,
        color: Colors.white,
        size: 28,
      ),
    );
  }
}