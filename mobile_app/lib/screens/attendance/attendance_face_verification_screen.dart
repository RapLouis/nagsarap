import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/app_colors.dart';
import '../../models/event_item.dart';
import '../../services/attendance_service.dart';

enum _LivenessStep { lookCenter, turn, verifying, passed, failed }

enum AttendanceSessionType { timeIn, timeOut }

class AttendanceFaceVerificationScreen extends StatefulWidget {
  const AttendanceFaceVerificationScreen({
    super.key,
    required this.event,
    this.studentName,
    this.hasTimeIn = false,
    this.hasTimeOut = false,
  });

  final EventItem event;
  final String? studentName;
  final bool hasTimeIn;
  final bool hasTimeOut;

  @override
  State<AttendanceFaceVerificationScreen> createState() =>
      _AttendanceFaceVerificationScreenState();
}

class _AttendanceFaceVerificationScreenState
    extends State<AttendanceFaceVerificationScreen>
    with SingleTickerProviderStateMixin {
  static const double frontalYawMax = 0.15;
  static const int frontalHoldFrames = 2;
  static const double turnYawMin = 0.18;
  static const int turnHoldFrames = 1;
  static const double wrongWayYaw = 0.15;
  static const Duration challengeTimeout = Duration(seconds: 20);
  static const Duration captureInterval = Duration(milliseconds: 30);

  CameraController? _camera;
  Position? _position;

  bool _cameraReady = false;
  bool _running = false;
  bool _analyzing = false;
  bool _disposed = false;

  late bool _hasTimeIn;
  late bool _hasTimeOut;
  late AttendanceSessionType _currentSession;

  String _direction = 'left';
  String? _challengeNonce;
  String? _challengeSessionId;
  String? _error;
  String? _hint;

  _LivenessStep _step = _LivenessStep.lookCenter;

  XFile? _centerFrame;
  XFile? _turnedFrame;

  double? _centerYaw;
  int _holdCount = 0;
  int _turnHoldCount = 0;
  double _holdProgress = 0.0;
  double _turnProgress = 0.0;

  DateTime? _challengeStartTime;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _hasTimeIn = widget.hasTimeIn;
    _hasTimeOut = widget.hasTimeOut;

    _currentSession = !_hasTimeIn
        ? AttendanceSessionType.timeIn
        : AttendanceSessionType.timeOut;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _prepareAndStartParallel();
  }

  /// High-speed parallel initialization for Camera, Geolocation, and Challenge API
  Future<void> _prepareAndStartParallel() async {
    try {
      if (widget.event.id == null) {
        throw Exception('Invalid event ID.');
      }

      if (_hasTimeIn && _hasTimeOut) {
        throw Exception('Attendance is already complete for this event.');
      }

      // Execute Camera, Location, and Liveness Challenge in parallel
      final results = await Future.wait([
        _initCameraFast(),
        _getFastPosition(),
        AttendanceService.instance.requestLivenessChallenge(
          eventId: widget.event.id!,
        ),
      ]);

      if (_disposed) return;

      _position = results[1] as Position?;
      if (_position != null) {
        _checkGeofence(_position!);
      }

      final challengeResult = results[2] as LivenessChallengeResult;

      if (!challengeResult.success || challengeResult.challenge == null) {
        throw Exception(challengeResult.message);
      }

      final challenge = challengeResult.challenge!;
      _direction = challenge.direction;
      _challengeNonce = challenge.nonce;
      _challengeSessionId = challenge.sessionId;

      await _startChallenge();
    } catch (e) {
      if (!mounted || _disposed) return;
      _fail(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _initCameraFast() async {
    final cameraPerm = await Permission.camera.request();
    if (!cameraPerm.isGranted) {
      throw Exception('Camera permission is required.');
    }

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

    _camera = controller;
    if (mounted) {
      setState(() {
        _cameraReady = true;
      });
    }
  }

  Future<Position?> _getFastPosition() async {
    bool enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return null;

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      return null;
    }

    // Attempt instant last-known position first to skip GPS lag
    final lastKnown = await Geolocator.getLastKnownPosition();
    if (lastKnown != null) {
      return lastKnown;
    }

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 4),
      ),
    );
  }

  void _checkGeofence(Position pos) {
    if (!widget.event.geofenceEnabled) return;
    final lat = widget.event.latitude;
    final lng = widget.event.longitude;
    final rad = widget.event.geofenceRadius;

    if (lat == null || lng == null || rad <= 0) return;

    final dist = Geolocator.distanceBetween(pos.latitude, pos.longitude, lat, lng);
    if (dist > rad) {
      final remaining = (dist - rad).round();
      throw Exception('Outside event area. Move $remaining m closer.');
    }
  }

  Future<void> _startChallenge() async {
    final controller = _camera;
    if (_running || controller == null || !controller.value.isInitialized || _disposed) {
      return;
    }

    _resetChallenge();

    setState(() {
      _running = true;
      _error = null;
      _step = _LivenessStep.lookCenter;
    });

    while (mounted &&
        !_disposed &&
        _running &&
        _step != _LivenessStep.verifying &&
        _step != _LivenessStep.passed &&
        _step != _LivenessStep.failed) {
      if (!_analyzing) {
        await _captureAndAnalyze();
      }
      if (!mounted || _disposed || !_running) break;
      await Future<void>.delayed(captureInterval);
    }
  }

  void _resetChallenge() {
    _centerFrame = null;
    _turnedFrame = null;
    _centerYaw = null;
    _holdCount = 0;
    _turnHoldCount = 0;
    _holdProgress = 0.0;
    _turnProgress = 0.0;
    _challengeStartTime = null;
    _hint = null;
  }

  Future<void> _captureAndAnalyze() async {
    if (_analyzing || !_running || _disposed) return;
    final controller = _camera;
    if (controller == null || !controller.value.isInitialized || controller.value.isTakingPicture) {
      return;
    }

    _analyzing = true;

    try {
      final frame = await controller.takePicture();
      if (!mounted || _disposed || !_running) return;

      final result = await AttendanceService.instance.analyzeLivenessFrame(
        frame: frame,
      );
      if (!mounted || _disposed || !_running) return;

      if (!result.success || !result.faceDetected) {
        _resetProgress('Position face inside frame');
        return;
      }

      final yaw = result.yaw;
      if (yaw == null) {
        _resetProgress('Keep face clearly visible');
        return;
      }

      await _processLivenessFrame(frame: frame, yaw: yaw);
    } catch (_) {
      _resetProgress('Analyzing orientation...');
    } finally {
      _analyzing = false;
    }
  }

  void _resetProgress(String hint) {
    if (!mounted) return;
    setState(() {
      _holdCount = 0;
      _turnHoldCount = 0;
      _holdProgress = 0.0;
      _turnProgress = 0.0;
      _hint = hint;
    });
  }

  Future<void> _processLivenessFrame({
    required XFile frame,
    required double yaw,
  }) async {
    switch (_step) {
      case _LivenessStep.lookCenter:
        if (yaw.abs() > frontalYawMax) {
          _resetProgress('Look straight at the camera.');
          return;
        }

        _holdCount++;
        setState(() {
          _hint = null;
          _holdProgress = (_holdCount / frontalHoldFrames).clamp(0.0, 1.0);
        });

        if (_holdCount >= frontalHoldFrames) {
          _centerFrame = frame;
          _centerYaw = yaw;
          _challengeStartTime = DateTime.now();
          _turnHoldCount = 0;
          setState(() {
            _step = _LivenessStep.turn;
            _holdProgress = 1.0;
          });
        }
        break;

      case _LivenessStep.turn:
        final startTime = _challengeStartTime ?? DateTime.now();
        if (DateTime.now().difference(startTime) > challengeTimeout) {
          _prepareAndStartParallel();
          setState(() {
            _hint = "Time ran out. Let's try again.";
          });
          return;
        }

        final centerYaw = _centerYaw ?? 0.0;
        final signedDelta = yaw - centerYaw;
        final turned = _direction == 'left' ? signedDelta : -signedDelta;

        if (turned <= -wrongWayYaw) {
          setState(() {
            _turnHoldCount = 0;
            _turnProgress = 0.0;
            _hint = 'Turn to your $_direction, not the other way.';
          });
          return;
        }

        final progress = (turned / turnYawMin).clamp(0.0, 1.0);
        setState(() {
          _hint = null;
          _turnProgress = progress;
        });

        if (turned >= turnYawMin) {
          _turnHoldCount++;
          if (_turnHoldCount >= turnHoldFrames) {
            _turnedFrame = frame;
            await _submitAttendance();
          }
        } else {
          _turnHoldCount = 0;
        }
        break;

      case _LivenessStep.verifying:
      case _LivenessStep.passed:
      case _LivenessStep.failed:
        break;
    }
  }

  Future<void> _submitAttendance() async {
    final eventId = widget.event.id;
    final pos = _position ?? Position(longitude: 0, latitude: 0, timestamp: DateTime.now(), accuracy: 0, altitude: 0, altitudeAccuracy: 0, heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0);
    if (eventId == null || _centerFrame == null || _turnedFrame == null) {
      return;
    }

    setState(() {
      _running = false;
      _step = _LivenessStep.verifying;
      _hint = null;
    });

    final result = await AttendanceService.instance.mobileCheckIn(
      eventId: eventId,
      latitude: pos.latitude,
      longitude: pos.longitude,
      locationAccuracy: pos.accuracy,
      centerFrame: _centerFrame!,
      turnedFrame: _turnedFrame!,
      challengeNonce: _challengeNonce ?? '',
      sessionId: _challengeSessionId ?? '',
    );

    if (!mounted || _disposed) return;

    if (!result.success) {
      _fail(result.message);
      return;
    }

    setState(() {
      _step = _LivenessStep.passed;
      if (_currentSession == AttendanceSessionType.timeIn) {
        _hasTimeIn = true;
      } else {
        _hasTimeOut = true;
      }
    });

    // Show Welcome Popup Modal
    await _showWelcomeModal();

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  /// Displays the Pop-Up Welcome Modal on completion
  Future<void> _showWelcomeModal() async {
    if (!mounted) return;

    Timer? timer;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        timer = Timer(const Duration(seconds: 2), () {
          if (Navigator.canPop(dialogContext)) {
            Navigator.pop(dialogContext);
          }
        });

        final nameText = widget.studentName != null && widget.studentName!.isNotEmpty
            ? widget.studentName!
            : 'Student';

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
                Text(
                  'Welcome, $nameText!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Attendance ${_currentSession == AttendanceSessionType.timeIn ? "Time-In" : "Time-Out"} verified successfully.',
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
                      timer?.cancel();
                      Navigator.pop(dialogContext);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Continue',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
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

    timer?.cancel();
  }

  void _fail(String message) {
    if (!mounted || _disposed) return;
    setState(() {
      _running = false;
      _step = _LivenessStep.failed;
      _error = message;
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _disposed = true;
    _running = false;
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.event.name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Text(
              'Face Verification (${_currentSession == AttendanceSessionType.timeIn ? 'Time-In' : 'Time-Out'})',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.event.venue,
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
                      child: _cameraReady && _camera != null && _camera!.value.isInitialized
                          ? FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width: 250,
                                height: 250 * _camera!.value.aspectRatio,
                                child: CameraPreview(_camera!),
                              ),
                            )
                          : const Center(
                              child: CircularProgressIndicator(color: AppColors.gold),
                            ),
                    ),
                  ),
                  if (_step == _LivenessStep.turn)
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
                          _direction == 'left' ? Icons.arrow_back : Icons.arrow_forward,
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
            if (_error != null && _step == _LivenessStep.failed)
              Padding(
                padding: const EdgeInsets.only(bottom: 12, left: 20, right: 20),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              )
            else if (_hint != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _hint!,
                  style: const TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            _buildProgressBar(),
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
      case _LivenessStep.lookCenter:
        text = 'Look straight at the camera';
        icon = Icons.remove_red_eye_outlined;
        break;
      case _LivenessStep.turn:
        text = 'Turn your head to your $_direction';
        icon = _direction == 'left' ? Icons.arrow_back : Icons.arrow_forward;
        break;
      case _LivenessStep.verifying:
        text = 'Verifying attendance...';
        icon = Icons.refresh;
        spin = true;
        break;
      case _LivenessStep.passed:
        text = 'Verified successfully!';
        icon = Icons.check_circle_outline;
        break;
      case _LivenessStep.failed:
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
    double progress = _step == _LivenessStep.lookCenter ? _holdProgress : _turnProgress;
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