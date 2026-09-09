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
  // ===========================================================================
  // THEME
  // ===========================================================================

  static const Color navy = Color(0xFF080878);
  static const Color gold = Color(0xFFFFC800);
  static const Color background = Color(0xFFF7F7FB);

  // ===========================================================================
  // LIVENESS THRESHOLDS
  // ===========================================================================

  /*
   * Keep these aligned with the Python service.
   */

  static const double centerYawLimit = 0.08;

  static const double turnYawDelta = 0.06;

  static const double returnYawDelta = 0.06;

  /*
   * Blink:
   *
   * Closed eye must fall below:
   *
   * centerEyeOpenness * 0.88
   *
   * Example:
   *
   * center = 0.100
   * closed threshold = 0.088
   *
   * eye = 0.084
   * -> CLOSED
   */
  static const double blinkRatio = 0.88;

  /*
   * Eyes must reopen close to the original
   * center baseline before proceeding.
   */
  static const double blinkReopenRatio = 0.92;

  static const double smileRatio = 1.04;

  // ===========================================================================
  // CAPTURE SPEED
  // ===========================================================================

  /*
   * DO NOT use the old fixed 800 ms delay.
   *
   * Blink is a very short gesture, so Blink gets
   * the fastest sampling interval.
   *
   * Actual throughput is still limited by:
   *
   * Camera
   * -> Laravel
   * -> Python
   * -> response
   *
   * but this removes unnecessary waiting.
   */

  static const Duration normalCaptureInterval = Duration(milliseconds: 250);

  static const Duration blinkCaptureInterval = Duration(milliseconds: 80);

  Duration get _currentCaptureInterval {
    if (_step == _ChallengeStep.blink) {
      return blinkCaptureInterval;
    }

    return normalCaptureInterval;
  }

  // ===========================================================================
  // CAMERA / STATE
  // ===========================================================================

  CameraController? _camera;

  bool _initializing = true;

  bool _running = false;

  bool _analyzing = false;

  bool _disposed = false;

  String? _error;

  _ChallengeStep _step = _ChallengeStep.preparing;

  // ===========================================================================
  // ACCEPTED CHALLENGE FRAMES
  // ===========================================================================

  XFile? _centerFrame;

  XFile? _blinkFrame;

  XFile? _turnedFrame;

  XFile? _smileFrame;

  XFile? _returnedFrame;

  // ===========================================================================
  // CENTER BASELINE
  // ===========================================================================

  double? _centerYaw;

  double? _centerEyeOpenness;

  double? _centerMouthWidth;

  // ===========================================================================
  // BLINK STATE MACHINE
  // ===========================================================================

  /*
   * Blink MUST happen in two phases:
   *
   * OPEN
   *   ↓
   * CLOSED
   *   ↓
   * OPEN
   *
   * This variable remembers that the CLOSED
   * state has already happened.
   */
  bool _blinkClosedDetected = false;

  /*
   * UI helper.
   *
   * false:
   * "Blink both eyes naturally"
   *
   * true:
   * "Open your eyes"
   */
  bool get _waitingForBlinkReopen {
    return _step == _ChallengeStep.blink && _blinkClosedDetected;
  }

  // ===========================================================================
  // BAD FRAME HANDLING
  // ===========================================================================

  int _badFrames = 0;

  static const int maxBadFramesBeforeMessage = 6;

  // ===========================================================================
  // INIT
  // ===========================================================================

  @override
  void initState() {
    super.initState();

    _initializeCamera();
  }

  // ===========================================================================
  // CAMERA
  // ===========================================================================

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

      /*
       * Short preparation window.
       *
       * The previous version waited two seconds.
       * 900 ms feels significantly more responsive
       * while still allowing the preview to settle.
       */
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
  // START
  // ===========================================================================

  Future<void> _startChallenge() async {
    final controller = _camera;

    if (_running ||
        controller == null ||
        !controller.value.isInitialized ||
        _disposed) {
      return;
    }

    _resetChallenge();

    if (!mounted) {
      return;
    }

    setState(() {
      _running = true;
      _error = null;
      _step = _ChallengeStep.center;
    });

    /*
     * One sequential analysis request at a time.
     *
     * This prevents overlapping:
     *
     * takePicture()
     * -> Laravel
     * -> Python
     *
     * requests.
     */
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

      await Future<void>.delayed(_currentCaptureInterval);
    }
  }

  // ===========================================================================
  // RESET
  // ===========================================================================

  void _resetChallenge() {
    _centerFrame = null;

    _blinkFrame = null;

    _turnedFrame = null;

    _smileFrame = null;

    _returnedFrame = null;

    _centerYaw = null;

    _centerEyeOpenness = null;

    _centerMouthWidth = null;

    /*
     * IMPORTANT:
     *
     * This was missing from the old code.
     */
    _blinkClosedDetected = false;

    _badFrames = 0;
  }

  // ===========================================================================
  // CAPTURE + ANALYZE
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
       * 422 / temporary bad camera frame should
       * NOT instantly interrupt the challenge.
       *
       * A blink itself may temporarily reduce
       * face confidence.
       */
      if (!result.success || !result.faceDetected) {
        _badFrames++;

        if (_badFrames >= maxBadFramesBeforeMessage) {
          if (mounted) {
            setState(() {
              _error = result.message.isNotEmpty
                  ? result.message
                  : 'Keep one face clearly visible inside the guide.';
            });
          }
        }

        return;
      }

      final yaw = result.yaw;

      final eye = result.eyeOpenness;

      final mouth = result.mouthWidth;

      if (yaw == null || eye == null || mouth == null) {
        _badFrames++;

        if (_badFrames >= maxBadFramesBeforeMessage) {
          setState(() {
            _error = 'Unable to read facial measurements. Keep your face clearly visible.';
          });
        }

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

      /*
       * Do not fail the entire challenge because
       * one frame could not be analyzed.
       */
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

  // ===========================================================================
  // CHALLENGE PROCESSING
  // ===========================================================================

  Future<void> _processMeasurement({
    required XFile frame,
    required double yaw,
    required double eyeOpenness,
    required double mouthWidth,
  }) async {
    switch (_step) {
      // =======================================================================
      // CENTER
      // =======================================================================

      case _ChallengeStep.center:
        if (yaw.abs() <= centerYawLimit) {
          _centerFrame = frame;

          _centerYaw = yaw;

          _centerEyeOpenness = eyeOpenness;

          _centerMouthWidth = mouthWidth;

          _blinkClosedDetected = false;

          if (!mounted) {
            return;
          }

          setState(() {
            _step = _ChallengeStep.blink;
          });
        }

        break;

      // =======================================================================
      // BLINK
      // =======================================================================

      case _ChallengeStep.blink:
        final baseline = _centerEyeOpenness;

        if (baseline == null || baseline <= 0) {
          _fail('Center eye measurement was lost. Please try again.');

          return;
        }

        /*
         * CLOSED THRESHOLD
         *
         * Example:
         *
         * baseline = 0.100
         *
         * closed <= 0.088
         */
        final closedThreshold = baseline * blinkRatio;

        /*
         * REOPEN THRESHOLD
         *
         * Example:
         *
         * baseline = 0.100
         *
         * reopened >= 0.092
         */
        final reopenThreshold = baseline * blinkReopenRatio;

        // ---------------------------------------------------------------
        // PHASE 1: DETECT CLOSED EYES
        // ---------------------------------------------------------------

        if (!_blinkClosedDetected) {
          if (eyeOpenness <= closedThreshold) {
            /*
             * THIS MUST BE TRUE.
             *
             * Your previous code incorrectly
             * assigned false here.
             */
            _blinkClosedDetected = true;

            /*
             * Save the genuinely closed-eye frame.
             *
             * Python will validate this again
             * during final verification.
             */
            _blinkFrame = frame;

            if (mounted) {
              setState(() {
                /*
                 * Rebuild immediately so UI changes
                 * from:
                 *
                 * Blink both eyes naturally
                 *
                 * to:
                 *
                 * Open your eyes
                 */
              });
            }
          }

          break;
        }

        // ---------------------------------------------------------------
        // PHASE 2: DETECT EYES REOPENING
        // ---------------------------------------------------------------

        if (eyeOpenness >= reopenThreshold) {
          if (!mounted) {
            return;
          }

          setState(() {
            _step = _ChallengeStep.turn;
          });
        }

        break;

      // =======================================================================
      // TURN
      // =======================================================================

      case _ChallengeStep.turn:
        final centerYaw = _centerYaw;

        if (centerYaw == null) {
          _fail('Center measurements were lost. Please try again.');

          return;
        }

        final delta = (yaw - centerYaw).abs();

        if (delta >= turnYawDelta) {
          _turnedFrame = frame;

          if (!mounted) {
            return;
          }

          setState(() {
            _step = _ChallengeStep.smile;
          });
        }

        break;

      // =======================================================================
      // SMILE
      // =======================================================================

      case _ChallengeStep.smile:
        final centerMouth = _centerMouthWidth;

        if (centerMouth == null || centerMouth <= 0) {
          _fail('Center measurements were lost. Please try again.');

          return;
        }

        final requiredSmile = centerMouth * smileRatio;

        if (mouthWidth >= requiredSmile) {
          _smileFrame = frame;

          if (!mounted) {
            return;
          }

          setState(() {
            _step = _ChallengeStep.returnCenter;
          });
        }

        break;

      // =======================================================================
      // RETURN CENTER
      // =======================================================================

      case _ChallengeStep.returnCenter:
        final originalYaw = _centerYaw;

        if (originalYaw == null) {
          _fail('Center measurements were lost. Please try again.');

          return;
        }

        final centered = yaw.abs() <= centerYawLimit;

        final returned = (yaw - originalYaw).abs() <= returnYawDelta;

        if (centered && returned) {
          _returnedFrame = frame;

          await _verifyFinalFrames();
        }

        break;

      // =======================================================================
      // NO PROCESSING
      // =======================================================================

      case _ChallengeStep.preparing:
      case _ChallengeStep.verifying:
      case _ChallengeStep.failed:
        break;
    }
  }

  // ===========================================================================
  // FINAL LARAVEL / PYTHON VERIFICATION
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

    if (!mounted || _disposed) {
      return;
    }

    setState(() {
      _running = false;

      _step = _ChallengeStep.verifying;

      _error = null;
    });

    /*
     * Final server-side verification remains.
     *
     * This protects against:
     *
     * - gesture spoofing
     * - wrong person
     * - identical twin mismatch
     * - frame substitution
     *
     * Laravel:
     * -> FaceService
     *
     * Python:
     * -> MediaPipe
     * -> OpenCV
     * -> InsightFace
     */
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

  // ===========================================================================
  // FAIL
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

  // ===========================================================================
  // RETRY
  // ===========================================================================

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

  // ===========================================================================
  // UI TEXT
  // ===========================================================================

  String get _instruction {
    switch (_step) {
      case _ChallengeStep.preparing:
        return 'Position your face inside the guide';

      case _ChallengeStep.center:
        return 'Look directly at the camera';

      case _ChallengeStep.blink:
        if (_waitingForBlinkReopen) {
          return 'Open your eyes';
        }

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
        return _waitingForBlinkReopen
            ? Icons.visibility_rounded
            : Icons.visibility_off_rounded;

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

    final camera = _camera;

    _camera = null;

    camera?.dispose();

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

  // ===========================================================================
  // FATAL CAMERA ERROR
  // ===========================================================================

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

  // ===========================================================================
  // CHALLENGE UI
  // ===========================================================================

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

                    /*
                     * Small visual confirmation
                     * when closed eyes have been
                     * detected.
                     */
                    if (_waitingForBlinkReopen)
                      Container(color: gold.withValues(alpha: 0.08)),

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

          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: Icon(
              _stepIcon,
              key: ValueKey('${_step.name}-$_blinkClosedDetected'),
              size: 30,
              color: _step == _ChallengeStep.failed ? Colors.red : navy,
            ),
          ),

          const SizedBox(height: 8),

          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: Text(
              _instruction,
              key: ValueKey('$_instruction-${_step.name}'),
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

  // ===========================================================================
  // PROGRESS
  // ===========================================================================

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
