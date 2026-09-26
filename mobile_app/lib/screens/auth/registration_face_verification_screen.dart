import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../services/registration_service.dart';
import 'auth_gate.dart';

enum _ChallengeStep { preparing, center, turn, returnCenter, verifying, failed }

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
  static const Color background = Color(0xFFF7F7FB);

  // Tolerant live guidance: the face can sit slightly off-center.
  // The final Laravel/Python verification remains authoritative.
  static const double centerYawLimit = 0.30;
  static const double turnYawDelta = 0.07;
  static const double returnYawDelta = 0.16;

  // Do not process every camera frame. Two consistent observations per
  // challenge step are enough to prevent noisy single-frame transitions.
  static const Duration captureInterval = Duration(milliseconds: 400);
  static const int stableFramesRequired = 2;
  static const int maxBadFramesBeforeMessage = 8;

  CameraController? _camera;

  bool _initializing = true;
  bool _running = false;
  bool _analyzing = false;
  bool _disposed = false;

  String? _challengeDirection;
  String? _challengeNonce;
  String? _challengeSessionId;

  String? _error;

  _ChallengeStep _step = _ChallengeStep.preparing;

  XFile? _centerFrame;
  XFile? _turnedFrame;
  XFile? _returnedFrame;

  double? _centerYaw;

  int _badFrames = 0;
  int _stableCenterFrames = 0;
  int _stableTurnFrames = 0;
  int _stableReturnFrames = 0;

  double? _bestTurnDelta;
  double? _bestReturnDelta;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (_disposed) {
      return;
    }

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

      final oldCamera = _camera;

      if (oldCamera != null) {
        await oldCamera.dispose();
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

      await Future<void>.delayed(const Duration(milliseconds: 900));

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
    } catch (_) {
      if (!mounted || _disposed) {
        return;
      }

      setState(() {
        _initializing = false;
        _error = 'Unable to start the camera.';
      });
    }
  }

  Future<void> _startChallenge() async {
    final controller = _camera;

    if (_running ||
        controller == null ||
        !controller.value.isInitialized ||
        _disposed) {
      return;
    }

    _resetChallenge();

    final challengeResult = await RegistrationService.instance
        .requestLivenessChallenge();

    if (!mounted || _disposed) {
      return;
    }

    if (!challengeResult.success || challengeResult.challenge == null) {
      _fail(challengeResult.message);
      return;
    }

    final challenge = challengeResult.challenge!;
    _challengeDirection = challenge.direction;
    _challengeNonce = challenge.nonce;
    _challengeSessionId = challenge.sessionId;

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

      if (!mounted ||
          _disposed ||
          !_running ||
          _step == _ChallengeStep.verifying ||
          _step == _ChallengeStep.failed) {
        break;
      }

      await Future<void>.delayed(captureInterval);
    }
  }

  void _resetChallenge() {
    _centerFrame = null;
    _turnedFrame = null;
    _returnedFrame = null;

    _centerYaw = null;

    _badFrames = 0;
    _stableCenterFrames = 0;
    _stableTurnFrames = 0;
    _stableReturnFrames = 0;
    _bestTurnDelta = null;
    _bestReturnDelta = null;
  }

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

      if (!result.success || !result.faceDetected) {
        _badFrames++;

        if (_badFrames >= maxBadFramesBeforeMessage && mounted) {
          setState(() {
            _error = result.message.isNotEmpty
                ? result.message
                : 'Keep one face clearly visible inside the guide.';
          });
        }

        return;
      }

      final yaw = result.yaw;

      if (yaw == null) {
        _badFrames++;

        if (_badFrames >= maxBadFramesBeforeMessage && mounted) {
          setState(() {
            _error = 'Keep your face clearly visible while the camera reads your head position.';
          });
        }

        return;
      }

      if (!result.faceInComfortableZone) {
        _badFrames++;

        if (_badFrames >= maxBadFramesBeforeMessage && mounted) {
          setState(() {
            _error = 'Move slightly closer to the middle so your whole face stays visible.';
          });
        }

        return;
      }

      _badFrames = 0;

      if (_error != null && mounted) {
        setState(() {
          _error = null;
        });
      }

      await _processMeasurement(frame: frame, yaw: yaw);
    } on CameraException catch (e) {
      if (!mounted || _disposed) {
        return;
      }

      setState(() {
        _error = 'Camera capture failed: ${e.description ?? e.code}';
      });
    } catch (_) {
      if (!mounted || _disposed) {
        return;
      }

      _badFrames++;

      if (_badFrames >= maxBadFramesBeforeMessage) {
        setState(() {
          _error = 'Unable to analyze the camera frame. Keep your face inside the guide.';
        });
      }
    } finally {
      _analyzing = false;
    }
  }

  Future<void> _processMeasurement({
    required XFile frame,
    required double yaw,
  }) async {
    switch (_step) {
      case _ChallengeStep.center:
        if (yaw.abs() <= centerYawLimit) {
          _stableCenterFrames++;

          final currentBest = _centerYaw;
          if (currentBest == null || yaw.abs() < currentBest.abs()) {
            _centerFrame = frame;
            _centerYaw = yaw;
          }

          if (_stableCenterFrames >= stableFramesRequired) {
            if (!mounted) {
              return;
            }

            setState(() {
              _step = _ChallengeStep.turn;
              _error = null;
            });
          }
        } else {
          _stableCenterFrames = 0;
        }
        break;

      case _ChallengeStep.turn:
        final centerYaw = _centerYaw;

        if (centerYaw == null) {
          _stableCenterFrames = 0;
          return;
        }

        final direction = _challengeDirection;
        if (direction == null) {
          return;
        }

        final signedDelta = yaw - centerYaw;
        final requestedDelta = direction == 'left' ? signedDelta : -signedDelta;

        if (requestedDelta >= turnYawDelta) {
          _stableTurnFrames++;

          if (_bestTurnDelta == null || requestedDelta > _bestTurnDelta!) {
            _bestTurnDelta = requestedDelta;
            _turnedFrame = frame;
          }

          if (_stableTurnFrames >= stableFramesRequired) {
            if (!mounted) {
              return;
            }

            setState(() {
              _step = _ChallengeStep.returnCenter;
              _error = null;
            });
          }
        } else {
          _stableTurnFrames = 0;
        }
        break;

      case _ChallengeStep.returnCenter:
        final centerYaw = _centerYaw;

        if (centerYaw == null) {
          _stableReturnFrames = 0;
          return;
        }

        final centered = yaw.abs() <= centerYawLimit;
        final returned = (yaw - centerYaw).abs() <= returnYawDelta;

        if (centered && returned) {
          _stableReturnFrames++;

          final difference = (yaw - centerYaw).abs();

          if (_bestReturnDelta == null || difference < _bestReturnDelta!) {
            _bestReturnDelta = difference;
            _returnedFrame = frame;
          }

          if (_stableReturnFrames >= stableFramesRequired) {
            await _verifyFinalFrames();
          }
        } else {
          _stableReturnFrames = 0;
        }
        break;

      case _ChallengeStep.preparing:
      case _ChallengeStep.verifying:
      case _ChallengeStep.failed:
        break;
    }
  }

  Future<void> _verifyFinalFrames() async {
    final centerFrame = _centerFrame;
    final turnedFrame = _turnedFrame;
    final returnedFrame = _returnedFrame;

    if (centerFrame == null || turnedFrame == null || returnedFrame == null) {
      _fail('Some biometric frames were not captured. Please try again.');
      return;
    }

    if (!mounted || _disposed) {
      return;
    }

    setState(() {
      _running = false;
      _step = _ChallengeStep.verifying;
      _error = null;
    });

    // Laravel currently expects the old five-frame payload.
    //
    // We keep that API unchanged so no service/controller changes
    // are required:
    //
    // center  -> center
    // blink   -> center
    // turn    -> turned
    // smile   -> turned
    // return  -> returned
    //
    // Blink and smile are NOT user challenges anymore.
    final result = await RegistrationService.instance.verifyRegistrationFace(
      centerFrame: centerFrame,
      blinkFrame: centerFrame,
      turnedFrame: turnedFrame,
      smileFrame: turnedFrame,
      returnedFrame: returnedFrame,
      challengeNonce: _challengeNonce!,
      sessionId: _challengeSessionId!,
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

  Future<void> _showSuccess() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          contentPadding: const EdgeInsets.fromLTRB(28, 30, 28, 26),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: const BoxDecoration(
                  color: Color(0xFF00B934),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 45,
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'Identity Verified',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF1E1E24),
                  fontSize: 26,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Liveness and facial identity verification completed successfully.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF38383E),
                  height: 1.45,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 26),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: navy,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Continue',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
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
    if (_running || _analyzing || _disposed) {
      return;
    }

    _resetChallenge();

    setState(() {
      _error = null;
      _step = _ChallengeStep.preparing;
    });

    await Future<void>.delayed(const Duration(milliseconds: 500));

    if (!mounted || _disposed) {
      return;
    }

    await _startChallenge();
  }

  String get _instruction {
    switch (_step) {
      case _ChallengeStep.preparing:
        return 'Position your face inside the guide';

      case _ChallengeStep.center:
        return 'Look directly at the camera';

      case _ChallengeStep.turn:
        return _challengeDirection == 'right'
            ? 'Turn your head to your RIGHT →'
            : '← Turn your head to your LEFT';

      case _ChallengeStep.returnCenter:
        return 'Return your face to center';

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
        return 'Step 1 of 3';

      case _ChallengeStep.turn:
        return 'Step 2 of 3';

      case _ChallengeStep.returnCenter:
        return 'Step 3 of 3';

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

      case _ChallengeStep.turn:
        return 1;

      case _ChallengeStep.returnCenter:
        return 2;

      case _ChallengeStep.verifying:
        return 3;

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

      case _ChallengeStep.turn:
        return Icons.sync_alt_rounded;

      case _ChallengeStep.verifying:
        return Icons.verified_user_rounded;

      case _ChallengeStep.failed:
        return Icons.error_outline_rounded;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _running = false;

    final camera = _camera;
    _camera = null;

    camera?.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_running,
      child: Scaffold(
        backgroundColor: background,
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
              ? const Center(child: CircularProgressIndicator(color: navy))
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
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
            child: Container(
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x26000000),
                    blurRadius: 24,
                    offset: Offset(0, 10),
                  ),
                ],
                color: Colors.black,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CameraPreview(controller),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      height: 100,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.45),
                          ],
                        ),
                      ),
                    ),
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
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: Icon(
              _stepIcon,
              key: ValueKey(_step.name),
              size: 30,
              color: _step == _ChallengeStep.failed ? Colors.red : navy,
            ),
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: Text(
              _instruction,
              key: ValueKey('${_step.name}-$_instruction'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: navy,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              _progress('Center', 0),
              _progress('Turn', 1),
              _progress('Center', 2),
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
                  foregroundColor: Colors.white,
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
            duration: const Duration(milliseconds: 180),
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
