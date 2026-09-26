import 'package:flutter/material.dart';

class AttendanceSplashScreen extends StatefulWidget {
  final Widget nextScreen;

  const AttendanceSplashScreen({super.key, required this.nextScreen});

  @override
  State<AttendanceSplashScreen> createState() => _AttendanceSplashScreenState();
}

class _AttendanceSplashScreenState extends State<AttendanceSplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => widget.nextScreen));
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF080878),
      body: Center(child: CircularProgressIndicator(color: Colors.white)),
    );
  }
}
