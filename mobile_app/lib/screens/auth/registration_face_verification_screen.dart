import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../core/app_colors.dart';
import '../../models/liveness_challenge.dart';
import '../../services/registration_service.dart';
import '../home/home_screen.dart';

enum RegistrationLivenessStep { lookCenter, turn, verifying, passed, failed }

class _RawStreamFrame {
  final Uint8List plane0;
  final Uint8List? plane1;
  final Uint8List? plane2;
  final int width;
  final int height;
  final int bytesPerRow0;
  final int bytesPerRow1;
  final int bytesPerRow2;
  final int uvPixelStride;
  final int sensorOrientation;
  final bool isBgra;

  const _RawStreamFrame({
    required this.plane0,
    this.plane1,
    this.plane2,
    required this.width,
    required this.height,
    required this.bytesPerRow0,
    required this.bytesPerRow1,
    required this.bytesPerRow2,
    required this.uvPixelStride,
    required this.sensorOrientation,
    required this.isBgra,
  });
}

Uint8List _encodeRawFrameToJpeg(_RawStreamFrame raw) {
  img.Image image = img.Image(width: raw.width, height: raw.height);

  if (raw.isBgra) {
    final bytes = raw.plane0;
    for (int y = 0; y < raw.height; y++) {
      final rowOffset = y * raw.bytesPerRow0;
      for (int x = 0; x < raw.width; x++) {
        final idx = rowOffset + x * 4;
        if (idx + 2 < bytes.length) {
          image.setPixelRgb(x, y, bytes[idx + 2], bytes[idx + 1], bytes[idx]);
        }
      }
    }
  } else {
    final yPlane = raw.plane0;
    final uPlane = raw.plane1;
    final vPlane = raw.plane2;

    for (int y = 0; y < raw.height; y++) {
      final yRow = y * raw.bytesPerRow0;
      final uvRowIndex = y >> 1;
      for (int x = 0; x < raw.width; x++) {
        final yIdx = yRow + x;
        if (yIdx >= yPlane.length) continue;
        final yp = yPlane[yIdx];

        int up = 128;
        int vp = 128;

        if (uPlane != null && vPlane != null) {
          final uIdx =
              uvRowIndex * raw.bytesPerRow1 + (x >> 1) * raw.uvPixelStride;
          final vIdx =
              uvRowIndex * raw.bytesPerRow2 + (x >> 1) * raw.uvPixelStride;
          if (uIdx < uPlane.length && vIdx < vPlane.length) {
            up = uPlane[uIdx];
            vp = vPlane[vIdx];
          }
        } else if (uPlane != null) {
          final uvIdx =
              uvRowIndex * raw.bytesPerRow1 + (x >> 1) * raw.uvPixelStride;
          if (uvIdx + 1 < uPlane.length) {
            vp = uPlane[uvIdx];
            up = uPlane[uvIdx + 1];
          }
        } else {
          final uvBase = raw.bytesPerRow0 * raw.height;
          final uvIdx = uvBase + uvRowIndex * raw.bytesPerRow0 + ((x >> 1) * 2);
          if (uvIdx + 1 < yPlane.length) {
            vp = yPlane[uvIdx];
            up = yPlane[uvIdx + 1];
          }
        }

        final r = (yp + 1.402 * (vp - 128)).round().clamp(0, 255);
        final g = (yp - 0.344136 * (up - 128) - 0.714136 * (vp - 128))
            .round()
            .clamp(0, 255);
        final b = (yp + 1.772 * (up - 128)).round().clamp(0, 255);
        image.setPixelRgb(x, y, r, g, b);
      }
    }
  }

  if (raw.sensorOrientation == 90) {
    image = img.copyRotate(image, angle: 90);
  } else if (raw.sensorOrientation == 180) {
    image = img.copyRotate(image, angle: 180);
  } else if (raw.sensorOrientation == 270) {
    image = img.copyRotate(image, angle: 270);
  }

  if (image.width > 384) {
    image = img.copyResize(image, width: 384);
  }

  return Uint8List.fromList(img.encodeJpg(image, quality: 82));
}

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
  static const double _requiredTurnAngle = 14.0;
  static const int _colorHoldMs = 380;

  CameraController? _camera;
  CameraDescription? _frontCamera;
  late final FaceDetector _faceDetector;

  bool _cameraReady = false;
  bool _disposed = false;
  bool _isProcessingFrame = false;
  bool _isSubmitting = false;

  RegistrationLivenessStep _step = RegistrationLivenessStep.lookCenter;

  LivenessChallenge? _challenge;
  String _direction = 'left';
  double _centerYaw = 0.0;
  int _steadyCenterCount = 0;

  double _holdProgress = 0.0;
  double _turnProgress = 0.0;

  String? _hint;
  String? _error;

  Color _overlayFlashColor = Colors.transparent;
  Timer? _flashTimer;
  int _flashCycleIndex = 0;
  int _activeFlashStep = -1;
  DateTime? _flashShownAt;

  List<String> _flashColorNames = const ['red', 'green', 'blue'];

  final Map<int, _RawStreamFrame> _capturedRgbFrames = {};
  _RawStreamFrame? _rawCenterFrame;
  _RawStreamFrame? _rawTurnedFrame;

  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableTracking: false,
        enableContours: false,
        enableLandmarks: false,
        enableClassification: false,
        minFaceSize: 0.20,
      ),
    );

    _initLivenessChallengeAndCamera();
  }

  Color _colorFromName(String name) {
    switch (name.trim().toLowerCase()) {
      case 'red':
        return const Color(0xFFFF0000);
      case 'green':
        return const Color(0xFF00FF00);
      case 'blue':
        return const Color(0xFF0000FF);
      default:
        return const Color(0xFFFF0000);
    }
  }

  Future<void> _initLivenessChallengeAndCamera() async {
    try {
      final results = await Future.wait([
        RegistrationService.instance.requestLivenessChallenge(),
        availableCameras(),
      ]);

      if (!mounted || _disposed) return;

      final challengeResult = results[0] as LivenessChallengeResult;
      final cameras = results[1] as List<CameraDescription>;

      if (challengeResult.success && challengeResult.challenge != null) {
        _challenge = challengeResult.challenge;
        _direction = _challenge!.direction;
        if (_challenge!.flashColors.isNotEmpty) {
          _flashColorNames = _challenge!.flashColors;
        }
      }

      if (cameras.isEmpty) {
        throw Exception('No camera available.');
      }

      final selected = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _frontCamera = selected;

      final controller = CameraController(
        selected,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
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
                Text(
                  'Your screen will flash RED, GREEN, and BLUE light while you look straight and then turn your head to your $_direction.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
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
                        Icons.light_mode_rounded,
                        color: Color(0xFFD97706),
                        size: 22,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Keep your face centered, hold steady during flashes, and turn your head smoothly.',
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
                    onPressed: () => Navigator.of(dialogContext).pop(),
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
      await _startContinuousCapture();
    }
  }

  void _startContinuousFlashing() {
    _flashTimer?.cancel();
    _flashCycleIndex = 0;
    setState(() {
      _overlayFlashColor = _colorFromName(_flashColorNames[0]);
    });

    _flashTimer = Timer.periodic(const Duration(milliseconds: 240), (timer) {
      if (!mounted || _disposed) {
        timer.cancel();
        return;
      }
      _flashCycleIndex = (_flashCycleIndex + 1) % _flashColorNames.length;
      setState(() {
        _overlayFlashColor = _colorFromName(_flashColorNames[_flashCycleIndex]);
      });
    });
  }

  void _stopContinuousFlashing() {
    _flashTimer?.cancel();
    _flashTimer = null;
    if (mounted && !_disposed) {
      setState(() {
        _overlayFlashColor = Colors.transparent;
      });
    }
  }

  Future<void> _startContinuousCapture() async {
    final controller = _camera;
    if (controller == null || !controller.value.isInitialized || _disposed) {
      return;
    }

    _capturedRgbFrames.clear();
    _rawCenterFrame = null;
    _rawTurnedFrame = null;
    _steadyCenterCount = 0;
    _centerYaw = 0.0;
    _activeFlashStep = -1;
    _flashShownAt = null;
    _isSubmitting = false;
    _flashTimer?.cancel();
    _flashTimer = null;

    if (!mounted || _disposed) return;

    setState(() {
      _overlayFlashColor = Colors.transparent;
      _step = RegistrationLivenessStep.lookCenter;
      _holdProgress = 0.08;
      _turnProgress = 0.0;
      _hint = 'Look straight at the camera...';
      _error = null;
    });

    if (!controller.value.isStreamingImages) {
      await controller.startImageStream(_onCameraFrame);
    }
  }

  Future<void> _stopStream() async {
    final controller = _camera;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isStreamingImages) {
      try {
        await controller.stopImageStream();
      } catch (_) {}
    }
  }

  Future<void> _onCameraFrame(CameraImage image) async {
    if (_disposed ||
        !mounted ||
        _isProcessingFrame ||
        _isSubmitting ||
        _step == RegistrationLivenessStep.verifying ||
        _step == RegistrationLivenessStep.passed ||
        _step == RegistrationLivenessStep.failed) {
      return;
    }

    _isProcessingFrame = true;

    try {
      final inputImage = _toInputImage(image);
      if (inputImage == null) return;

      final faces = await _faceDetector.processImage(inputImage);
      if (_disposed || !mounted) return;

      if (faces.isEmpty) {
        if (_hint != 'Position your face clearly inside the circle') {
          setState(() => _hint = 'Position your face clearly inside the circle');
        }
        return;
      }

      final face = faces.first;
      final double yaw = face.headEulerAngleY ?? 0.0;

      if (_step == RegistrationLivenessStep.lookCenter) {
        if (yaw.abs() > 15.0) {
          const msg = 'Look straight at the camera while screen flashes...';
          if (_hint != msg) {
            setState(() => _hint = msg);
          }
          return;
        }

        if (_activeFlashStep == -1) {
          _steadyCenterCount++;
          if (_steadyCenterCount < 2) {
            setState(() => _holdProgress = 0.15);
            return;
          }

          _rawCenterFrame = _copyRawFrame(image);
          _centerYaw = yaw;

          _activeFlashStep = 0;
          _flashShownAt = DateTime.now();
          setState(() {
            _overlayFlashColor = _colorFromName(_flashColorNames[0]);
            _holdProgress = 0.25;
            _hint = 'Hold still. Screen is verifying light reflections...';
          });
          return;
        }

        final shownAt = _flashShownAt;
        if (shownAt == null ||
            DateTime.now().difference(shownAt).inMilliseconds < _colorHoldMs) {
          return;
        }

        _capturedRgbFrames[_activeFlashStep] = _copyRawFrame(image);
        final int nextStep = _activeFlashStep + 1;

        if (nextStep < _flashColorNames.length) {
          _activeFlashStep = nextStep;
          _flashShownAt = DateTime.now();
          final double progress =
              0.25 + (0.75 * (nextStep / _flashColorNames.length));
          setState(() {
            _overlayFlashColor = _colorFromName(_flashColorNames[nextStep]);
            _holdProgress = progress.clamp(0.0, 1.0);
          });
        } else {
          _activeFlashStep = nextStep;
          _startContinuousFlashing();
          setState(() {
            _holdProgress = 1.0;
            _step = RegistrationLivenessStep.turn;
            _turnProgress = 0.25;
            _hint =
                'Turn your head to your ${_direction.toUpperCase()} while screen flashes...';
          });
        }
      } else if (_step == RegistrationLivenessStep.turn) {
        final double deltaYaw = yaw - _centerYaw;
        final bool turnedLeft = deltaYaw >= _requiredTurnAngle;
        final bool turnedRight = deltaYaw <= -_requiredTurnAngle;

        final bool reachedTargetDirection =
            (_direction == 'left' && turnedLeft) ||
                (_direction == 'right' && turnedRight);

        if (!reachedTargetDirection) {
          if (_direction == 'left' && turnedRight) {
            const wrongMsg =
                'Wrong direction — turn your head to your LEFT...';
            if (_hint != wrongMsg) setState(() => _hint = wrongMsg);
          } else if (_direction == 'right' && turnedLeft) {
            const wrongMsg =
                'Wrong direction — turn your head to your RIGHT...';
            if (_hint != wrongMsg) setState(() => _hint = wrongMsg);
          }
          return;
        }

        _rawTurnedFrame = _copyRawFrame(image);
        _stopContinuousFlashing();
        await _stopStream();

        if (!mounted || _disposed) return;

        setState(() {
          _overlayFlashColor = Colors.transparent;
          _turnProgress = 1.0;
          _step = RegistrationLivenessStep.verifying;
          _hint = 'Registering face biometrics...';
        });

        await _encodeAndSubmit();
      }
    } catch (e) {
      debugPrint('Liveness stream error: $e');
    } finally {
      _isProcessingFrame = false;
    }
  }

  _RawStreamFrame _copyRawFrame(CameraImage image) {
    final bool isBgra = image.format.group == ImageFormatGroup.bgra8888;
    return _RawStreamFrame(
      plane0: Uint8List.fromList(image.planes[0].bytes),
      plane1: image.planes.length > 1
          ? Uint8List.fromList(image.planes[1].bytes)
          : null,
      plane2: image.planes.length > 2
          ? Uint8List.fromList(image.planes[2].bytes)
          : null,
      width: image.width,
      height: image.height,
      bytesPerRow0: image.planes[0].bytesPerRow,
      bytesPerRow1: image.planes.length > 1 ? image.planes[1].bytesPerRow : 0,
      bytesPerRow2: image.planes.length > 2 ? image.planes[2].bytesPerRow : 0,
      uvPixelStride:
          image.planes.length > 1 ? (image.planes[1].bytesPerPixel ?? 1) : 1,
      sensorOrientation: _frontCamera?.sensorOrientation ?? 270,
      isBgra: isBgra,
    );
  }

  InputImage? _toInputImage(CameraImage image) {
    final camera = _frontCamera;
    if (camera == null) return null;

    final rotation =
        InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    if (image.planes.isEmpty) return null;

    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }

    return InputImage.fromBytes(
      bytes: allBytes.done().buffer.asUint8List(),
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  Future<void> _encodeAndSubmit() async {
    if (_isSubmitting || _rawCenterFrame == null || _rawTurnedFrame == null) {
      return;
    }

    _isSubmitting = true;

    try {
      final tempDir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;

      final orderedRgbFrames = <_RawStreamFrame>[];
      final orderedRgbColors = <String>[];
      for (int i = 0; i < _flashColorNames.length; i++) {
        final frame = _capturedRgbFrames[i];
        if (frame != null) {
          orderedRgbFrames.add(frame);
          orderedRgbColors.add(_flashColorNames[i]);
        }
      }

      final futures = <Future<Uint8List>>[
        compute(_encodeRawFrameToJpeg, _rawCenterFrame!),
        compute(_encodeRawFrameToJpeg, _rawTurnedFrame!),
        ...orderedRgbFrames.map((f) => compute(_encodeRawFrameToJpeg, f)),
      ];

      final encodedBytes = await Future.wait(futures);

      Future<XFile> writeTemp(String name, Uint8List bytes) async {
        final file = File('${tempDir.path}/${ts}_$name.jpg');
        await file.writeAsBytes(bytes, flush: true);
        return XFile(file.path);
      }

      final centerFile = await writeTemp('center', encodedBytes[0]);
      final turnedFile = await writeTemp('turned', encodedBytes[1]);
      final flashFiles = <XFile>[];
      for (int i = 2; i < encodedBytes.length; i++) {
        flashFiles.add(await writeTemp('flash_${i - 2}', encodedBytes[i]));
      }

      final nonce = _challenge?.nonce ?? 'fallback_nonce';
      final sessionId = _challenge?.sessionId ?? 'fallback_session_id';

      final result = await RegistrationService.instance
          .verifyRegistrationFace(
            centerFrame: centerFile,
            turnedFrame: turnedFile,
            flashFrames: flashFiles,
            flashColors: orderedRgbColors,
            challengeNonce: nonce,
            sessionId: sessionId,
          )
          .timeout(const Duration(seconds: 35));

      if (!mounted || _disposed) return;

      if (!result.success) {
        throw Exception(result.message);
      }

      setState(() {
        _step = RegistrationLivenessStep.passed;
      });

      await _showSuccessModalAndNavigate();
    } on TimeoutException {
      if (!mounted || _disposed) return;
      setState(() {
        _step = RegistrationLivenessStep.failed;
        _overlayFlashColor = Colors.transparent;
        _error = 'Verification timed out. Tap Retry to try again.';
      });
    } catch (e) {
      if (!mounted || _disposed) return;
      setState(() {
        _step = RegistrationLivenessStep.failed;
        _overlayFlashColor = Colors.transparent;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      _isSubmitting = false;
    }
  }

  Future<void> _retryVerification() async {
    if (_isSubmitting) return;
    _stopContinuousFlashing();
    await _stopStream();

    final res = await RegistrationService.instance.requestLivenessChallenge();
    if (!mounted || _disposed) return;
    if (res.success && res.challenge != null) {
      _challenge = res.challenge;
      _direction = _challenge!.direction;
      if (_challenge!.flashColors.isNotEmpty) {
        _flashColorNames = _challenge!.flashColors;
      }
    }
    await _startContinuousCapture();
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
                    onPressed: () => Navigator.of(dialogContext).pop(),
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
    _flashTimer?.cancel();
    _pulseController.dispose();
    _disposed = true;
    _stopStream();
    _camera?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isFlashing = _overlayFlashColor != Colors.transparent;

    return Scaffold(
      backgroundColor: isFlashing ? _overlayFlashColor : AppColors.background,
      appBar: AppBar(
        backgroundColor: isFlashing ? _overlayFlashColor : AppColors.navy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Register Face Biometrics',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            Text(
              'Face Registration',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isFlashing ? Colors.white : AppColors.navy,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _hint ?? 'Position your face inside the circle',
              style: TextStyle(
                fontSize: 13,
                color: isFlashing ? Colors.white : Colors.grey,
                fontWeight: isFlashing ? FontWeight.w600 : FontWeight.normal,
              ),
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
                        width: 278,
                        height: 278,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: (isFlashing ? Colors.white : AppColors.gold)
                                .withValues(
                              alpha: 0.4 + (_pulseController.value * 0.45),
                            ),
                            width: isFlashing ? 6.0 : 3.5,
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
                      border: Border.all(
                        color: isFlashing ? _overlayFlashColor : AppColors.gold,
                        width: isFlashing ? 8 : 4,
                      ),
                    ),
                    child: ClipOval(
                      child: _cameraReady &&
                              _camera != null &&
                              _camera!.value.isInitialized
                          ? _buildUndistortedPreview(_camera!)
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
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            _buildProgressBar(),
            const SizedBox(height: 20),
            if (!isFlashing)
              ElevatedButton(
                onPressed: _isSubmitting ? null : _retryVerification,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: AppColors.navy,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 36, vertical: 12),
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

  Widget _buildUndistortedPreview(CameraController controller) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) {
      return CameraPreview(controller);
    }

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: previewSize.height,
          height: previewSize.width,
          child: CameraPreview(controller),
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
    final double progress = _step == RegistrationLivenessStep.lookCenter
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