import 'package:flutter/material.dart';

import '../main.dart';
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

  static Widget scannerButton(
    BuildContext context, {
    int currentIndex = -1,
    VoidCallback? onPressed,
  }) {
    return Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        color: const Color(0xFFFFC800),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFC800).withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: RawMaterialButton(
        onPressed: onPressed,
        shape: const CircleBorder(),
        elevation: 0,
        child: const Icon(
          Icons.qr_code_scanner_rounded,
          color: Color(0xFF080878),
          size: 28,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeController.isDarkMode;
    final backgroundColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final unselectedColor =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF808080);
    final selectedColor =
        isDark ? const Color(0xFFFFC800) : const Color(0xFF080878);

    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: backgroundColor,
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _navItem(
            context,
            icon: Icons.home_rounded,
            label: 'Home',
            isSelected: currentIndex == 0,
            selectedColor: selectedColor,
            unselectedColor: unselectedColor,
            onTap: () {
              if (currentIndex == 0) {
                onHomeRefresh?.call();
              } else {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
                  (route) => false,
                );
              }
            },
          ),
          _navItem(
            context,
            icon: Icons.notifications_rounded,
            label: 'Notifications',
            isSelected: currentIndex == 1,
            badgeCount: notificationBadge,
            selectedColor: selectedColor,
            unselectedColor: unselectedColor,
            onTap: () {
              if (currentIndex != 1) {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const NotificationsScreen(),
                  ),
                );
              }
            },
          ),
          const SizedBox(width: 48), // Spacer for center scanner FAB
          _navItem(
            context,
            icon: Icons.calendar_month_rounded,
            label: 'Calendar',
            isSelected: currentIndex == 2,
            selectedColor: selectedColor,
            unselectedColor: unselectedColor,
            onTap: () {
              if (currentIndex != 2) {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CalendarScreen(),
                  ),
                );
              }
            },
          ),
          _navItem(
            context,
            icon: Icons.assignment_late_rounded,
            label: 'Sanction',
            isSelected: currentIndex == 3,
            selectedColor: selectedColor,
            unselectedColor: unselectedColor,
            onTap: () {
              if (currentIndex != 3) {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SanctionsScreen(),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _navItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool isSelected,
    required Color selectedColor,
    required Color unselectedColor,
    required VoidCallback onTap,
    int badgeCount = 0,
  }) {
    final color = isSelected ? selectedColor : unselectedColor;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: color, size: 24),
                if (badgeCount > 0)
                  Positioned(
                    right: -6,
                    top: -4,
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
                        '$badgeCount',
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
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}