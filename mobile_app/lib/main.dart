import 'package:flutter/material.dart';

import 'core/app_theme.dart';
import 'screens/auth/auth_gate.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const CcisAttendanceApp());
}

class CcisAttendanceApp extends StatelessWidget {
  const CcisAttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CCIS Attendance System',

      debugShowCheckedModeBanner: false,

      theme: AppTheme.lightTheme,

      home: const AuthGate(),
    );
  }
}
