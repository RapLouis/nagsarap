import 'package:flutter/material.dart';
import 'controllers/theme_controller.dart';
import 'screens/auth/auth_gate.dart';

final ThemeController themeController = ThemeController();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
      title: 'CCIS Attendance',
      debugShowCheckedModeBanner: false,
      themeMode: themeController.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      
      // Light Mode Configuration
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

      // Dark Mode Configuration
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

      home: const AuthGate(),
    );
  }
}