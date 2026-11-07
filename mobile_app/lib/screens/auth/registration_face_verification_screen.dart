import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../models/liveness_challenge.dart';
import '../../services/registration_service.dart';
import '../home/home_screen.dart';

enum RegistrationLivenessStep { lookCenter, turn, verifying, passed, failed }

class RegistrationFaceVerificationScreen extends StatefulWidget {
  const RegistrationFaceVerificationScreen({
    super.key,
    this.studentName,
  });

  final String? studentName;

  @override
  State<RegistrationFaceVerificationScreen> createState() =>
      _RegistrationFaceVerificationScreenState();
}

class _RegistrationFaceVerificationScreenState
    extends State<RegistrationFaceVerificationScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _camera;
  bool _cameraReady = false;
  bool _disposed = false;
  bool _isProcessing = false;

  RegistrationLivenessStep _step = RegistrationLivenessStep.lookCenter;

  LivenessChallenge? _challenge;
  String _direction = 'left';

  double _holdProgress = 0.0;
  double _turnProgress = 0.0;

  String? _hint;
  String? _error;

  Color _overlayFlashColor = Colors.transparent;
  final List<XFile> _flashFrames = [];
  final List<String> _flashColors = [];

  final List<Color> _flashColorSequence = [
    Colors.red,
    Colors.green,
    Colors.blue,
  ];
  final List<String> _flashColorNames = ['red', 'green', 'blue'];

  XFile? _centerFrame;
  XFile? _turnedFrame;

  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _initLivenessChallengeAndCamera();
  }

  Future<void> _initLivenessChallengeAndCamera() async {
    final challengeResult =
        await RegistrationService.instance.requestLivenessChallenge();

    if (!mounted || _disposed) return;

    if (challengeResult.success && challengeResult.challenge != null) {
      _challenge = challengeResult.challenge;
      _direction = _challenge!.direction;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw Exception('No camera available.');
      }

      final selected = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        selected,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();

      if (!mounted || _disposed) {
        await controller.dispose();
        return;
      }

      setState(() {
        _camera = controller;
        _cameraReady = true;
      });

      await _showInstructionModal();
    } catch (e) {
      if (mounted) {
        setState(() {
          _step = RegistrationLivenessStep.failed;
          _error = 'Unable to start camera for face biometrics.';
        });
      }
    }
  }

  Future<void> _showInstructionModal() async {
    if (!mounted || _disposed) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFEF3C7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.security_rounded,
                    color: Color(0xFFD97706),
                    size: 32,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Anti-Spoofing Verification',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'To block photo or pre-recorded video spoofing, your screen will flash RED, GREEN, and BLUE light continuously while capturing your face during center and turned poses.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.black87,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Color(0xFFD97706),
                        size: 22,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Warning: Screen light will flash rapidly. Keep phone steady at eye level.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF92400E),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'I Understand',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (mounted && !_disposed) {
      await _runAutomatedCapture();
    }
  }

  Future<void> _runAutomatedCapture() async {
    if (_isProcessing ||
        _camera == null ||
        !_camera!.value.isInitialized ||
        _disposed) {
      return;
    }

    _isProcessing = true;
    _flashFrames.clear();
    _flashColors.clear();

    try {
      // ----------------------------------------------------------------------
      // PHASE 1: CENTER POSE WITH CONTINUOUS FLASHING
      // ----------------------------------------------------------------------
      setState(() {
        _step = RegistrationLivenessStep.lookCenter;
        _holdProgress = 0.1;
        _hint = 'Look straight. Screen is verifying light reflections...';
      });

      for (int i = 0; i < _flashColorSequence.length; i++) {
        if (!mounted || _disposed) return;

        setState(() {
          _overlayFlashColor = _flashColorSequence[i];
        });

        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted || _disposed) return;

        final frame = await _camera!.takePicture();
        _flashFrames.add(frame);
        _flashColors.add(_flashColorNames[i]);

        setState(() {
          _holdProgress = 0.1 + (0.4 * ((i + 1) / _flashColorSequence.length));
        });
      }

      _centerFrame = await _camera!.takePicture();
      setState(() {
        _holdProgress = 1.0;
      });

      // ----------------------------------------------------------------------
      // PHASE 2: HEAD TURN POSE WITH CONTINUED FLASHING
      // ----------------------------------------------------------------------
      setState(() {
        _step = RegistrationLivenessStep.turn;
        _turnProgress = 0.1;
        _hint = 'Turn your head to your $_direction while screen flashes...';
      });

      for (int i = 0; i < _flashColorSequence.length; i++) {
        if (!mounted || _disposed) return;

        setState(() {
          _overlayFlashColor = _flashColorSequence[i];
        });

        await Future.delayed(const Duration(milliseconds: 350));
        if (!mounted || _disposed) return;

        final frame = await _camera!.takePicture();
        _flashFrames.add(frame);
        _flashColors.add(_flashColorNames[i]);

        setState(() {
          _turnProgress = 0.1 + (0.8 * ((i + 1) / _flashColorSequence.length));
        });
      }

      _turnedFrame = await _camera!.takePicture();

      setState(() {
        _overlayFlashColor = Colors.transparent;
        _turnProgress = 1.0;
      });

      await _submitBiometrics();
    } catch (e) {
      debugPrint('Registration capture error: $e');
      if (mounted && !_disposed) {
        setState(() {
          _step = RegistrationLivenessStep.failed;
          _overlayFlashColor = Colors.transparent;
          _error = 'Camera capture failed. Please retry.';
        });
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _submitBiometrics() async {
    setState(() {
      _step = RegistrationLivenessStep.verifying;
      _hint = 'Registering face biometrics...';
      _error = null;
    });

    try {
      if (_centerFrame != null && _turnedFrame != null) {
        final nonce = _challenge?.nonce ?? 'fallback_nonce';
        final sessionId = _challenge?.sessionId ?? 'fallback_session_id';

        final result =
            await RegistrationService.instance.verifyRegistrationFace(
          centerFrame: _centerFrame!,
          turnedFrame: _turnedFrame!,
          flashFrames: _flashFrames,
          flashColors: _flashColors,
          challengeNonce: nonce,
          sessionId: sessionId,
        );

        if (!result.success) {
          final msg = result.message.toLowerCase();
          if (msg.contains('turn') ||
              msg.contains('angle') ||
              msg.contains('liveness')) {
            setState(() {
              _hint = 'Retrying angle adjustment...';
            });
            await Future.delayed(const Duration(milliseconds: 800));
            if (mounted && !_disposed) {
              await _runAutomatedCapture();
            }
            return;
          }
          throw Exception(result.message);
        }
      }

      if (!mounted || _disposed) return;

      setState(() {
        _step = RegistrationLivenessStep.passed;
      });

      await _showSuccessModalAndNavigate();
    } catch (e) {
      if (!mounted || _disposed) return;
      setState(() {
        _step = RegistrationLivenessStep.failed;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _showSuccessModalAndNavigate() async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final nameText =
            widget.studentName != null && widget.studentName!.isNotEmpty
                ? widget.studentName!
                : 'Student';

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 16,
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: Color(0xFFDCFCE7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF16A34A),
                    size: 40,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Registration Complete!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Welcome, $nameText! Your account and face biometrics are active.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Go to Home Page',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const HomeScreen(),
      ),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _disposed = true;
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _overlayFlashColor != Colors.transparent
          ? _overlayFlashColor
          : AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        title: const Text(
          'Register Face Biometrics',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            const Text(
              'Face Registration',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _hint ?? 'Position your face inside the circle',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const Spacer(),
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Container(
                        width: 270,
                        height: 270,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.gold.withValues(
                              alpha: 0.3 + (_pulseController.value * 0.4),
                            ),
                            width: 3.5,
                          ),
                        ),
                      );
                    },
                  ),
                  Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black,
                      border: Border.all(color: AppColors.gold, width: 4),
                    ),
                    child: ClipOval(
                      child: _cameraReady &&
                              _camera != null &&
                              _camera!.value.isInitialized
                          ? LayoutBuilder(
                              builder: (context, constraints) {
                                final previewRatio = _camera!.value.aspectRatio;
                                return SizedBox(
                                  width: constraints.maxWidth,
                                  height: constraints.maxHeight,
                                  child: ClipRect(
                                    child: OverflowBox(
                                      alignment: Alignment.center,
                                      child: FittedBox(
                                        fit: BoxFit.cover,
                                        child: SizedBox(
                                          width: constraints.maxWidth,
                                          height: constraints.maxWidth *
                                              previewRatio,
                                          child: CameraPreview(_camera!),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            )
                          : const Center(
                              child: CircularProgressIndicator(
                                color: AppColors.gold,
                              ),
                            ),
                    ),
                  ),
                  if (_step == RegistrationLivenessStep.turn)
                    Positioned(
                      left: _direction == 'left' ? 16 : null,
                      right: _direction == 'right' ? 16 : null,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.navy.withValues(alpha: 0.85),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.gold, width: 2),
                        ),
                        child: Icon(
                          _direction == 'left'
                              ? Icons.arrow_back
                              : Icons.arrow_forward,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _buildInstructionBadge(),
            const Spacer(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            _buildProgressBar(),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isProcessing
                  ? null
                  : () {
                      setState(() {
                        _isProcessing = false;
                        _error = null;
                      });
                      _runAutomatedCapture();
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.navy,
                padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: const Text(
                'Retry / Capture Now',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionBadge() {
    String text;
    IconData icon;
    bool spin = false;

    switch (_step) {
      case RegistrationLivenessStep.lookCenter:
        text = 'Look straight at the camera';
        icon = Icons.remove_red_eye_outlined;
        break;
      case RegistrationLivenessStep.turn:
        text = 'Turn your head clearly to your $_direction';
        icon = _direction == 'left' ? Icons.arrow_back : Icons.arrow_forward;
        break;
      case RegistrationLivenessStep.verifying:
        text = 'Registering face biometrics...';
        icon = Icons.refresh;
        spin = true;
        break;
      case RegistrationLivenessStep.passed:
        text = 'Verified & Registered!';
        icon = Icons.check_circle_outline;
        break;
      case RegistrationLivenessStep.failed:
        text = 'Verification failed';
        icon = Icons.error_outline;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          spin
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.navy,
                  ),
                )
              : Icon(icon, color: AppColors.navy, size: 20),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    double progress = _step == RegistrationLivenessStep.lookCenter
        ? _holdProgress
        : _turnProgress;
    return SizedBox(
      width: 180,
      height: 6,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: progress,
          backgroundColor: Colors.grey.shade300,
          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.navy),
        ),
      ),
    );
  }
}