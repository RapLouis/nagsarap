import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../main.dart';
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
  static const Color brandNavy = Color(0xFF080878);
  static const Color brandGold = Color(0xFFFFC800);
  static const Color muted = Color(0xFF94A3B8);

  // Speed & Flexibility Tuning
  static const double frontalYawMax = 0.35; // High tolerance for center position
  static const int frontalHoldFrames = 1;   // Instant center capture
  static const double turnYawMin = 0.10;    // Easy head turn threshold
  static const int turnHoldFrames = 1;     // Instant turn capture
  static const double wrongWayYaw = 0.25;   // Flexible opposite yaw tolerance
  static const Duration challengeTimeout = Duration(seconds: 15);
  static const Duration captureInterval = Duration(milliseconds: 10); // Fast camera loop

  CameraController? _camera;
  Position? _position;

  bool _cameraReady = false;
  bool _running = false;
  bool _analyzing = false;
  bool _disposed = false;

  late bool _hasTimeIn;
  late bool _hasTimeOut;
  AttendanceSessionType? _currentSession;

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

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _currentSession = _determineCurrentSession();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_currentSession == null) {
        _showClosedDialog('Attendance is currently closed for this event.');
      } else {
        _prepareAndStartSequential();
      }
    });
  }

  AttendanceSessionType? _determineCurrentSession() {
    final now = DateTime.now();
    final startTime = _parseEventTime(widget.event.startTime);
    final endTime = _parseEventTime(widget.event.endTime);

    if (startTime != null && endTime != null) {
      final midpoint = startTime.add(endTime.difference(startTime) ~/ 2);
      final timeInStart = startTime.subtract(const Duration(minutes: 30));

      if (_hasTimeIn) {
        if (!_hasTimeOut &&
            now.isAfter(midpoint) &&
            now.isBefore(endTime.add(const Duration(minutes: 30)))) {
          return AttendanceSessionType.timeOut;
        }
        return null;
      }

      if (now.isAfter(timeInStart) && now.isBefore(midpoint)) {
        return AttendanceSessionType.timeIn;
      } else if (now.isAfter(midpoint) &&
          now.isBefore(endTime.add(const Duration(minutes: 30)))) {
        return AttendanceSessionType.timeOut;
      }

      return null;
    }

    if (_hasTimeIn && !_hasTimeOut) return AttendanceSessionType.timeOut;
    if (!_hasTimeIn) return AttendanceSessionType.timeIn;
    return null;
  }

  DateTime? _parseEventTime(String timeStr) {
    final clean = timeStr.trim();
    if (clean.isEmpty) return null;

    const formats = ['HH:mm:ss', 'HH:mm', 'h:mm a', 'hh:mm a'];
    for (final format in formats) {
      try {
        final parsed = DateFormat(format, 'en_US').parseLoose(clean);
        final now = DateTime.now();
        return DateTime(
          now.year,
          now.month,
          now.day,
          parsed.hour,
          parsed.minute,
          parsed.second,
        );
      } catch (_) {}
    }
    return null;
  }

  Future<void> _showClosedDialog(String message) async {
    if (!mounted) return;
    final isDark = themeController.isDarkMode;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.access_time_filled_rounded,
                color: Colors.orangeAccent, size: 26),
            const SizedBox(width: 10),
            Text(
              'Attendance Closed',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: isDark ? Colors.white : brandNavy,
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: TextStyle(
            fontSize: 14,
            color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? brandGold : brandNavy,
              foregroundColor: isDark ? brandNavy : Colors.white,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child:
                const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _prepareAndStartSequential() async {
    try {
      if (widget.event.id == null) {
        throw Exception('Invalid event ID.');
      }

      if (_hasTimeIn && _hasTimeOut) {
        throw Exception('Attendance is already complete for this event.');
      }

      final cameraPerm = await Permission.camera.request();
      if (!cameraPerm.isGranted) {
        throw Exception('Camera permission is required.');
      }

      final cameraFuture = _initCameraFast();
      final locationFuture = _getFastPosition();
      final challengeFuture =
          AttendanceService.instance.requestLivenessChallenge(
        eventId: widget.event.id!,
      );

      final results = await Future.wait([
        cameraFuture,
        locationFuture,
        challengeFuture,
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
    if (mounted) {
      setState(() {
        _cameraReady = true;
      });
    }
  }

  Future<Position?> _getFastPosition() async {
    try {
      bool enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return null;

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }

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
    } catch (_) {
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
    }
  }

  void _checkGeofence(Position pos) {
    if (!widget.event.geofenceEnabled) return;
    final lat = widget.event.latitude;
    final lng = widget.event.longitude;
    final rad = widget.event.geofenceRadius;

    if (lat == null || lng == null || rad <= 0) return;

    final dist =
        Geolocator.distanceBetween(pos.latitude, pos.longitude, lat, lng);
    if (dist > rad) {
      final remaining = (dist - rad).round();
      throw Exception('Outside event area. Move $remaining m closer.');
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
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture) {
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
        if (mounted) {
          setState(() {
            _hint = 'Position face inside camera view';
          });
        }
        return;
      }

      final yaw = result.yaw ?? 0.0;
      await _processLivenessFrame(frame: frame, yaw: yaw);
    } catch (_) {
      // transient frame retry
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
          if (mounted) {
            setState(() {
              _hint = 'Look towards camera';
            });
          }
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
          _prepareAndStartSequential();
          setState(() {
            _hint = 'Verification timed out. Please try again.';
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
            _hint = 'Turn head towards your $_direction';
          });
          return;
        }

        final progress = (turned.abs() / turnYawMin).clamp(0.0, 1.0);
        setState(() {
          _hint = null;
          _turnProgress = progress;
        });

        if (turned >= turnYawMin || turned.abs() >= turnYawMin) {
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
    final pos = _position ??
        Position(
          longitude: 0,
          latitude: 0,
          timestamp: DateTime.now(),
          accuracy: 0,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        );
    if (eventId == null || _centerFrame == null || _turnedFrame == null) {
      return;
    }

    setState(() {
      _running = false;
      _step = _LivenessStep.verifying;
      _hint = null;
    });

    final typeStr = _currentSession == AttendanceSessionType.timeIn
        ? 'time_in'
        : 'time_out';

    final result = await AttendanceService.instance.mobileCheckIn(
      eventId: eventId,
      latitude: pos.latitude,
      longitude: pos.longitude,
      locationAccuracy: pos.accuracy,
      centerFrame: _centerFrame!,
      turnedFrame: _turnedFrame!,
      challengeNonce: _challengeNonce ?? '',
      sessionId: _challengeSessionId ?? '',
      type: typeStr,
    );

    if (!mounted || _disposed) return;

    if (!result.success) {
      _fail(result.message);
      _showClosedDialog(result.message);
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

    await _showWelcomeModal();

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _showWelcomeModal() async {
    if (!mounted) return;

    Timer? timer;
    final isDark = themeController.isDarkMode;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        timer = Timer(const Duration(seconds: 2), () {
          if (Navigator.canPop(dialogContext)) {
            Navigator.pop(dialogContext);
          }
        });

        final nameText =
            widget.studentName != null && widget.studentName!.isNotEmpty
                ? widget.studentName!
                : 'Student';

        final sessionText = _currentSession == AttendanceSessionType.timeIn
            ? 'Time-In'
            : 'Time-Out';

        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 16,
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
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
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : brandNavy,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$sessionText verified successfully.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: muted,
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
                      backgroundColor: isDark ? brandGold : brandNavy,
                      foregroundColor: isDark ? brandNavy : Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Continue',
                      style: TextStyle(
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
    final isDark = themeController.isDarkMode;
    final sessionTitle = _currentSession == AttendanceSessionType.timeIn
        ? 'Time-In'
        : (_currentSession == AttendanceSessionType.timeOut
            ? 'Time-Out'
            : 'Closed');

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E293B) : brandNavy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.event.name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      body: SafeArea(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 1. Top Section Overlay
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Face Verification ($sessionTitle)',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : brandNavy,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.event.venue,
                    style: const TextStyle(fontSize: 12.5, color: muted),
                  ),
                  const SizedBox(height: 12),
                  _buildInstructionBadge(),
                  if (_error != null && _step == _LivenessStep.failed) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              color: Color(0xFFDC2626), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: Color(0xFF991B1B),
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (_hint != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF3B2D08)
                            : const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded,
                              color: Color(0xFFD97706), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _hint!,
                              style: TextStyle(
                                color: isDark
                                    ? brandGold
                                    : const Color(0xFF92400E),
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // 2. Camera Viewfinder Circle
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
                            color: brandGold.withValues(
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
                      border: Border.all(color: brandGold, width: 4),
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
                                color: brandGold,
                              ),
                            ),
                    ),
                  ),
                  if (_step == _LivenessStep.turn)
                    Positioned(
                      left: _direction == 'left' ? 14 : null,
                      right: _direction == 'right' ? 14 : null,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (isDark ? const Color(0xFF1E293B) : brandNavy)
                              .withValues(alpha: 0.85),
                          shape: BoxShape.circle,
                          border: Border.all(color: brandGold, width: 2),
                        ),
                        child: Icon(
                          _direction == 'left'
                              ? Icons.arrow_back
                              : Icons.arrow_forward,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // 3. Progress Bar
            Positioned(
              bottom: 24,
              child: _buildProgressBar(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionBadge() {
    final isDark = themeController.isDarkMode;
    String text;
    IconData icon;
    bool spin = false;

    switch (_step) {
      case _LivenessStep.lookCenter:
        text = 'Look at camera';
        icon = Icons.remove_red_eye_outlined;
        break;
      case _LivenessStep.turn:
        text = 'Turn head slightly to $_direction';
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
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFFFF8E7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color:
              isDark ? const Color(0xFF334155) : brandGold.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          spin
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: isDark ? brandGold : brandNavy,
                  ),
                )
              : Icon(icon, color: isDark ? brandGold : brandNavy, size: 20),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: isDark ? Colors.white : brandNavy,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    final isDark = themeController.isDarkMode;
    double progress =
        _step == _LivenessStep.lookCenter ? _holdProgress : _turnProgress;

    return SizedBox(
      width: 180,
      height: 6,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: progress,
          backgroundColor:
              isDark ? const Color(0xFF334155) : Colors.grey.shade300,
          valueColor: AlwaysStoppedAnimation<Color>(
            isDark ? brandGold : brandNavy,
          ),
        ),
      ),
    );
  }
}