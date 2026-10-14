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

  CameraController? _camera;
  Position? _position;

  bool _cameraReady = false;
  bool _disposed = false;
  bool _isProcessing = false;

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

  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _hasTimeIn = widget.hasTimeIn;
    _hasTimeOut = widget.hasTimeOut;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _currentSession = _determineCurrentSession();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_currentSession == null) {
        _showClosedDialog(
            'Attendance is currently closed or already completed for this event.');
      } else {
        _initializeAndRunSequence();
      }
    });
  }

  // --------------------------------------------------------------------------
  // STRICT ADMIN WINDOW ROUTING (ZERO MIDPOINT CALCULATION)
  // --------------------------------------------------------------------------

  AttendanceSessionType? _determineCurrentSession() {
    final now = DateTime.now();

    DateTime? parseTimeString(String? str) {
      if (str == null) return null;
      final text = str.trim();
      if (text.isEmpty || text.toLowerCase() == 'null') return null;
      try {
        final uppercase = text.toUpperCase();
        if (uppercase.contains('AM') || uppercase.contains('PM')) {
          final parsed = DateFormat('h:mm a').parseLoose(uppercase);
          return DateTime(
              now.year, now.month, now.day, parsed.hour, parsed.minute, parsed.second);
        }
        final parts = text.split(':');
        if (parts.length >= 2) {
          final hour = int.parse(parts[0].trim());
          final minute = int.parse(parts[1].trim());
          final second =
              parts.length >= 3 ? int.parse(parts[2].trim().split(' ')[0]) : 0;
          return DateTime(
              now.year, now.month, now.day, hour, minute, second);
        }
      } catch (_) {}
      return null;
    }

    String? getRawVal(List<String> keys) {
      for (final key in keys) {
        final val = widget.event.raw[key];
        if (val != null) {
          final text = val.toString().trim();
          if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
        }
      }
      return null;
    }

    // 1. Extract Admin Time-In Window Boundaries
    final timeInStart = parseTimeString(getRawVal([
          'time_in_start',
          'timeInStart',
          'time_in_start_time',
          'time_in_begin',
          'start_time',
          'time_in',
          'attendance_start'
        ])) ?? parseTimeString(widget.event.startTime);

    final timeInEnd = parseTimeString(getRawVal([
      'time_in_end',
      'timeInEnd',
      'time_in_end_time',
      'time_in_cutoff',
      'time_in_limit',
      'time_in_to',
      'time_in_close'
    ]));

    // 2. Extract Admin Time-Out Window Boundaries
    final timeOutStart = parseTimeString(getRawVal([
      'time_out_start',
      'timeOutStart',
      'time_out_start_time',
      'time_out_begin',
      'time_out_from',
      'time_out_open'
    ]));

    final timeOutEnd = parseTimeString(getRawVal([
          'time_out_end',
          'timeOutEnd',
          'time_out_end_time',
          'time_out_cutoff',
          'time_out_close',
          'end_time',
          'time_out',
          'attendance_end'
        ])) ?? parseTimeString(widget.event.endTime);

    // ------------------------------------------------------------------------
    // RULE 1: STRICT TIME-IN WINDOW CHECK
    // Every single second inside [timeInStart, timeInEnd] routes to TIME-IN
    // ------------------------------------------------------------------------
    if (timeInStart != null && timeInEnd != null) {
      final inTimeInWindow = (now.isAfter(timeInStart) || now.isAtSameMomentAs(timeInStart)) &&
          (now.isBefore(timeInEnd) || now.isAtSameMomentAs(timeInEnd));

      if (inTimeInWindow && !_hasTimeIn) {
        return AttendanceSessionType.timeIn;
      }
    }

    // ------------------------------------------------------------------------
    // RULE 2: STRICT TIME-OUT WINDOW CHECK
    // Every second inside [timeOutStart, timeOutEnd] routes to TIME-OUT
    // (ALLOWED REGARDLESS OF WHETHER THE STUDENT ATTENDED TIME-IN)
    // ------------------------------------------------------------------------
    if (timeOutStart != null && timeOutEnd != null) {
      final inTimeOutWindow = (now.isAfter(timeOutStart) || now.isAtSameMomentAs(timeOutStart)) &&
          (now.isBefore(timeOutEnd) || now.isAtSameMomentAs(timeOutEnd));

      if (inTimeOutWindow && !_hasTimeOut) {
        return AttendanceSessionType.timeOut;
      }
    }

    // ------------------------------------------------------------------------
    // RULE 3: SINGLE BLOCK / BROAD EVENT FALLBACK (No sub-window cutoffs in JSON)
    // ------------------------------------------------------------------------
    if (timeInStart != null && timeOutEnd != null) {
      final isWithinEvent = (now.isAfter(timeInStart) || now.isAtSameMomentAs(timeInStart)) &&
          (now.isBefore(timeOutEnd) || now.isAtSameMomentAs(timeOutEnd));

      if (isWithinEvent) {
        // If explicit time_in_end passed -> force Time-Out
        if (timeInEnd != null && now.isAfter(timeInEnd)) {
          if (!_hasTimeOut) return AttendanceSessionType.timeOut;
        } 
        // If explicit time_out_start not reached -> force Time-In
        else if (timeOutStart != null && now.isBefore(timeOutStart)) {
          if (!_hasTimeIn) return AttendanceSessionType.timeIn;
        } 
        // Unsplit event block: 1st check-in = Time-In, 2nd check-in = Time-Out
        else {
          if (!_hasTimeIn) return AttendanceSessionType.timeIn;
          if (!_hasTimeOut) return AttendanceSessionType.timeOut;
        }
      }
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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // INITIALIZATION & AUTOMATED CAPTURE SEQUENCE
  // --------------------------------------------------------------------------

  Future<void> _initializeAndRunSequence() async {
    try {
      if (widget.event.id == null) {
        throw Exception('Invalid event ID.');
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
      if (challengeResult.success && challengeResult.challenge != null) {
        _direction = challengeResult.challenge!.direction;
        _challengeNonce = challengeResult.challenge!.nonce;
        _challengeSessionId = challengeResult.challenge!.sessionId;
      } else {
        _direction = 'left';
        _challengeNonce = 'offline-nonce';
        _challengeSessionId = DateTime.now().millisecondsSinceEpoch.toString();
      }

      await _runAutomatedCapture();
    } catch (e) {
      if (!mounted || _disposed) return;
      setState(() {
        _step = _LivenessStep.failed;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
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

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 2),
        ),
      );
    } catch (_) {
      return await Geolocator.getLastKnownPosition();
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

  // --------------------------------------------------------------------------
  // AUTOMATED SNAPSHOT CAPTURE SEQUENCE
  // --------------------------------------------------------------------------

  Future<void> _runAutomatedCapture() async {
    if (_isProcessing ||
        _camera == null ||
        !_camera!.value.isInitialized ||
        _disposed) {
      return;
    }

    _isProcessing = true;

    try {
      setState(() {
        _step = _LivenessStep.lookCenter;
        _hint = 'Hold still, capturing center face...';
      });

      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (!mounted || _disposed) return;

      _centerFrame = await _camera!.takePicture();

      setState(() {
        _step = _LivenessStep.turn;
        _hint = 'Now turn your head towards $_direction...';
      });

      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (!mounted || _disposed) return;

      _turnedFrame = await _camera!.takePicture();

      await _submitAttendance();
    } catch (e) {
      debugPrint('Capture sequence error: $e');
      if (mounted && !_disposed) {
        setState(() {
          _step = _LivenessStep.failed;
          _error = 'Camera capture failed. Please retry.';
        });
      }
    } finally {
      _isProcessing = false;
    }
  }

  // --------------------------------------------------------------------------
  // SUBMISSION TO BACKEND
  // --------------------------------------------------------------------------

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
      throw Exception('Missing camera frames or event reference.');
    }

    setState(() {
      _step = _LivenessStep.verifying;
      _hint = 'Verifying attendance with server...';
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

      if (result.networkUnavailable) {
        final offlineQueueResult =
            await AttendanceService.instance.queueOfflineAttendance(
          eventId: eventId,
          latitude: pos.latitude,
          longitude: pos.longitude,
          locationAccuracy: pos.accuracy,
          attendanceTime: DateTime.now(),
          centerFrame: _centerFrame!,
          turnedFrame: _turnedFrame!,
          livenessDirection: _direction,
          type: typeStr,
        );

        if (!mounted || _disposed) return;

        if (!offlineQueueResult.success) {
          _fail(offlineQueueResult.message);
          return;
        }
      } else {
        _fail(result.message);
        _showClosedDialog(result.message);
        return;
      }
    }

    setState(() {
      _step = _LivenessStep.passed;
    });

    await _showSuccessModal();

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _showSuccessModal() async {
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
                  '$sessionText recorded successfully.',
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
                      style: TextStyle(fontWeight: FontWeight.bold),
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
      _step = _LivenessStep.failed;
      _error = message;
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _disposed = true;
    _camera?.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // UI BUILD
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isDark = themeController.isDarkMode;
    final sessionTitle = _currentSession == AttendanceSessionType.timeIn
        ? 'Time-In'
        : 'Time-Out';

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
            Positioned(
              bottom: 30,
              child: ElevatedButton(
                onPressed: _isProcessing
                    ? null
                    : () {
                        setState(() {
                          _isProcessing = false;
                        });
                        _runAutomatedCapture();
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: brandGold,
                  foregroundColor: brandNavy,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                child: const Text(
                  'Retry / Capture Now',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
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
        text = 'Look straight at camera';
        icon = Icons.remove_red_eye_outlined;
        break;
      case _LivenessStep.turn:
        text = 'Turn head towards $_direction';
        icon = _direction == 'left' ? Icons.arrow_back : Icons.arrow_forward;
        break;
      case _LivenessStep.verifying:
        text = 'Submitting attendance...';
        icon = Icons.refresh;
        spin = true;
        break;
      case _LivenessStep.passed:
        text = 'Recorded successfully!';
        icon = Icons.check_circle_outline;
        break;
      case _LivenessStep.failed:
        text = 'Recording failed';
        icon = Icons.error_outline;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFFFF8E7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? const Color(0xFF334155)
              : brandGold.withValues(alpha: 0.6),
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
}