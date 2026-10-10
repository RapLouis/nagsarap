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
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: const Color(0xFFFFC800),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFC800).withValues(alpha: 0.35),
            blurRadius: 14,
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
          size: 26,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeController.isDarkMode;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final backgroundColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final unselectedColor =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final selectedColor =
        isDark ? const Color(0xFFFFC800) : const Color(0xFF080878);

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        bottom: true,
        child: Padding(
          padding: EdgeInsets.only(
            top: 8,
            bottom: bottomInset > 0 ? 0 : 6,
          ),
          child: SizedBox(
            height: 60,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _navItem(
                  context,
                  icon: Icons.grid_view_rounded,
                  label: 'Home',
                  isSelected: currentIndex == 0,
                  selectedColor: selectedColor,
                  unselectedColor: unselectedColor,
                  onTap: () {
                    if (currentIndex == 0) {
                      onHomeRefresh?.call();
                    } else {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute<void>(
                          builder: (_) => const HomeScreen(),
                        ),
                        (route) => false,
                      );
                    }
                  },
                ),
                _navItem(
                  context,
                  icon: Icons.notifications_none_rounded,
                  selectedIcon: Icons.notifications_rounded,
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
                const SizedBox(width: 48), // Center floating action button gap
                _navItem(
                  context,
                  icon: Icons.calendar_today_rounded,
                  selectedIcon: Icons.calendar_month_rounded,
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
                  icon: Icons.assignment_outlined,
                  selectedIcon: Icons.assignment_rounded,
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
          ),
        ),
      ),
    );
  }

  Widget _navItem(
    BuildContext context, {
    required IconData icon,
    IconData? selectedIcon,
    required String label,
    required bool isSelected,
    required Color selectedColor,
    required Color unselectedColor,
    required VoidCallback onTap,
    int badgeCount = 0,
  }) {
    final color = isSelected ? selectedColor : unselectedColor;
    final activeIcon = isSelected ? (selectedIcon ?? icon) : icon;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(activeIcon, color: color, size: 22),
                if (badgeCount > 0)
                  Positioned(
                    right: -5,
                    top: -3,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
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
                          fontWeight: FontWeight.w800,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}