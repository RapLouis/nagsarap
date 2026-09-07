import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../services/registration_service.dart';
import '../../widgets/app_dialog.dart';
import 'auth_gate.dart';

enum _LivenessStep {
  detect,
  center,
  blink,
  turn,
  smile,
  returnCenter,
  verifying,
}

class RegistrationFaceVerificationScreen extends StatefulWidget {
  const RegistrationFaceVerificationScreen({super.key});

  @override
  State<RegistrationFaceVerificationScreen> createState() =>
      _RegistrationFaceVerificationScreenState();
}

class _RegistrationFaceVerificationScreenState
    extends State<RegistrationFaceVerificationScreen> {
  CameraController? _cameraController;

  Timer? _scanTimer;

  bool _initializing = true;
  bool _processingFrame = false;
  bool _finished = false;

  String? _cameraError;

  _LivenessStep _step = _LivenessStep.detect;

  /*
  |--------------------------------------------------------------------------
  | CAPTURED VALID FRAMES
  |--------------------------------------------------------------------------
  */

  XFile? _centerFrame;
  XFile? _blinkFrame;
  XFile? _turnedFrame;
  XFile? _smileFrame;
  XFile? _returnedFrame;

  /*
  |--------------------------------------------------------------------------
  | BLINK STATE
  |--------------------------------------------------------------------------
  |
  | Same idea as the web implementation:
  |
  | eye closes
  |      ↓
  | eye opens
  |      ↓
  | blink completed
  |
  */

  bool _blinkClosed = false;

  /*
  |--------------------------------------------------------------------------
  | STABILITY
  |--------------------------------------------------------------------------
  |
  | Require the condition to appear in more than one server result
  | so one noisy frame does not advance the challenge.
  |
  */

  int _stableMatches = 0;

  static const int requiredStableMatches = 2;

  @override
  void initState() {
    super.initState();

    _initializeCamera();
  }

  /*
  |--------------------------------------------------------------------------
  | CAMERA
  |--------------------------------------------------------------------------
  */

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        throw Exception('No camera available.');
      }

      CameraDescription frontCamera = cameras.first;

      for (final camera in cameras) {
        if (camera.lensDirection == CameraLensDirection.front) {
          frontCamera = camera;

          break;
        }
      }

      final controller = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();

        return;
      }

      setState(() {
        _cameraController = controller;

        _initializing = false;
      });

      _startAutomaticScanning();
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _initializing = false;

        _cameraError = 'Unable to open the front camera. Allow camera access and try again.';
      });
    }
  }

  /*
  |--------------------------------------------------------------------------
  | AUTOMATIC SCANNING
  |--------------------------------------------------------------------------
  |
  | No Capture buttons.
  |
  | Every ~700 ms:
  |
  | camera
  |   ↓
  | Laravel
  |   ↓
  | FaceService
  |   ↓
  | MediaPipe/OpenCV
  |   ↓
  | metrics returned
  |
  */

  void _startAutomaticScanning() {
    _scanTimer?.cancel();

    _scanTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      _processAutomaticFrame();
    });
  }

  Future<void> _processAutomaticFrame() async {
    if (_processingFrame || _finished || _step == _LivenessStep.verifying) {
      return;
    }

    final controller = _cameraController;

    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture) {
      return;
    }

    _processingFrame = true;

    try {
      final frame = await controller.takePicture();

      final metrics = await RegistrationService.instance.analyzeLivenessFrame(
        frame: frame,
      );

      if (!mounted) {
        return;
      }

      if (metrics == null) {
        _stableMatches = 0;

        if (_step == _LivenessStep.detect) {
          return;
        }

        return;
      }

      await _handleMetrics(frame, metrics);
    } catch (e) {
      debugPrint('Automatic liveness frame error: $e');
    } finally {
      _processingFrame = false;
    }
  }

  /*
  |--------------------------------------------------------------------------
  | AUTOMATIC LIVENESS STATE MACHINE
  |--------------------------------------------------------------------------
  |
  | Mirrors the existing Laravel web flow:
  |
  | DETECT
  | CENTER
  | BLINK
  | TURN
  | SMILE
  | RETURN
  |
  */

  Future<void> _handleMetrics(XFile frame, Map<String, dynamic> metrics) async {
    final bool faceDetected =
        metrics['face_detected'] == true || metrics['success'] == true;

    if (!faceDetected) {
      _stableMatches = 0;

      if (_step != _LivenessStep.detect) {
        setState(() {
          _step = _LivenessStep.detect;
        });
      }

      return;
    }

    final double yaw = _doubleValue(metrics['yaw']);

    final double eye = _doubleValue(metrics['eye_openness']);

    final double mouth = _doubleValue(metrics['mouth_width']);

    switch (_step) {
      /*
      |--------------------------------------------------------------------------
      | DETECT
      |--------------------------------------------------------------------------
      */

      case _LivenessStep.detect:
        setState(() {
          _step = _LivenessStep.center;
        });

        _stableMatches = 0;

        break;

      /*
      |--------------------------------------------------------------------------
      | CENTER
      |--------------------------------------------------------------------------
      |
      | Web:
      |
      | Math.abs(yaw) < 0.15
      |
      */

      case _LivenessStep.center:
        if (yaw.abs() < 0.15 && eye > 0.20) {
          _stableMatches++;

          if (_stableMatches >= requiredStableMatches) {
            _centerFrame = frame;

            _stableMatches = 0;

            setState(() {
              _step = _LivenessStep.blink;
            });
          }
        } else {
          _stableMatches = 0;
        }

        break;

      /*
      |--------------------------------------------------------------------------
      | BLINK
      |--------------------------------------------------------------------------
      |
      | Same web logic:
      |
      | closed < 0.18
      | opened >= 0.22
      |
      */

      case _LivenessStep.blink:
        if (eye < 0.18) {
          _blinkClosed = true;

          _blinkFrame = frame;

          setState(() {});
        } else if (_blinkClosed && eye >= 0.22) {
          _blinkClosed = false;

          _stableMatches = 0;

          setState(() {
            _step = _LivenessStep.turn;
          });
        }

        break;

      /*
      |--------------------------------------------------------------------------
      | TURN
      |--------------------------------------------------------------------------
      |
      | Same web threshold:
      |
      | Math.abs(yaw) > 0.30
      |
      */

      case _LivenessStep.turn:
        if (yaw.abs() > 0.30) {
          _stableMatches++;

          if (_stableMatches >= requiredStableMatches) {
            _turnedFrame = frame;

            _stableMatches = 0;

            setState(() {
              _step = _LivenessStep.smile;
            });
          }
        } else {
          _stableMatches = 0;
        }

        break;

      /*
      |--------------------------------------------------------------------------
      | SMILE
      |--------------------------------------------------------------------------
      |
      | Existing web flow uses mouth ratio > 0.35.
      |
      */

      case _LivenessStep.smile:
        if (mouth > 0.35) {
          _stableMatches++;

          if (_stableMatches >= requiredStableMatches) {
            _smileFrame = frame;

            _stableMatches = 0;

            setState(() {
              _step = _LivenessStep.returnCenter;
            });
          }
        } else {
          _stableMatches = 0;
        }

        break;

      /*
      |--------------------------------------------------------------------------
      | RETURN CENTER
      |--------------------------------------------------------------------------
      */

      case _LivenessStep.returnCenter:
        if (yaw.abs() < 0.15 && eye > 0.20) {
          _stableMatches++;

          if (_stableMatches >= requiredStableMatches) {
            _returnedFrame = frame;

            _stableMatches = 0;

            await _submitVerification();
          }
        } else {
          _stableMatches = 0;
        }

        break;

      case _LivenessStep.verifying:
        break;
    }
  }

  /*
  |--------------------------------------------------------------------------
  | FINAL SERVER VERIFICATION
  |--------------------------------------------------------------------------
  |
  | This happens AUTOMATICALLY.
  |
  | No "Verify My Face" button.
  |
  */

  Future<void> _submitVerification() async {
    if (_finished) {
      return;
    }

    if (_centerFrame == null ||
        _blinkFrame == null ||
        _turnedFrame == null ||
        _smileFrame == null ||
        _returnedFrame == null) {
      _restartChallenge();

      return;
    }

    _finished = true;

    _scanTimer?.cancel();

    setState(() {
      _step = _LivenessStep.verifying;
    });

    final result = await RegistrationService.instance.verifyRegistrationFace(
      centerFrame: _centerFrame!,
      blinkFrame: _blinkFrame!,
      turnedFrame: _turnedFrame!,
      smileFrame: _smileFrame!,
      returnedFrame: _returnedFrame!,
    );

    if (!mounted) {
      return;
    }

    if (!result.success) {
      _finished = false;

      await _showFailure(result.message);

      if (mounted) {
        _restartChallenge();
      }

      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AppDialog(
          type: AppDialogType.success,
          title: 'Identity Verified',
          message: 'Liveness and face verification completed successfully.',
          primaryText: 'Continue',
          primaryAction: () {
            Navigator.of(dialogContext).pop();
          },
        );
      },
    );

    if (!mounted) {
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (_) => false,
    );
  }

  /*
  |--------------------------------------------------------------------------
  | RESTART
  |--------------------------------------------------------------------------
  */

  void _restartChallenge() {
    _scanTimer?.cancel();

    _centerFrame = null;
    _blinkFrame = null;
    _turnedFrame = null;
    _smileFrame = null;
    _returnedFrame = null;

    _blinkClosed = false;
    _stableMatches = 0;
    _finished = false;

    if (mounted) {
      setState(() {
        _step = _LivenessStep.detect;
      });

      _startAutomaticScanning();
    }
  }

  /*
  |--------------------------------------------------------------------------
  | HELPERS
  |--------------------------------------------------------------------------
  */

  double _doubleValue(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  Future<void> _showFailure(String message) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AppDialog(
          type: AppDialogType.error,
          title: 'Liveness Failed',
          message: message,
          primaryText: 'Try Again',
          primaryAction: () {
            Navigator.of(dialogContext).pop();
          },
        );
      },
    );
  }

  String get _instruction {
    switch (_step) {
      case _LivenessStep.detect:
        return 'Position one face inside the guide';

      case _LivenessStep.center:
        return 'Look straight at the camera';

      case _LivenessStep.blink:
        return 'Blink once';

      case _LivenessStep.turn:
        return 'Turn your head left or right';

      case _LivenessStep.smile:
        return 'Smile';

      case _LivenessStep.returnCenter:
        return 'Look straight at the camera again';

      case _LivenessStep.verifying:
        return 'Verifying your identity...';
    }
  }

  int get _currentStep {
    switch (_step) {
      case _LivenessStep.detect:
        return 0;

      case _LivenessStep.center:
        return 0;

      case _LivenessStep.blink:
        return 1;

      case _LivenessStep.turn:
        return 2;

      case _LivenessStep.smile:
        return 3;

      case _LivenessStep.returnCenter:
        return 4;

      case _LivenessStep.verifying:
        return 5;
    }
  }

  Widget _progressItem(String text, int index) {
    final completed = index < _currentStep;

    final active = index == _currentStep;

    return Expanded(
      child: Column(
        children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: completed
                ? AppColors.success
                : active
                ? AppColors.gold
                : Colors.grey.shade300,
            child: completed
                ? const Icon(Icons.check, size: 13, color: Colors.white)
                : Text(
                    '${index + 1}',
                    style: const TextStyle(
                      fontSize: 9,
                      color: AppColors.navy,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
          const SizedBox(height: 4),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 8),
          ),
        ],
      ),
    );
  }

  /*
  |--------------------------------------------------------------------------
  | DISPOSE
  |--------------------------------------------------------------------------
  */

  @override
  void dispose() {
    _scanTimer?.cancel();

    _cameraController?.dispose();

    super.dispose();
  }

  /*
  |--------------------------------------------------------------------------
  | UI
  |--------------------------------------------------------------------------
  */

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step != _LivenessStep.verifying,
      child: Scaffold(
        appBar: AppBar(title: const Text('Live Face Verification')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              children: [
                const Text(
                  'Complete the liveness challenge',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                ),

                const SizedBox(height: 7),

                const Text(
                  'Follow the instructions. Detection and capture happen automatically.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),

                const SizedBox(height: 22),

                Expanded(child: Center(child: _cameraView())),

                const SizedBox(height: 18),

                if (_step == _LivenessStep.verifying)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: AppColors.navy,
                    ),
                  )
                else
                  const Icon(
                    Icons.face_retouching_natural_rounded,
                    color: AppColors.navy,
                    size: 26,
                  ),

                const SizedBox(height: 8),

                Text(
                  _instruction,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                  ),
                ),

                const SizedBox(height: 20),

                Row(
                  children: [
                    _progressItem('Center', 0),
                    _progressItem('Blink', 1),
                    _progressItem('Turn', 2),
                    _progressItem('Smile', 3),
                    _progressItem('Return', 4),
                  ],
                ),

                const SizedBox(height: 15),

                if (_step != _LivenessStep.verifying)
                  TextButton(
                    onPressed: _restartChallenge,
                    child: const Text('Restart Liveness Check'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cameraView() {
    if (_initializing) {
      return const CircularProgressIndicator(color: AppColors.navy);
    }

    if (_cameraError != null) {
      return Text(_cameraError!, textAlign: TextAlign.center);
    }

    final controller = _cameraController;

    if (controller == null || !controller.value.isInitialized) {
      return const Text('Camera unavailable.');
    }

    return Container(
      width: 285,
      height: 360,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(150),
        border: Border.all(color: AppColors.gold, width: 4),
      ),
      clipBehavior: Clip.antiAlias,
      child: Transform.scale(scaleX: -1, child: CameraPreview(controller)),
    );
  }
}
