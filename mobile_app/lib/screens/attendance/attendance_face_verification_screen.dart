import 'dart:async';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../main.dart';
import '../../models/event_item.dart';
import '../../services/attendance_service.dart';
import '../../services/image_compress_service.dart';
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
    this.timeInWindow,
    this.timeOutWindow,
  });

  final EventItem event;
  final String? studentName;
  final bool hasTimeIn;
  final bool hasTimeOut;
  final String? timeInWindow;
  final String? timeOutWindow;

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

  // Minimum head yaw angle (in degrees) required to confirm a left/right turn
  static const double _requiredTurnAngle = 14.0;

  final Random _random = Random();
  CameraController? _camera;
  Position? _position;

  // On-device ML Kit face detector (100% offline capable)
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: false,
      enableLandmarks: false,
      enableContours: false,
      enableTracking: false,
      performanceMode: FaceDetectorMode.fast,
    ),
  );

  bool _cameraReady = false;
  bool _disposed = false;
  bool _isProcessing = false;
  bool _checkingSession = true;

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
  final List<Future<XFile>> _flashCompressFutures = [];
  final List<String> _flashColors = [];

  final List<Color> _flashColorSequence = [
    Colors.red,
    Colors.green,
    Colors.blue,
  ];
  final List<String> _flashColorNames = ['red', 'green', 'blue'];

  _LivenessStep _step = _LivenessStep.lookCenter;

  XFile? _centerFrame;
  Future<XFile>? _centerCompressFuture;
  XFile? _turnedFrame;
  Future<XFile>? _turnedCompressFuture;

  // Limits concurrent native compressions to 2 workers so disk I/O never stalls camera shots
  int _activeCompressJobs = 0;
  final List<Completer<void>> _compressWaiters = [];

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
      final resolved = await _determineCurrentSession();
      if (!mounted || _disposed) return;

      setState(() {
        _currentSession = resolved;
        _checkingSession = false;
      });

      if (resolved == null) {
        _showClosedDialog(
          'Attendance is currently closed or not active for this event.',
        );
      } else {
        _initializeAndRunSequence();
      }
    });
  }

  String _pickRandomDirection() {
    return _random.nextBool() ? 'left' : 'right';
  }

  Future<XFile> _compressPaced(XFile frame) async {
    while (_activeCompressJobs >= 2) {
      final waiter = Completer<void>();
      _compressWaiters.add(waiter);
      await waiter.future;
    }
    _activeCompressJobs++;
    try {
      return await ImageCompressService.compressFrame(frame);
    } finally {
      _activeCompressJobs--;
      if (_compressWaiters.isNotEmpty) {
        _compressWaiters.removeAt(0).complete();
      }
    }
  }

  // --------------------------------------------------------------------------
  // AUTOMATIC SESSION DETECTION (TIME-IN VS TIME-OUT — NO HARDCODED MARGIN)
  // --------------------------------------------------------------------------

  Future<DateTime> _getNormalizedLocalNow() async {
    final deviceNow = DateTime.now();
    try {
      final trusted = await SecureTimeService.instance
          .getTrustedTime()
          .timeout(const Duration(milliseconds: 800));
      final localTrusted = trusted.toLocal();
      if (localTrusted.year >= 2025 &&
          localTrusted.difference(deviceNow).abs() < const Duration(hours: 2)) {
        return localTrusted;
      }
    } catch (_) {}
    return deviceNow;
  }

  Future<AttendanceSessionType?> _determineCurrentSession() async {
    if (_hasTimeIn && _hasTimeOut) return null;

    final now = await _getNormalizedLocalNow();

    final _TimeWindow timeInWin = (widget.timeInWindow != null &&
            widget.timeInWindow!.trim().isNotEmpty)
        ? _parseWindowString(widget.timeInWindow!, now)
        : _extractWindow(isTimeOut: false, now: now);

    final _TimeWindow timeOutWin = (widget.timeOutWindow != null &&
            widget.timeOutWindow!.trim().isNotEmpty)
        ? _parseWindowString(widget.timeOutWindow!, now)
        : _extractWindow(isTimeOut: true, now: now);

    bool isInsideWindow(_TimeWindow win) {
      final start = win.start;
      final end = win.end;
      if (start == null || end == null) return false;

      DateTime adjustedEnd = end;
      if (adjustedEnd.isBefore(start)) {
        adjustedEnd = adjustedEnd.add(const Duration(days: 1));
      }

      return (now.isAfter(start) || now.isAtSameMomentAs(start)) &&
          (now.isBefore(adjustedEnd) || now.isAtSameMomentAs(adjustedEnd));
    }

    final bool isTimeOutActive = isInsideWindow(timeOutWin);
    final bool isTimeInActive = isInsideWindow(timeInWin);

    if (isTimeOutActive && !_hasTimeOut) {
      return AttendanceSessionType.timeOut;
    }

    if (isTimeInActive && !_hasTimeIn) {
      return AttendanceSessionType.timeIn;
    }

    return null;
  }

  DateTime? _parseSingleTime(String input, DateTime now) {
    final str = input.trim();
    if (str.isEmpty ||
        str.toLowerCase() == 'null' ||
        str.toLowerCase() == 'tba') {
      return null;
    }

    final amPmMatch = RegExp(
      r'(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(AM|PM)',
      caseSensitive: false,
    ).firstMatch(str);

    if (amPmMatch != null) {
      int hour = int.parse(amPmMatch.group(1)!);
      final minute = int.parse(amPmMatch.group(2)!);
      final second =
          amPmMatch.group(3) != null ? int.parse(amPmMatch.group(3)!) : 0;
      final period = amPmMatch.group(4)!.toUpperCase();

      if (period == 'PM' && hour < 12) hour += 12;
      if (period == 'AM' && hour == 12) hour = 0;

      return DateTime(now.year, now.month, now.day, hour, minute, second);
    }

    final h24Match = RegExp(
      r'\b([01]?\d|2[0-3]):([0-5]\d)(?::([0-5]\d))?\b',
    ).firstMatch(str);

    if (h24Match != null) {
      final hour = int.parse(h24Match.group(1)!);
      final minute = int.parse(h24Match.group(2)!);
      final second =
          h24Match.group(3) != null ? int.parse(h24Match.group(3)!) : 0;

      return DateTime(now.year, now.month, now.day, hour, minute, second);
    }

    final iso = DateTime.tryParse(str);
    if (iso != null) {
      final local = iso.toLocal();
      return DateTime(
        now.year,
        now.month,
        now.day,
        local.hour,
        local.minute,
        local.second,
      );
    }

    return null;
  }

  _TimeWindow _parseWindowString(String windowStr, DateTime now) {
    final parts = windowStr.split(RegExp(r'[-–]')).map((s) => s.trim()).toList();
    final start = parts.isNotEmpty ? _parseSingleTime(parts[0], now) : null;
    final end = parts.length > 1 ? _parseSingleTime(parts[1], now) : null;
    return _TimeWindow(start, end);
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
      if (str.isEmpty ||
          str.toLowerCase() == 'null' ||
          str.toLowerCase() == 'tba') {
        return;
      }

      if (str.contains(RegExp(r'[-–]'))) {
        final parts = str.split(RegExp(r'[-–]'));
        for (final part in parts) {
          final parsed = _parseSingleTime(part, now);
          if (parsed != null) foundTimes.add(parsed);
        }
        return;
      }

      final parsed = _parseSingleTime(str, now);
      if (parsed != null) {
        foundTimes.add(parsed);
      }
    }

    void scanMap(dynamic data) {
      if (data is Map) {
        for (final entry in data.entries) {
          final keyStr = entry.key
              .toString()
              .toLowerCase()
              .replaceAll('_', '')
              .replaceAll('-', '');

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

    final eventStart = _parseSingleTime(widget.event.startTime, now);
    final eventEnd = _parseSingleTime(widget.event.endTime, now);

    if (foundTimes.isEmpty) {
      if (!isTimeOut && eventStart != null) {
        foundTimes.add(eventStart);
      } else if (isTimeOut && eventEnd != null) {
        foundTimes.add(eventEnd);
      }
    }

    foundTimes.sort();

    DateTime? start = foundTimes.isNotEmpty ? foundTimes.first : null;
    DateTime? end = foundTimes.length > 1 ? foundTimes.last : null;

    if (start != null && end == null) {
      if (!isTimeOut) {
        final outWin = _extractWindow(isTimeOut: true, now: now);
        if (outWin.start != null && outWin.start!.isAfter(start)) {
          end = outWin.start;
        } else if (eventEnd != null && eventEnd.isAfter(start)) {
          final midSeconds = eventEnd.difference(start).inSeconds ~/ 2;
          end = start.add(Duration(seconds: midSeconds));
        } else {
          end = eventEnd;
        }
      } else {
        if (eventStart != null && start.isAfter(eventStart)) {
          final midSeconds = start.difference(eventStart).inSeconds ~/ 2;
          end = start;
          start = eventStart.add(Duration(seconds: midSeconds));
        } else {
          end = eventEnd;
        }
      }
    }

    return _TimeWindow(start, end);
  }

  // --------------------------------------------------------------------------
  // ON-DEVICE ML KIT HEAD-TURN VALIDATION (INSTANT FEEDBACK)
  // --------------------------------------------------------------------------

  Future<_PoseValidationResult> _validateCenterPoseMLKit(XFile frame) async {
    try {
      final inputImage = InputImage.fromFilePath(frame.path);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        return const _PoseValidationResult(
          isValid: false,
          title: 'Face Not Detected',
          message:
              'Please position your face clearly inside the circle and keep steady.',
        );
      }

      if (faces.length > 1) {
        return const _PoseValidationResult(
          isValid: false,
          title: 'Multiple Faces Detected',
          message:
              'Please ensure only your face is visible inside the camera frame.',
        );
      }

      final yaw = faces.first.headEulerAngleY ?? 0.0;

      if (yaw.abs() > 18.0) {
        return _PoseValidationResult(
          isValid: false,
          title: 'Look Straight First',
          message:
              'Please look straight at the camera during the first step before turning (angle: ${yaw.toStringAsFixed(0)}°).',
        );
      }

      return _PoseValidationResult(
        isValid: true,
        title: 'Center Verified',
        message: 'Center pose OK',
        yaw: yaw,
      );
    } catch (e) {
      debugPrint('[MLKIT CENTER ERROR] $e');
      return const _PoseValidationResult(
        isValid: true,
        title: 'Verified',
        message: 'Fallback pass',
      );
    }
  }

  Future<_PoseValidationResult> _validateTurnPoseMLKit({
    required double centerYaw,
    required XFile turnedFrame,
    required String requiredDirection,
  }) async {
    try {
      final inputImage = InputImage.fromFilePath(turnedFrame.path);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        return _PoseValidationResult(
          isValid: false,
          title: 'Face Lost During Turn',
          message:
              'Your face moved out of view. Turn your head slightly to the ${requiredDirection.toUpperCase()} while staying inside the circle.',
        );
      }

      final turnedYaw = faces.first.headEulerAngleY ?? 0.0;
      final deltaYaw = turnedYaw - centerYaw;

      final bool turnedLeft = deltaYaw > _requiredTurnAngle;
      final bool turnedRight = deltaYaw < -_requiredTurnAngle;

      if (requiredDirection == 'left' && !turnedLeft) {
        if (turnedRight) {
          return _PoseValidationResult(
            isValid: false,
            title: 'Wrong Direction',
            message:
                'You turned RIGHT, but you need to turn LEFT. Please try again.',
            yaw: deltaYaw,
          );
        }
        return _PoseValidationResult(
          isValid: false,
          title: 'Head Turn Not Detected',
          message:
              'Please turn your head clearly to the LEFT (detected: ${deltaYaw.toStringAsFixed(0)}°) and try again.',
          yaw: deltaYaw,
        );
      }

      if (requiredDirection == 'right' && !turnedRight) {
        if (turnedLeft) {
          return _PoseValidationResult(
            isValid: false,
            title: 'Wrong Direction',
            message:
                'You turned LEFT, but you need to turn RIGHT. Please try again.',
            yaw: deltaYaw,
          );
        }
        return _PoseValidationResult(
          isValid: false,
          title: 'Head Turn Not Detected',
          message:
              'Please turn your head clearly to the RIGHT (detected: ${deltaYaw.toStringAsFixed(0)}°) and try again.',
          yaw: deltaYaw,
        );
      }

      return _PoseValidationResult(
        isValid: true,
        title: 'Turn Verified',
        message: 'Head turn confirmed (${deltaYaw.toStringAsFixed(0)}°).',
        yaw: deltaYaw,
      );
    } catch (e) {
      debugPrint('[MLKIT TURN ERROR] $e');
      return const _PoseValidationResult(
        isValid: true,
        title: 'Verified',
        message: 'Fallback pass',
      );
    }
  }

  // --------------------------------------------------------------------------
  // DIALOGS
  // --------------------------------------------------------------------------

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
            const Icon(
              Icons.access_time_filled_rounded,
              color: Colors.orangeAccent,
              size: 26,
            ),
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
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'OK',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showInstantPosePopup({
    required String title,
    required String message,
  }) async {
    if (!mounted || _disposed) return;
    HapticFeedback.heavyImpact();
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
              child: const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFDC2626),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
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
            fontSize: 14,
            height: 1.4,
            color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                Navigator.of(dialogCtx).pop();
                if (mounted && !_disposed) {
                  try {
                    await _camera?.resumePreview();
                  } catch (_) {}
                  setState(() {
                    if (_challengeNonce == 'offline-nonce') {
                      _direction = _pickRandomDirection();
                    }
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Try Again Now',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // CAMERA & CAPTURE SEQUENCE
  // --------------------------------------------------------------------------

  Future<void> _initializeAndRunSequence() async {
    try {
      if (widget.event.id == null) throw Exception('Invalid event ID.');

      final initFuture = () async {
        final cameraPerm = await Permission.camera.request();
        if (!cameraPerm.isGranted) {
          throw Exception('Camera permission is required.');
        }

        return Future.wait([
          _initCameraFast(),
          _getAccuratePosition(),
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

      final challengeResult = results[2] as LivenessChallengeResult;
      if (challengeResult.success && challengeResult.challenge != null) {
        _direction = challengeResult.challenge!.direction;
        _challengeNonce = challengeResult.challenge!.nonce;
        _challengeSessionId = challengeResult.challenge!.sessionId;
      } else {
        _direction = _pickRandomDirection();
        _challengeNonce = 'offline-nonce';
        _challengeSessionId = DateTime.now().millisecondsSinceEpoch.toString();
      }

      if (_position != null) {
        _checkGeofence(_position!);
      } else if (widget.event.geofenceEnabled) {
        throw Exception(
          'Unable to get your GPS location. Please enable Location Services and try again.',
        );
      }

      await _runAutomatedCapture();
    } catch (e) {
      if (!mounted || _disposed) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _step = _LivenessStep.failed;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _verifyLocationAndCapture() async {
    if (!mounted || _disposed) return;
    try {
      await _camera?.resumePreview();
    } catch (_) {}
    setState(() {
      _step = _LivenessStep.lookCenter;
      _error = null;
      _hint = 'Checking GPS location...';
    });

    try {
      final pos = await _getAccuratePosition();
      if (!mounted || _disposed) return;
      _position = pos;

      if (pos != null) {
        _checkGeofence(pos);
      } else if (widget.event.geofenceEnabled) {
        throw Exception(
          'Unable to get your GPS location. Please enable Location Services and try again.',
        );
      }

      await _runAutomatedCapture();
    } catch (e) {
      if (!mounted || _disposed) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _step = _LivenessStep.failed;
        _error = e.toString().replaceFirst('Exception: ', '');
        _hint = null;
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
                  child: const Icon(
                    Icons.security_rounded,
                    color: Color(0xFFD97706),
                    size: 32,
                  ),
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
                    color: isDark
                        ? const Color(0xFF3B2D08)
                        : const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Color(0xFFD97706),
                        size: 22,
                      ),
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'I Understand',
                      style: TextStyle(
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

    try {
      await controller.setFocusMode(FocusMode.locked);
    } catch (_) {}
    try {
      await controller.setExposureMode(ExposureMode.locked);
    } catch (_) {}

    if (!mounted || _disposed) {
      await controller.dispose();
      return;
    }

    _camera = controller;
    if (mounted) setState(() => _cameraReady = true);
  }

  Future<Position?> _getAccuratePosition() async {
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
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
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

    final dist = Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      lat,
      lng,
    );
    if (dist > rad) {
      final remaining = (dist - rad).round();
      final distanceText = remaining >= 1000
          ? '${(remaining / 1000).toStringAsFixed(2)} km'
          : '$remaining m';
      throw Exception(
        'You are outside the allowed venue radius ($distanceText away; allowed radius: ${rad.round()} m). Move closer and try again.',
      );
    }
  }

  Future<void> _runAutomatedCapture() async {
    if (_isProcessing ||
        _camera == null ||
        !_camera!.value.isInitialized ||
        _disposed) {
      return;
    }

    _isProcessing = true;
    _flashFrames.clear();
    _flashCompressFutures.clear();
    _flashColors.clear();
    _centerCompressFuture = null;
    _turnedCompressFuture = null;

    try {
      // 1. Center Pose Capture
      setState(() {
        _step = _LivenessStep.lookCenter;
        _hint = 'Look straight. Screen is verifying light reflections...';
      });

      for (int i = 0; i < _flashColorSequence.length; i++) {
        if (!mounted || _disposed) return;

        setState(() => _overlayFlashColor = _flashColorSequence[i]);
        await Future.delayed(const Duration(milliseconds: 220));
        if (!mounted || _disposed) return;

        final frame = await _camera!.takePicture();
        _flashFrames.add(frame);
        _flashColors.add(_flashColorNames[i]);
        _flashCompressFutures.add(_compressPaced(frame));
      }

      _centerFrame = await _camera!.takePicture();
      _centerCompressFuture = _compressPaced(_centerFrame!);

      // Instant ML Kit Check on Center Pose
      final centerCheck = await _validateCenterPoseMLKit(_centerFrame!);
      if (!centerCheck.isValid) {
        if (mounted && !_disposed) {
          setState(() {
            _step = _LivenessStep.failed;
            _overlayFlashColor = Colors.transparent;
          });
          await _showInstantPosePopup(
            title: centerCheck.title,
            message: centerCheck.message,
          );
        }
        return;
      }

      // 2. Head Turn Pose Capture
      setState(() {
        _step = _LivenessStep.turn;
        _hint =
            'Turn your head to your ${_direction.toUpperCase()} while screen flashes...';
      });

      for (int i = 0; i < _flashColorSequence.length; i++) {
        if (!mounted || _disposed) return;

        setState(() => _overlayFlashColor = _flashColorSequence[i]);
        await Future.delayed(const Duration(milliseconds: 250));
        if (!mounted || _disposed) return;

        final frame = await _camera!.takePicture();
        _flashFrames.add(frame);
        _flashColors.add(_flashColorNames[i]);
        _flashCompressFutures.add(_compressPaced(frame));
      }

      _turnedFrame = await _camera!.takePicture();
      _turnedCompressFuture = _compressPaced(_turnedFrame!);

      if (mounted && !_disposed) {
        setState(() {
          _overlayFlashColor = Colors.transparent;
          _step = _LivenessStep.verifying;
          _hint = 'Verifying pose & preparing frames...';
        });
      }
      try {
        await _camera?.pausePreview();
      } catch (_) {}

      final preSubmitResults = await Future.wait([
        _validateTurnPoseMLKit(
          centerYaw: centerCheck.yaw,
          turnedFrame: _turnedFrame!,
          requiredDirection: _direction,
        ),
        _centerCompressFuture!,
        _turnedCompressFuture!,
        Future.wait(_flashCompressFutures),
      ]);

      if (!mounted || _disposed) return;

      final turnCheck = preSubmitResults[0] as _PoseValidationResult;
      if (!turnCheck.isValid) {
        setState(() => _step = _LivenessStep.failed);
        await _showInstantPosePopup(
          title: turnCheck.title,
          message: turnCheck.message,
        );
        return;
      }

      // 3. Submit pre-compressed frames immediately
      await _submitAttendance(
        compressedCenter: preSubmitResults[1] as XFile,
        compressedTurned: preSubmitResults[2] as XFile,
        compressedFlashFrames: preSubmitResults[3] as List<XFile>,
      );
    } catch (e) {
      debugPrint('Capture sequence error: $e');
      if (mounted && !_disposed) {
        setState(() {
          _step = _LivenessStep.failed;
          _overlayFlashColor = Colors.transparent;
        });
        await _showInstantPosePopup(
          title: 'Capture Failed',
          message:
              'Camera capture failed. Please ensure clear lighting and try again.',
        );
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _submitAttendance({
    required XFile compressedCenter,
    required XFile compressedTurned,
    required List<XFile> compressedFlashFrames,
  }) async {
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

    if (eventId == null) {
      throw Exception('Missing event reference.');
    }

    setState(() {
      _step = _LivenessStep.verifying;
      _hint = 'Verifying face with server...';
    });

    final typeStr =
        _currentSession == AttendanceSessionType.timeIn ? 'time_in' : 'time_out';

    final result = await AttendanceService.instance.mobileCheckIn(
      eventId: eventId,
      latitude: pos.latitude,
      longitude: pos.longitude,
      locationAccuracy: pos.accuracy,
      centerFrame: compressedCenter,
      turnedFrame: compressedTurned,
      flashFrames: compressedFlashFrames,
      flashColors: _flashColors,
      challengeNonce: _challengeNonce ?? '',
      sessionId: _challengeSessionId ?? '',
      type: typeStr,
    );

    if (!mounted || _disposed) return;

    if (!result.success) {
      final msg = result.message.toLowerCase();

      if (msg.contains('turn') ||
          msg.contains('angle') ||
          msg.contains('liveness') ||
          msg.contains('pose')) {
        setState(() => _step = _LivenessStep.failed);
        await _showInstantPosePopup(
          title: 'Incorrect Head Turn',
          message:
              'Server verification failed because you did not turn your head to the ${_direction.toUpperCase()} direction. Please try again.',
        );
        return;
      }

      if (result.networkUnavailable) {
        final trustedTime = await _getNormalizedLocalNow();

        final offlineQueueResult =
            await AttendanceService.instance.queueOfflineAttendance(
          eventId: eventId,
          latitude: pos.latitude,
          longitude: pos.longitude,
          locationAccuracy: pos.accuracy,
          attendanceTime: trustedTime,
          centerFrame: compressedCenter,
          turnedFrame: compressedTurned,
          flashFrames: compressedFlashFrames,
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
        timer = Timer(const Duration(milliseconds: 2500), () {
          if (Navigator.canPop(dialogContext)) Navigator.pop(dialogContext);
        });

        final nameText =
            widget.studentName != null && widget.studentName!.isNotEmpty
                ? widget.studentName!
                : 'Student';

        final sessionText = _currentSession == AttendanceSessionType.timeIn
            ? 'Time-In'
            : 'Time-Out';

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
    _faceDetector.close();
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeController.isDarkMode;

    return Scaffold(
      backgroundColor: _overlayFlashColor != Colors.transparent
          ? _overlayFlashColor
          : Theme.of(context).scaffoldBackgroundColor,
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
                  _buildSessionBadge(isDark),
                  const SizedBox(height: 6),
                  Text(
                    widget.event.venue,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: muted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildInstructionBadge(),
                  if (_error != null && _step == _LivenessStep.failed) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: Color(0xFFDC2626),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: Color(0xFF991B1B),
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (_hint != null && _step != _LivenessStep.failed) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF3B2D08)
                            : const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            color: Color(0xFFD97706),
                            size: 18,
                          ),
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
                              child: CircularProgressIndicator(color: brandGold),
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
                onPressed: (_isProcessing || _currentSession == null)
                    ? null
                    : () {
                        setState(() {
                          if (_challengeNonce == 'offline-nonce') {
                            _direction = _pickRandomDirection();
                          }
                          _isProcessing = false;
                        });
                        _verifyLocationAndCapture();
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: brandGold,
                  foregroundColor: brandNavy,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 36,
                    vertical: 14,
                  ),
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

 Widget _buildSessionBadge(bool isDark) {
    final bool isTimeIn = _currentSession == AttendanceSessionType.timeIn;
    final bool isTimeOut = _currentSession == AttendanceSessionType.timeOut;

    final String label = _checkingSession
        ? 'Checking schedule...'
        : isTimeIn
            ? 'Time-In Attendance'
            : isTimeOut
                ? 'Time-Out Attendance'
                : 'Attendance Verification';

    final IconData icon = _checkingSession
        ? Icons.schedule_rounded
        : isTimeIn
            ? Icons.login_rounded
            : isTimeOut
                ? Icons.logout_rounded
                : Icons.verified_user_outlined;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: isDark ? brandGold : brandNavy,
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : brandNavy,
            ),
          ),
        ],
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
        text = 'Turn head towards ${_direction.toUpperCase()}';
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

class _PoseValidationResult {
  final bool isValid;
  final String title;
  final String message;
  final double yaw;

  const _PoseValidationResult({
    required this.isValid,
    required this.title,
    required this.message,
    this.yaw = 0.0,
  });
}

class _TimeWindow {
  final DateTime? start;
  final DateTime? end;
  const _TimeWindow(this.start, this.end);
}