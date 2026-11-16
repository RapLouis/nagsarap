import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';

import 'controllers/theme_controller.dart';
import 'screens/splash/app_splash_screen.dart';
import 'services/attendance_service.dart';

final ThemeController themeController = ThemeController();

/// Top-level background entry point required by Flutter WorkManager.
/// Marked with `@pragma('vm:entry-point')` to prevent tree-shaking in release builds.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      debugPrint('[WORKMANAGER] Starting background offline attendance sync...');

      final syncResult =
          await AttendanceService.instance.syncPendingOfflineAttendance();

      debugPrint('[WORKMANAGER] Sync complete: ${syncResult.message}');
      return true;
    } catch (e) {
      debugPrint('[WORKMANAGER ERROR] Background sync failed: $e');
      return false;
    }
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );

    await Workmanager().registerPeriodicTask(
      'attendance_offline_sync_task',
      'syncOfflineAttendanceTask',
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
  } catch (e, stack) {
    debugPrint('[STARTUP WORKMANAGER ERROR] $e\n$stack');
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    themeController.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    themeController.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Attend',
      debugShowCheckedModeBanner: false,
      themeMode: themeController.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF8F9FC),
        primaryColor: const Color(0xFF080878),
        cardColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF080878),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF080878),
          secondary: Color(0xFFFFC800),
          surface: Colors.white,
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        primaryColor: const Color(0xFF1E293B),
        cardColor: const Color(0xFF1E293B),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E293B),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF1E293B),
          secondary: Color(0xFFFFC800),
          surface: Color(0xFF1E293B),
        ),
      ),
      home: const AppSplashScreen(),
    );
  }
}