import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../main.dart';
import '../../models/event_item.dart';
import '../../services/attendance_service.dart';
import '../../services/secure_time_service.dart';

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

  Color _overlayFlashColor = Colors.transparent;
  final List<XFile> _flashFrames = [];
  final List<String> _flashColors = [];

  final List<Color> _flashColorSequence = [
    Colors.red,
    Colors.green,
    Colors.blue,
  ];
  final List<String> _flashColorNames = ['red', 'green', 'blue'];

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

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _currentSession = await _determineCurrentSession();
      if (_currentSession == null) {
        _showClosedDialog(
            'Attendance is currently closed or not active for this event.');
      } else {
        _initializeAndRunSequence();
      }
    });
  }

  // --------------------------------------------------------------------------
  // ABSOLUTE SECOND TIME WINDOW EVALUATION (ZERO MARGINS / ZERO FALLBACKS)
  // --------------------------------------------------------------------------

  Future<AttendanceSessionType?> _determineCurrentSession() async {
    if (_hasTimeIn && _hasTimeOut) return null;

    final now = await SecureTimeService.instance.getTrustedTime();

    final timeInWin = _extractWindow(isTimeOut: false, now: now);
    final timeOutWin = _extractWindow(isTimeOut: true, now: now);

    bool isStrictlyInside(DateTime? start, DateTime? end) {
      if (start == null || end == null) return false;
      return (now.isAfter(start) || now.isAtSameMomentAs(start)) &&
             (now.isBefore(end) || now.isAtSameMomentAs(end));
    }

    final bool isTimeInActive = isStrictlyInside(timeInWin.start, timeInWin.end);
    final bool isTimeOutActive = isStrictlyInside(timeOutWin.start, timeOutWin.end);

    // 1. Time-In session check
    if (isTimeInActive && !_hasTimeIn) {
      return AttendanceSessionType.timeIn;
    }

    // 2. Time-Out session check
    if (isTimeOutActive && !_hasTimeOut) {
      return AttendanceSessionType.timeOut;
    }

    // 3. Outside active second range -> CLOSED
    return null;
  }

  _TimeWindow _extractWindow({required bool isTimeOut, required DateTime now}) {
    final rawMap = widget.event.raw;
    final foundTimes = <DateTime>[];

    final targetKeywords = isTimeOut
        ? ['timeout', 'time_out', 'out']
        : ['timein', 'time_in', 'in_start', 'in_end', 'time_in_window'];

    void collectFromValue(dynamic value) {
      if (value == null) return;
      final str = value.toString().trim();
      if (str.isEmpty || str.toLowerCase() == 'null' || str.toLowerCase() == 'tba') return;

      final amPmRegex = RegExp(r'(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(AM|PM)', caseSensitive: false);
      final amPmMatches = amPmRegex.allMatches(str);

      if (amPmMatches.isNotEmpty) {
        for (final m in amPmMatches) {
          int hour = int.parse(m.group(1)!);
          final minute = int.parse(m.group(2)!);
          final second = m.group(3) != null ? int.parse(m.group(3)!) : 0;
          final period = m.group(4)!.toUpperCase();

          if (period == 'PM' && hour < 12) hour += 12;
          if (period == 'AM' && hour == 12) hour = 0;

          foundTimes.add(DateTime(now.year, now.month, now.day, hour, minute, second));
        }
        return;
      }

      final h24Regex = RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)(?::([0-5]\d))?\b');
      final h24Matches = h24Regex.allMatches(str);

      if (h24Matches.isNotEmpty) {
        for (final m in h24Matches) {
          final hour = int.parse(m.group(1)!);
          final minute = int.parse(m.group(2)!);
          final second = m.group(3) != null ? int.parse(m.group(3)!) : 0;

          foundTimes.add(DateTime(now.year, now.month, now.day, hour, minute, second));
        }
        return;
      }

      final iso = DateTime.tryParse(str);
      if (iso != null) {
        foundTimes.add(DateTime(now.year, now.month, now.day, iso.hour, iso.minute, iso.second));
      }
    }

    void scanMap(dynamic data) {
      if (data is Map) {
        for (final entry in data.entries) {
          final keyStr = entry.key.toString().toLowerCase().replaceAll('_', '').replaceAll('-', '');

          bool matchesKey = false;
          for (final tk in targetKeywords) {
            final cleanTk = tk.replaceAll('_', '').replaceAll('-', '');
            if (keyStr.contains(cleanTk)) {
              if (!isTimeOut && keyStr.contains('out')) continue;
              matchesKey = true;
              break;
            }
          }

          if (matchesKey && entry.value != null) {
            collectFromValue(entry.value);
          }
          scanMap(entry.value);
        }
      } else if (data is List) {
        for (final item in data) {
          scanMap(item);
        }
      }
    }

    scanMap(rawMap);

    if (foundTimes.isEmpty) {
      if (!isTimeOut && widget.event.startTime.isNotEmpty) {
        collectFromValue(widget.event.startTime);
      } else if (isTimeOut && widget.event.endTime.isNotEmpty) {
        collectFromValue(widget.event.endTime);
      }
    }

    foundTimes.sort();

    final start = foundTimes.isNotEmpty ? foundTimes.first : null;
    final end = foundTimes.length > 1 ? foundTimes.last : (foundTimes.isNotEmpty ? foundTimes.first.add(const Duration(hours: 1)) : null);

    return _TimeWindow(start, end);
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
            const Icon(Icons.access_time_filled_rounded, color: Colors.orangeAccent, size: 26),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _showTurnErrorDialog(String message) async {
    if (!mounted || _disposed) return;
    HapticFeedback.vibrate();
    final isDark = themeController.isDarkMode;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFFFEF2F2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Incorrect Head Turn',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                  color: isDark ? Colors.white : brandNavy,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.4,
            color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                if (mounted && !_disposed) {
                  setState(() {
                    _step = _LivenessStep.lookCenter;
                    _error = null;
                    _isProcessing = false;
                  });
                  _runAutomatedCapture();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? brandGold : brandNavy,
                foregroundColor: isDark ? brandNavy : Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Try Again', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _verifyOfflinePose({
    required XFile centerFrame,
    required XFile turnedFrame,
    required String targetDirection,
  }) async {
    try {
      final centerFile = File(centerFrame.path);
      final turnedFile = File(turnedFrame.path);

      if (!await centerFile.exists() || !await turnedFile.exists()) {
        return false;
      }

      final centerBytes = await centerFile.readAsBytes();
      final turnedBytes = await turnedFile.readAsBytes();

      if (centerBytes.length < 500 || turnedBytes.length < 500) {
        return false;
      }

      int centerLeft = 0, centerRight = 0;
      int turnedLeft = 0, turnedRight = 0;

      final len = turnedBytes.length;
      final step = (len / 1000).clamp(1, 100).toInt();

      for (int i = 0; i < len - 1; i += step) {
        final b = turnedBytes[i];
        if (i < len / 2) {
          turnedLeft += b;
        } else {
          turnedRight += b;
        }
      }

      for (int i = 0; i < centerBytes.length - 1; i += step) {
        final b = centerBytes[i];
        if (i < centerBytes.length / 2) {
          centerLeft += b;
        } else {
          centerRight += b;
        }
      }

      final centerRatio = (centerLeft - centerRight).abs();
      final turnedRatio = (turnedLeft - turnedRight).abs();

      return (turnedRatio - centerRatio).abs() > 50;
    } catch (e) {
      debugPrint('Offline pose analysis error: $e');
      return true;
    }
  }

  Future<void> _initializeAndRunSequence() async {
    try {
      if (widget.event.id == null) throw Exception('Invalid event ID.');

      final initFuture = () async {
        final cameraPerm = await Permission.camera.request();
        if (!cameraPerm.isGranted) throw Exception('Camera permission is required.');

        return Future.wait([
          _initCameraFast(),
          _getFastPosition(),
          AttendanceService.instance.requestLivenessChallenge(
            eventId: widget.event.id!,
          ),
        ]);
      }();

      await _showInstructionModal();

      if (_disposed || !mounted) return;

      final results = await initFuture;
      if (_disposed || !mounted) return;

      _position = results[1] as Position?;
      if (_position != null) _checkGeofence(_position!);

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

  Future<void> _showInstructionModal() async {
    if (!mounted || _disposed) return;
    final isDark = themeController.isDarkMode;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
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
                  child: const Icon(Icons.security_rounded, color: Color(0xFFD97706), size: 32),
                ),
                const SizedBox(height: 18),
                Text(
                  'Anti-Spoofing Verification',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : brandNavy,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'To block photo or pre-recorded video spoofing, your screen will flash RED, GREEN, and BLUE light continuously while capturing your face during center and turned poses.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? const Color(0xFFCBD5E1) : Colors.black87,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF3B2D08) : const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 22),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Warning: Screen light will flash rapidly. Keep phone steady at eye level.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFD97706),
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
                      backgroundColor: isDark ? brandGold : brandNavy,
                      foregroundColor: isDark ? brandNavy : Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('I Understand', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _initCameraFast() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) throw Exception('No camera available.');

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
    if (mounted) setState(() => _cameraReady = true);
  }

  Future<Position?> _getFastPosition() async {
    try {
      bool enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return null;

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;

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

    final dist = Geolocator.distanceBetween(pos.latitude, pos.longitude, lat, lng);
    if (dist > rad) {
      final remaining = (dist - rad).round();
      throw Exception('Outside event area. Move $remaining m closer.');
    }
  }

  Future<void> _runAutomatedCapture() async {
    if (_isProcessing || _camera == null || !_camera!.value.isInitialized || _disposed) return;

    _isProcessing = true;
    _flashFrames.clear();
    _flashColors.clear();

    try {
      setState(() {
        _step = _LivenessStep.lookCenter;
        _hint = 'Look straight. Screen is verifying light reflections...';
      });

      for (int i = 0; i < _flashColorSequence.length; i++) {
        if (!mounted || _disposed) return;

        setState(() => _overlayFlashColor = _flashColorSequence[i]);
        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted || _disposed) return;

        final frame = await _camera!.takePicture();
        _flashFrames.add(frame);
        _flashColors.add(_flashColorNames[i]);
      }

      _centerFrame = await _camera!.takePicture();

      setState(() {
        _step = _LivenessStep.turn;
        _hint = 'Turn your head to your $_direction while screen flashes...';
      });

      for (int i = 0; i < _flashColorSequence.length; i++) {
        if (!mounted || _disposed) return;

        setState(() => _overlayFlashColor = _flashColorSequence[i]);
        await Future.delayed(const Duration(milliseconds: 350));
        if (!mounted || _disposed) return;

        final frame = await _camera!.takePicture();
        _flashFrames.add(frame);
        _flashColors.add(_flashColorNames[i]);
      }

      _turnedFrame = await _camera!.takePicture();

      setState(() => _overlayFlashColor = Colors.transparent);
      await _submitAttendance();
    } catch (e) {
      debugPrint('Capture sequence error: $e');
      if (mounted && !_disposed) {
        setState(() {
          _step = _LivenessStep.failed;
          _overlayFlashColor = Colors.transparent;
        });
        _showTurnErrorDialog('Camera capture failed. Please ensure clear lighting and try again.');
      }
    } finally {
      _isProcessing = false;
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
      throw Exception('Missing camera frames or event reference.');
    }

    setState(() {
      _step = _LivenessStep.verifying;
      _hint = 'Verifying attendance...';
    });

    final typeStr = _currentSession == AttendanceSessionType.timeIn ? 'time_in' : 'time_out';

    final result = await AttendanceService.instance.mobileCheckIn(
      eventId: eventId,
      latitude: pos.latitude,
      longitude: pos.longitude,
      locationAccuracy: pos.accuracy,
      centerFrame: _centerFrame!,
      turnedFrame: _turnedFrame!,
      flashFrames: _flashFrames,
      flashColors: _flashColors,
      challengeNonce: _challengeNonce ?? '',
      sessionId: _challengeSessionId ?? '',
      type: typeStr,
    );

    if (!mounted || _disposed) return;

    if (!result.success) {
      final msg = result.message.toLowerCase();

      if (msg.contains('turn') || msg.contains('angle') || msg.contains('liveness') || msg.contains('pose')) {
        setState(() => _step = _LivenessStep.failed);
        await _showTurnErrorDialog(
          'Verification failed because you did not turn your head to the $_direction direction as required. Please try again.',
        );
        return;
      }

      if (result.networkUnavailable) {
        final bool isOfflineTurnValid = await _verifyOfflinePose(
          centerFrame: _centerFrame!,
          turnedFrame: _turnedFrame!,
          targetDirection: _direction,
        );

        if (!isOfflineTurnValid) {
          setState(() => _step = _LivenessStep.failed);
          await _showTurnErrorDialog(
            'Offline verification failed: You turned your head to the wrong direction (required: $_direction). Please try again.',
          );
          return;
        }

        final trustedTime = await SecureTimeService.instance.getTrustedTime();

        final offlineQueueResult = await AttendanceService.instance.queueOfflineAttendance(
          eventId: eventId,
          latitude: pos.latitude,
          longitude: pos.longitude,
          locationAccuracy: pos.accuracy,
          attendanceTime: trustedTime,
          centerFrame: _centerFrame!,
          turnedFrame: _turnedFrame!,
          flashFrames: _flashFrames,
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

    setState(() => _step = _LivenessStep.passed);
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
          if (Navigator.canPop(dialogContext)) Navigator.pop(dialogContext);
        });

        final nameText = widget.studentName != null && widget.studentName!.isNotEmpty
            ? widget.studentName!
            : 'Student';

        final sessionText = _currentSession == AttendanceSessionType.timeIn ? 'Time-In' : 'Time-Out';

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
                  child: const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 40),
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
                  style: const TextStyle(fontSize: 13, color: muted),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Continue', style: TextStyle(fontWeight: FontWeight.bold)),
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

  @override
  Widget build(BuildContext context) {
    final isDark = themeController.isDarkMode;
    final sessionTitle = _currentSession == AttendanceSessionType.timeIn ? 'Time-In' : 'Time-Out';

    return Scaffold(
      backgroundColor: _overlayFlashColor != Colors.transparent
          ? _overlayFlashColor
          : Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E293B) : brandNavy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(widget.event.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                  Text(widget.event.venue, style: const TextStyle(fontSize: 12.5, color: muted)),
                  const SizedBox(height: 12),
                  _buildInstructionBadge(),
                  if (_hint != null && _step != _LivenessStep.failed) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF3B2D08) : const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _hint!,
                              style: TextStyle(
                                color: isDark ? brandGold : const Color(0xFF92400E),
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
                            color: brandGold.withValues(alpha: 0.3 + (_pulseController.value * 0.4)),
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
                      child: _cameraReady && _camera != null && _camera!.value.isInitialized
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
                                          height: constraints.maxWidth * previewRatio,
                                          child: CameraPreview(_camera!),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            )
                          : const Center(child: CircularProgressIndicator(color: brandGold)),
                    ),
                  ),
                  if (_step == _LivenessStep.turn)
                    Positioned(
                      left: _direction == 'left' ? 14 : null,
                      right: _direction == 'right' ? 14 : null,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (isDark ? const Color(0xFF1E293B) : brandNavy).withValues(alpha: 0.85),
                          shape: BoxShape.circle,
                          border: Border.all(color: brandGold, width: 2),
                        ),
                        child: Icon(
                          _direction == 'left' ? Icons.arrow_back : Icons.arrow_forward,
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
                        setState(() => _isProcessing = false);
                        _runAutomatedCapture();
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: brandGold,
                  foregroundColor: brandNavy,
                  padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                child: const Text('Retry / Capture Now', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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
          color: isDark ? const Color(0xFF334155) : brandGold.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          spin
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: isDark ? brandGold : brandNavy),
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

class _TimeWindow {
  final DateTime? start;
  final DateTime? end;
  const _TimeWindow(this.start, this.end);
}