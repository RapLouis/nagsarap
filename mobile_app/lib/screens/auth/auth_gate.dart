import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../services/auth_service.dart';
import '../home/home_screen.dart';
import 'auth_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool loading = true;

  Map<String, dynamic>? user;
  Map<String, dynamic>? student;

  bool authenticated = false;

  @override
  void initState() {
    super.initState();

    restoreSession();
  }

  /*
  |--------------------------------------------------------------------------
  | RESTORE LOGIN SESSION
  |--------------------------------------------------------------------------
  */

  Future<void> restoreSession() async {
    final hasSession = await AuthService.instance.hasSavedSession();

    if (!hasSession) {
      if (!mounted) {
        return;
      }

      setState(() {
        loading = false;
        authenticated = false;
      });

      return;
    }

    final result = await AuthService.instance.me();

    if (!mounted) {
      return;
    }

    if (result.success) {
      setState(() {
        user = result.user;
        student = result.student;

        authenticated = true;

        loading = false;
      });
    } else {
      setState(() {
        authenticated = false;
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    /*
    |--------------------------------------------------------------------------
    | LOADING
    |--------------------------------------------------------------------------
    */

    if (loading) {
      return const Scaffold(
        backgroundColor: AppColors.navy,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 58,
                  height: 58,
                  child: CircularProgressIndicator(
                    strokeWidth: 4,
                    color: AppColors.gold,
                  ),
                ),
                SizedBox(height: 22),
                Text(
                  'CCIS Attendance',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Restoring your session...',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      );
    }

    /*
    |--------------------------------------------------------------------------
    | AUTHENTICATED
    |--------------------------------------------------------------------------
    */

    if (authenticated) {
      return HomeScreen(user: user, student: student);
    }

    /*
    |--------------------------------------------------------------------------
    | NOT AUTHENTICATED
    |--------------------------------------------------------------------------
    */

    return const AuthScreen();
  }
}
