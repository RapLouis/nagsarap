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

enum RegistrationLivenessStep { lookCenter, flash, turn, verifying, passed, failed }

class _RawStreamFrame {
  final Uint8List plane0;
  final Uint8List? plane1;
  final Uint8List? plane2;
  final int width;
  final int height;
  final int bytesPerRow0;
  final int bytesPerRow1;
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
      final uvRow = (y >> 1) * raw.bytesPerRow1;
      for (int x = 0; x < raw.width; x++) {
        final yIdx = yRow + x;
        if (yIdx >= yPlane.length) continue;
        final yp = yPlane[yIdx];

        int up = 128;
        int vp = 128;
        if (uPlane != null && vPlane != null) {
          final uvIdx = uvRow + (x >> 1) * raw.uvPixelStride;
          if (uvIdx < uPlane.length && uvIdx < vPlane.length) {
            up = uPlane[uvIdx];
            vp = vPlane[uvIdx];
          }
        }

        final r = (yp + 1.402 * (vp - 128)).round().clamp(0, 255);
        final g =
            (yp - 0.344136 * (up - 128) - 0.714136 * (vp - 128)).round().clamp(0, 255);
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

  if (image.width > 480) {
    image = img.copyResize(image, width: 480);
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

  double _progress = 0.0;
  String? _hint;
  String? _error;

  Color _overlayFlashColor = Colors.transparent;
  final List<String> _flashColorNames = ['red', 'green', 'blue'];
  final List<Color> _flashColorValues = [
    Colors.red,
    Colors.green,
    Colors.blue,
  ];

  int _centerStableCount = 0;
  int _flashIndex = 0;
  DateTime? _flashColorShownAt;
  bool _capturingFlash = false;

  _RawStreamFrame? _rawCenterFrame;
  _RawStreamFrame? _rawTurnedFrame;
  final List<_RawStreamFrame> _rawFlashFrames = [];

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
        ResolutionPreset.medium,
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
                  'Quick Liveness Check',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Look straight at the camera for a quick RGB light check, then turn your head slightly to your $_direction.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black87,
                    height: 1.4,
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
                      'Start Verification',
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
      await _startStreamCapture();
    }
  }

  Future<void> _startStreamCapture() async {
    final controller = _camera;
    if (controller == null || !controller.value.isInitialized || _disposed) {
      return;
    }

    _rawCenterFrame = null;
    _rawTurnedFrame = null;
    _rawFlashFrames.clear();
    _centerStableCount = 0;
    _flashIndex = 0;
    _flashColorShownAt = null;
    _capturingFlash = false;

    setState(() {
      _step = RegistrationLivenessStep.lookCenter;
      _progress = 0.05;
      _hint = 'Look straight at the camera...';
      _error = null;
      _overlayFlashColor = Colors.transparent;
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
      // PHASE 2: Fast RGB Screen Flash Capture (120ms per color, zero shutter lag)
      if (_step == RegistrationLivenessStep.flash) {
        if (!_capturingFlash) {
          _capturingFlash = true;
          setState(() {
            _overlayFlashColor = _flashColorValues[_flashIndex];
            _hint = 'Hold still — verifying screen light...';
          });
          _flashColorShownAt = DateTime.now();
        } else if (_flashColorShownAt != null &&
            DateTime.now().difference(_flashColorShownAt!).inMilliseconds >=
                110) {
          _rawFlashFrames.add(_copyRawFrame(image));
          _flashIndex++;

          if (_flashIndex < _flashColorValues.length) {
            setState(() {
              _overlayFlashColor = _flashColorValues[_flashIndex];
              _progress = 0.35 + (0.30 * (_flashIndex / _flashColorValues.length));
            });
            _flashColorShownAt = DateTime.now();
          } else {
            _capturingFlash = false;
            setState(() {
              _overlayFlashColor = Colors.transparent;
              _step = RegistrationLivenessStep.turn;
              _progress = 0.70;
              _hint = 'Now turn your head to your $_direction';
            });
          }
        }
        return;
      }

      // PHASE 1 & PHASE 3: Real-time ML Kit Pose Check
      final inputImage = _toInputImage(image);
      if (inputImage == null) return;

      final faces = await _faceDetector.processImage(inputImage);
      if (_disposed || !mounted) return;

      if (faces.isEmpty) {
        _centerStableCount = 0;
        if (_hint != 'Position your face inside the circle') {
          setState(() => _hint = 'Position your face inside the circle');
        }
        return;
      }

      final face = faces.first;
      final double yaw = face.headEulerAngleY ?? 0.0;

      if (_step == RegistrationLivenessStep.lookCenter) {
        if (yaw.abs() <= 11.0) {
          _centerStableCount++;
          setState(() {
            _progress = 0.05 + (0.30 * (_centerStableCount / 3).clamp(0.0, 1.0));
          });

          if (_centerStableCount >= 3) {
            _rawCenterFrame = _copyRawFrame(image);
            setState(() {
              _step = RegistrationLivenessStep.flash;
              _progress = 0.35;
            });
          }
        } else {
          _centerStableCount = 0;
          setState(() => _hint = 'Look straight at the camera');
        }
      } else if (_step == RegistrationLivenessStep.turn) {
        // Front camera yaw sign can invert across Android HALs, so accept clear turn
        // toward target direction (and > 15 deg head turn)
        final bool turnedEnough = yaw.abs() >= 15.0;
        if (turnedEnough) {
          _rawTurnedFrame = _copyRawFrame(image);
          setState(() {
            _progress = 1.0;
            _step = RegistrationLivenessStep.verifying;
            _hint = 'Registering face biometrics...';
          });
          await _stopStream();
          await _encodeAndSubmit();
        }
      }
    } catch (e) {
      debugPrint('Liveness frame error: $e');
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

      // Encode center, turned, and 3 RGB flash frames in parallel isolates
      final futures = <Future<Uint8List>>[
        compute(_encodeRawFrameToJpeg, _rawCenterFrame!),
        compute(_encodeRawFrameToJpeg, _rawTurnedFrame!),
        ..._rawFlashFrames.map((f) => compute(_encodeRawFrameToJpeg, f)),
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

      final result = await RegistrationService.instance.verifyRegistrationFace(
        centerFrame: centerFile,
        turnedFrame: turnedFile,
        flashFrames: flashFiles,
        flashColors: _flashColorNames.take(flashFiles.length).toList(),
        challengeNonce: nonce,
        sessionId: sessionId,
      );

      if (!mounted || _disposed) return;

      if (!result.success) {
        throw Exception(result.message);
      }

      setState(() {
        _step = RegistrationLivenessStep.passed;
      });

      await _showSuccessModalAndNavigate();
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
    await _stopStream();
    final res = await RegistrationService.instance.requestLivenessChallenge();
    if (!mounted || _disposed) return;
    if (res.success && res.challenge != null) {
      _challenge = res.challenge;
      _direction = _challenge!.direction;
    }
    await _startStreamCapture();
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
    _pulseController.dispose();
    _disposed = true;
    _stopStream();
    _camera?.dispose();
    _faceDetector.close();
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
            SizedBox(
              width: 180,
              height: 6,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.grey.shade300,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.navy),
                ),
              ),
            ),
            const SizedBox(height: 20),
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
      case RegistrationLivenessStep.flash:
        text = 'Hold still — checking light...';
        icon = Icons.wb_sunny_outlined;
        break;
      case RegistrationLivenessStep.turn:
        text = 'Turn your head to your $_direction';
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
}