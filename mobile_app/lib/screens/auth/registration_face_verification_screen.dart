import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../services/registration_service.dart';
import 'auth_gate.dart';

enum _ChallengeStep {
  preparing,
  center,
  blink,
  turn,
  smile,
  returnCenter,
  verifying,
  failed,
}

class RegistrationFaceVerificationScreen extends StatefulWidget {
  const RegistrationFaceVerificationScreen({super.key});

  @override
  State<RegistrationFaceVerificationScreen> createState() =>
      _RegistrationFaceVerificationScreenState();
}

class _RegistrationFaceVerificationScreenState
    extends State<RegistrationFaceVerificationScreen> {
  static const Color navy = Color(0xFF080878);

  static const Color gold = Color(0xFFFFC800);

  /*
   * Match Python constants.
   */

  static const double centerYawLimit = 0.08;

  static const double turnYawDelta = 0.06;

  static const double returnYawDelta = 0.06;

  static const double blinkRatio = 0.72;

  static const double smileRatio = 1.04;

  /*
   * We intentionally do NOT call Laravel
   * dozens of times every second.
   */

  static const Duration captureInterval = Duration(milliseconds: 800);

  CameraController? _camera;

  bool _initializing = true;

  bool _running = false;

  bool _analyzing = false;

  bool _disposed = false;

  String? _error;

  _ChallengeStep _step = _ChallengeStep.preparing;

  XFile? _centerFrame;
  XFile? _blinkFrame;
  XFile? _turnedFrame;
  XFile? _smileFrame;
  XFile? _returnedFrame;

  /*
   * Baseline values from the accepted
   * CENTER frame.
   */

  double? _centerYaw;
  double? _centerEyeOpenness;
  double? _centerMouthWidth;

  int _badFrames = 0;

  @override
  void initState() {
    super.initState();

    _initializeCamera();
  }

  // ===========================================================================
  // CAMERA
  // ===========================================================================

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        throw StateError('No camera is available.');
      }

      CameraDescription selected = cameras.first;

      for (final camera in cameras) {
        if (camera.lensDirection == CameraLensDirection.front) {
          selected = camera;

          break;
        }
      }

      final controller = CameraController(
        selected,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();

      if (!mounted || _disposed) {
        await controller.dispose();

        return;
      }

      _camera = controller;

      setState(() {
        _initializing = false;

        _error = null;

        _step = _ChallengeStep.preparing;
      });

      /*
       * Give the student two seconds
       * to position their face.
       */

      await Future<void>.delayed(const Duration(seconds: 2));

      if (!mounted || _disposed) {
        return;
      }

      await _startChallenge();
    } on CameraException catch (e) {
      if (!mounted || _disposed) {
        return;
      }

      setState(() {
        _initializing = false;

        _error = e.code == 'CameraAccessDenied'
            ? 'Camera permission was denied. Allow camera access and try again.'
            : 'Unable to start camera: ${e.description ?? e.code}';
      });
    } catch (e) {
      if (!mounted || _disposed) {
        return;
      }

      setState(() {
        _initializing = false;

        _error = 'Unable to start the camera.';
      });
    }
  }

  // ===========================================================================
  // START / RESET
  // ===========================================================================

  Future<void> _startChallenge() async {
    final controller = _camera;

    if (_running || controller == null || !controller.value.isInitialized) {
      return;
    }

    _resetChallenge();

    setState(() {
      _running = true;

      _error = null;

      _step = _ChallengeStep.center;
    });

    while (mounted &&
        !_disposed &&
        _running &&
        _step != _ChallengeStep.verifying &&
        _step != _ChallengeStep.failed) {
      await _captureAndAnalyze();

      await Future<void>.delayed(captureInterval);
    }
  }

  void _resetChallenge() {
    _centerFrame = null;

    _blinkFrame = null;

    _turnedFrame = null;

    _smileFrame = null;

    _returnedFrame = null;

    _centerYaw = null;

    _centerEyeOpenness = null;

    _centerMouthWidth = null;

    _badFrames = 0;
  }

  // ===========================================================================
  // CAPTURE + LARAVEL ANALYSIS
  // ===========================================================================

  Future<void> _captureAndAnalyze() async {
    if (_analyzing || !_running || _disposed) {
      return;
    }

    final controller = _camera;

    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture) {
      return;
    }

    _analyzing = true;

    try {
      final frame = await controller.takePicture();

      if (!mounted || _disposed || !_running) {
        return;
      }

      final result = await RegistrationService.instance.analyzeLivenessFrame(
        frame: frame,
      );

      if (!mounted || _disposed || !_running) {
        return;
      }

      /*
       * Python rejects frames with no face,
       * multiple faces, severe blur, etc.
       */

      if (!result.success || !result.faceDetected) {
        _badFrames++;

        if (_badFrames >= 4) {
          setState(() {
            _error = result.message;
          });
        }

        return;
      }

      final yaw = result.yaw;

      final eye = result.eyeOpenness;

      final mouth = result.mouthWidth;

      if (yaw == null || eye == null || mouth == null) {
        setState(() {
          _error = 'Biometric service returned incomplete facial measurements.';
        });

        return;
      }

      _badFrames = 0;

      if (_error != null) {
        setState(() {
          _error = null;
        });
      }

      await _processMeasurement(
        frame: frame,
        yaw: yaw,
        eyeOpenness: eye,
        mouthWidth: mouth,
      );
    } on CameraException catch (e) {
      if (!mounted || _disposed) {
        return;
      }

      setState(() {
        _error = 'Camera capture failed: ${e.description ?? e.code}';
      });
    } catch (e) {
      if (!mounted || _disposed) {
        return;
      }

      setState(() {
        _error = 'Unable to analyze the camera frame.';
      });
    } finally {
      _analyzing = false;
    }
  }

  // ===========================================================================
  // CHALLENGE LOGIC
  // ===========================================================================

  Future<void> _processMeasurement({
    required XFile frame,
    required double yaw,
    required double eyeOpenness,
    required double mouthWidth,
  }) async {
    switch (_step) {
      /*
       * --------------------------------------------------------
       * CENTER
       * --------------------------------------------------------
       *
       * Python:
       * abs(center.yaw) <= 0.08
       */

      case _ChallengeStep.center:
        if (yaw.abs() <= centerYawLimit) {
          _centerFrame = frame;

          _centerYaw = yaw;

          _centerEyeOpenness = eyeOpenness;

          _centerMouthWidth = mouthWidth;

          setState(() {
            _step = _ChallengeStep.blink;
          });
        }

        break;

      /*
       * --------------------------------------------------------
       * BLINK
       * --------------------------------------------------------
       *
       * Python:
       *
       * blinkEye <= centerEye * 0.72
       */

      case _ChallengeStep.blink:
        final baseline = _centerEyeOpenness;

        if (baseline == null) {
          _fail('Center measurements were lost. Please try again.');

          return;
        }

        final required = baseline * blinkRatio;

        if (eyeOpenness <= required) {
          _blinkFrame = frame;

          setState(() {
            _step = _ChallengeStep.turn;
          });
        }

        break;

      /*
       * --------------------------------------------------------
       * HEAD TURN
       * --------------------------------------------------------
       *
       * Python:
       *
       * abs(turnYaw - centerYaw) >= 0.06
       */

      case _ChallengeStep.turn:
        final baseline = _centerYaw;

        if (baseline == null) {
          _fail('Center measurements were lost. Please try again.');

          return;
        }

        final delta = (yaw - baseline).abs();

        if (delta >= turnYawDelta) {
          _turnedFrame = frame;

          setState(() {
            _step = _ChallengeStep.smile;
          });
        }

        break;

      /*
       * --------------------------------------------------------
       * SMILE
       * --------------------------------------------------------
       *
       * Python:
       *
       * smileMouth >= centerMouth * 1.04
       */

      case _ChallengeStep.smile:
        final baseline = _centerMouthWidth;

        if (baseline == null) {
          _fail('Center measurements were lost. Please try again.');

          return;
        }

        final required = baseline * smileRatio;

        if (mouthWidth >= required) {
          _smileFrame = frame;

          setState(() {
            _step = _ChallengeStep.returnCenter;
          });
        }

        break;

      /*
       * --------------------------------------------------------
       * RETURN TO CENTER
       * --------------------------------------------------------
       */

      case _ChallengeStep.returnCenter:
        final original = _centerYaw;

        if (original == null) {
          _fail('Center measurements were lost. Please try again.');

          return;
        }

        final centered = yaw.abs() <= centerYawLimit;

        final returned = (yaw - original).abs() <= returnYawDelta;

        if (centered && returned) {
          _returnedFrame = frame;

          await _verifyFinalFrames();
        }

        break;

      case _ChallengeStep.preparing:
      case _ChallengeStep.verifying:
      case _ChallengeStep.failed:
        break;
    }
  }

  // ===========================================================================
  // FINAL VERIFY
  // ===========================================================================

  Future<void> _verifyFinalFrames() async {
    if (_centerFrame == null ||
        _blinkFrame == null ||
        _turnedFrame == null ||
        _smileFrame == null ||
        _returnedFrame == null) {
      _fail('Some biometric frames were not captured. Please try again.');

      return;
    }

    setState(() {
      _running = false;

      _step = _ChallengeStep.verifying;

      _error = null;
    });

    final result = await RegistrationService.instance.verifyRegistrationFace(
      centerFrame: _centerFrame!,

      blinkFrame: _blinkFrame!,

      turnedFrame: _turnedFrame!,

      smileFrame: _smileFrame!,

      returnedFrame: _returnedFrame!,
    );

    if (!mounted || _disposed) {
      return;
    }

    if (!result.success) {
      _fail(result.message);

      return;
    }

    await _showSuccess();
  }

  // ===========================================================================
  // SUCCESS
  // ===========================================================================

  Future<void> _showSuccess() async {
    await showDialog<void>(
      context: context,

      barrierDismissible: false,

      builder: (BuildContext dialogContext) {
        return AlertDialog(
          icon: const Icon(
            Icons.verified_user_rounded,
            size: 48,
            color: Colors.green,
          ),

          title: const Text('Identity Verified', textAlign: TextAlign.center),

          content: const Text(
            'Liveness and facial identity verification completed successfully.',
            textAlign: TextAlign.center,
          ),

          actionsAlignment: MainAxisAlignment.center,

          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              style: FilledButton.styleFrom(backgroundColor: navy),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );

    if (!mounted || _disposed) {
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (_) => false,
    );
  }

  // ===========================================================================
  // FAILURE / RETRY
  // ===========================================================================

  void _fail(String message) {
    if (!mounted || _disposed) {
      return;
    }

    setState(() {
      _running = false;

      _step = _ChallengeStep.failed;

      _error = message;
    });
  }

  Future<void> _retry() async {
    if (_running || _analyzing) {
      return;
    }

    _resetChallenge();

    setState(() {
      _error = null;

      _step = _ChallengeStep.preparing;
    });

    await Future<void>.delayed(const Duration(seconds: 1));

    if (!mounted || _disposed) {
      return;
    }

    await _startChallenge();
  }

  // ===========================================================================
  // UI STRINGS
  // ===========================================================================

  String get _instruction {
    switch (_step) {
      case _ChallengeStep.preparing:
        return 'Position your face inside the guide';

      case _ChallengeStep.center:
        return 'Look directly at the camera';

      case _ChallengeStep.blink:
        return 'Blink both eyes naturally';

      case _ChallengeStep.turn:
        return 'Turn your head left or right';

      case _ChallengeStep.smile:
        return 'Smile clearly';

      case _ChallengeStep.returnCenter:
        return 'Look directly at the camera again';

      case _ChallengeStep.verifying:
        return 'Verifying your identity...';

      case _ChallengeStep.failed:
        return 'Verification needs to be repeated';
    }
  }

  String get _subtitle {
    switch (_step) {
      case _ChallengeStep.preparing:
        return 'Preparing camera';

      case _ChallengeStep.center:
        return 'Step 1 of 5';

      case _ChallengeStep.blink:
        return 'Step 2 of 5';

      case _ChallengeStep.turn:
        return 'Step 3 of 5';

      case _ChallengeStep.smile:
        return 'Step 4 of 5';

      case _ChallengeStep.returnCenter:
        return 'Step 5 of 5';

      case _ChallengeStep.verifying:
        return 'MediaPipe + OpenCV + InsightFace';

      case _ChallengeStep.failed:
        return 'Please try again';
    }
  }

  int get _activeIndex {
    switch (_step) {
      case _ChallengeStep.preparing:
      case _ChallengeStep.center:
        return 0;

      case _ChallengeStep.blink:
        return 1;

      case _ChallengeStep.turn:
        return 2;

      case _ChallengeStep.smile:
        return 3;

      case _ChallengeStep.returnCenter:
        return 4;

      case _ChallengeStep.verifying:
        return 5;

      case _ChallengeStep.failed:
        return -1;
    }
  }

  IconData get _stepIcon {
    switch (_step) {
      case _ChallengeStep.preparing:
      case _ChallengeStep.center:
      case _ChallengeStep.returnCenter:
        return Icons.face_retouching_natural_rounded;

      case _ChallengeStep.blink:
        return Icons.visibility_off_rounded;

      case _ChallengeStep.turn:
        return Icons.sync_alt_rounded;

      case _ChallengeStep.smile:
        return Icons.sentiment_very_satisfied_rounded;

      case _ChallengeStep.verifying:
        return Icons.verified_user_rounded;

      case _ChallengeStep.failed:
        return Icons.error_outline_rounded;
    }
  }

  // ===========================================================================
  // DISPOSE
  // ===========================================================================

  @override
  void dispose() {
    _disposed = true;

    _running = false;

    _camera?.dispose();

    _camera = null;

    super.dispose();
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_running,

      child: Scaffold(
        backgroundColor: const Color(0xFFF7F7FB),

        appBar: AppBar(
          backgroundColor: Colors.white,

          foregroundColor: navy,

          elevation: 0,

          title: const Text(
            'Live Face Verification',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),

        body: SafeArea(
          child: _initializing
              ? const Center(child: CircularProgressIndicator())
              : _camera == null
              ? _fatalError()
              : _challenge(),
        ),
      ),
    );
  }

  Widget _fatalError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,

          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 56,
              color: Colors.red,
            ),

            const SizedBox(height: 16),

            Text(_error ?? 'Camera unavailable.', textAlign: TextAlign.center),

            const SizedBox(height: 20),

            FilledButton(
              onPressed: _initializeCamera,
              style: FilledButton.styleFrom(backgroundColor: navy),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _challenge() {
    final controller = _camera!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),

      child: Column(
        children: [
          const Text(
            'Biometric Registration',
            style: TextStyle(
              color: navy,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            _subtitle,
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),

          const SizedBox(height: 18),

          Expanded(
            child: Center(
              child: Container(
                constraints: const BoxConstraints(
                  maxWidth: 310,
                  maxHeight: 390,
                ),

                clipBehavior: Clip.antiAlias,

                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(160),

                  border: Border.all(
                    color: _step == _ChallengeStep.verifying
                        ? Colors.green
                        : gold,
                    width: 4,
                  ),

                  color: Colors.black,
                ),

                child: Stack(
                  fit: StackFit.expand,

                  children: [
                    Transform.scale(
                      scaleX: -1,
                      child: CameraPreview(controller),
                    ),

                    if (_step == _ChallengeStep.verifying)
                      Container(
                        color: Colors.black.withValues(alpha: 0.35),
                        child: const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          Icon(
            _stepIcon,
            size: 30,
            color: _step == _ChallengeStep.failed ? Colors.red : navy,
          ),

          const SizedBox(height: 8),

          Text(
            _instruction,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: navy,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 10),

            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],

          const SizedBox(height: 18),

          Row(
            children: [
              _progress('Center', 0),
              _progress('Blink', 1),
              _progress('Turn', 2),
              _progress('Smile', 3),
              _progress('Center', 4),
            ],
          ),

          if (_step == _ChallengeStep.failed) ...[
            const SizedBox(height: 18),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _retry,

                icon: const Icon(Icons.refresh_rounded),

                style: FilledButton.styleFrom(
                  backgroundColor: navy,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),

                label: const Text('Try Again'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _progress(String label, int index) {
    final active = index == _activeIndex;

    final completed = _activeIndex > index;

    return Expanded(
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),

            width: 25,

            height: 25,

            alignment: Alignment.center,

            decoration: BoxDecoration(
              shape: BoxShape.circle,

              color: completed
                  ? Colors.green
                  : active
                  ? gold
                  : Colors.grey.shade300,
            ),

            child: completed
                ? const Icon(Icons.check, size: 15, color: Colors.white)
                : Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: navy,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),

          const SizedBox(height: 5),

          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 9),
          ),
        ],
      ),
    );
  }
}
