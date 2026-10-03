import 'dart:async';
import 'package:flutter/material.dart';

import '../home/home_screen.dart';

class AppSplashScreen extends StatefulWidget {
  const AppSplashScreen({super.key});

  @override
  State<AppSplashScreen> createState() => _AppSplashScreenState();
}

class _AppSplashScreenState extends State<AppSplashScreen>
    with TickerProviderStateMixin {
  static const Color navy = Color(0xFF080878);
  static const Color gold = Color(0xFFFFC800);
  static const Color emerald = Color(0xFF10B981);

  late AnimationController _scanController;
  late AnimationController _checkController;
  late Animation<double> _scanLineAnimation;
  late Animation<double> _checkScaleAnimation;

  bool _isScanned = false;

  @override
  void initState() {
    super.initState();

    // 800ms per pass -> 4 passes over 3.2 seconds
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _scanLineAnimation = Tween<double>(begin: -1.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanController, curve: Curves.easeInOut),
    );

    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _checkScaleAnimation = CurvedAnimation(
      parent: _checkController,
      curve: Curves.elasticOut,
    );

    _startSplashScreenSequence();
  }

  Future<void> _startSplashScreenSequence() async {
    // Wait for 4 complete laser sweeps
    await Future.delayed(const Duration(milliseconds: 3200));

    if (!mounted) return;

    _scanController.stop();
    setState(() {
      _isScanned = true;
    });
    _checkController.forward();

    await Future.delayed(const Duration(milliseconds: 1000));

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (context, animation, secondaryAnimation) =>
            const HomeScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  void dispose() {
    _scanController.dispose();
    _checkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: navy,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),

              Stack(
                alignment: Alignment.center,
                children: [
                  // Outer Circle Border
                  Container(
                    width: 185,
                    height: 185,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: (_isScanned ? emerald : gold).withValues(alpha: 0.3),
                        width: 2,
                      ),
                    ),
                  ),

                  // Inner Circle Ring Container
                  Container(
                    width: 155,
                    height: 155,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.05),
                      border: Border.all(
                        color: _isScanned ? emerald : gold,
                        width: 3,
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Biometric HUD Target Frame Corners
                        CustomPaint(
                          size: const Size(110, 110),
                          painter: _HUDFaceFramePainter(
                            color: _isScanned ? emerald : gold,
                          ),
                        ),

                        // Distinct Facial Recognition Biometric Silhouette Icon
                        Icon(
                          Icons.face_retouching_natural_rounded,
                          size: 72,
                          color: _isScanned ? emerald : gold,
                        ),
                      ],
                    ),
                  ),

                  // Multi-Pass Scanning Laser Sweep Bar
                  if (!_isScanned)
                    AnimatedBuilder(
                      animation: _scanLineAnimation,
                      builder: (context, child) {
                        return Positioned(
                          top: 75 + (_scanLineAnimation.value * 52),
                          child: Container(
                            width: 125,
                            height: 3,
                            decoration: BoxDecoration(
                              color: gold,
                              borderRadius: BorderRadius.circular(2),
                              boxShadow: [
                                BoxShadow(
                                  color: gold.withValues(alpha: 0.95),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                  // Success Checkmark Badge Overlay
                  if (_isScanned)
                    ScaleTransition(
                      scale: _checkScaleAnimation,
                      child: Container(
                        width: 54,
                        height: 54,
                        decoration: const BoxDecoration(
                          color: emerald,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 36),

              const Text(
                'CABIEBIES Attendance System',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                _isScanned ? 'Identity Verified' : 'Scanning face biometrics...',
                style: TextStyle(
                  color: _isScanned ? emerald : Colors.white.withValues(alpha: 0.7),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const Spacer(),

              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Text(
                  'Powered by Red Horse Empe + Coke Technology',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// HUD Facial Corner Bracket Frame Painter
class _HUDFaceFramePainter extends CustomPainter {
  final Color color;

  _HUDFaceFramePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const len = 18.0;
    const r = 8.0;

    // Top-Left Corner
    final pathTL = Path()
      ..moveTo(0, len)
      ..lineTo(0, r)
      ..quadraticBezierTo(0, 0, r, 0)
      ..lineTo(len, 0);
    canvas.drawPath(pathTL, paint);

    // Top-Right Corner
    final pathTR = Path()
      ..moveTo(size.width - len, 0)
      ..lineTo(size.width - r, 0)
      ..quadraticBezierTo(size.width, 0, size.width, r)
      ..lineTo(size.width, len);
    canvas.drawPath(pathTR, paint);

    // Bottom-Left Corner
    final pathBL = Path()
      ..moveTo(0, size.height - len)
      ..lineTo(0, size.height - r)
      ..quadraticBezierTo(0, size.height, r, size.height)
      ..lineTo(len, size.height);
    canvas.drawPath(pathBL, paint);

    // Bottom-Right Corner
    final pathBR = Path()
      ..moveTo(size.width - len, size.height)
      ..lineTo(size.width - r, size.height)
      ..quadraticBezierTo(size.width, size.height, size.width, size.height - r)
      ..lineTo(size.width, size.height - len);
    canvas.drawPath(pathBR, paint);
  }

  @override
  bool shouldRepaint(covariant _HUDFaceFramePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}