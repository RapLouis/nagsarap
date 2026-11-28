import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../main.dart';
import '../../models/event_item.dart';
import '../../services/attendance_service.dart';
import '../../services/secure_time_service.dart';

enum _LivenessStep { lookCenter, turn, verifying, passed, failed }

enum AttendanceSessionType { timeIn, timeOut }

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
  final bool isFlash;

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
    this.isFlash = false,
  });
}

Uint8List _encodeRawStreamToJpeg(_RawStreamFrame raw) {
  final int targetMax = raw.isFlash ? 160 : 360;
  final int longestSide = max(raw.width, raw.height);
  final int step = max(1, longestSide ~/ targetMax);

  final int outW = raw.width ~/ step;
  final int outH = raw.height ~/ step;
  img.Image image = img.Image(width: outW, height: outH);

  if (raw.isBgra) {
    final bytes = raw.plane0;
    for (int dy = 0; dy < outH; dy++) {
      final sy = dy * step;
      final rowOffset = sy * raw.bytesPerRow0;
      for (int dx = 0; dx < outW; dx++) {
        final sx = dx * step;
        final idx = rowOffset + sx * 4;
        if (idx + 2 < bytes.length) {
          image.setPixelRgb(dx, dy, bytes[idx + 2], bytes[idx + 1], bytes[idx]);
        }
      }
    }
  } else {
    final yPlane = raw.plane0;
    final uPlane = raw.plane1;
    final vPlane = raw.plane2;

    for (int dy = 0; dy < outH; dy++) {
      final sy = dy * step;
      final yRow = sy * raw.bytesPerRow0;
      final uvRowIndex = sy >> 1;
      for (int dx = 0; dx < outW; dx++) {
        final sx = dx * step;
        final yIdx = yRow + sx;
        if (yIdx >= yPlane.length) continue;
        final yp = yPlane[yIdx];

        int up = 128;
        int vp = 128;

        if (uPlane != null && vPlane != null) {
          final uIdx =
              uvRowIndex * raw.bytesPerRow1 + (sx >> 1) * raw.uvPixelStride;
          final vIdx =
              uvRowIndex * raw.bytesPerRow2 + (sx >> 1) * raw.uvPixelStride;
          if (uIdx < uPlane.length && vIdx < vPlane.length) {
            up = uPlane[uIdx];
            vp = vPlane[vIdx];
          }
        } else if (uPlane != null) {
          final uvIdx =
              uvRowIndex * raw.bytesPerRow1 + (sx >> 1) * raw.uvPixelStride;
          if (uvIdx + 1 < uPlane.length) {
            vp = uPlane[uvIdx];
            up = uPlane[uvIdx + 1];
          }
        } else {
          final uvBase = raw.bytesPerRow0 * raw.height;
          final uvIdx =
              uvBase + uvRowIndex * raw.bytesPerRow0 + ((sx >> 1) * 2);
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
        image.setPixelRgb(dx, dy, r, g, b);
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

  return Uint8List.fromList(
    img.encodeJpg(image, quality: raw.isFlash ? 55 : 75),
  );
}

class AttendanceFaceVerificationScreen extends StatefulWidget {
  const AttendanceFaceVerificationScreen({
    super.key,
    required this.event,
    this.studentName,
    this.hasTimeIn = false,
    this.hasTimeOut = false,
    this.timeInWindow,
    this.timeOutWindow,
    this.slotIndex,
    this.checkpointKey,
    this.checkpointLabel,
  });

  final EventItem event;
  final String? studentName;
  final bool hasTimeIn;
  final bool hasTimeOut;
  final String? timeInWindow;
  final String? timeOutWindow;
  final int? slotIndex;
  final String? checkpointKey;
  final String? checkpointLabel;

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
  static const Duration _flashCycleInterval = Duration(milliseconds: 280);

  // Maximum time to wait for online verification before queuing offline
  static const Duration _serverVerifyTimeout = Duration(seconds: 8);

  final Random _random = Random();
  CameraController? _camera;
  CameraDescription? _frontCamera;
  Position? _position;
  DateTime? _positionFetchedAt;

  // On-device ML Kit face detector (100% offline capable)
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: false,
      enableLandmarks: false,
      enableContours: false,
      enableTracking: false,
      performanceMode: FaceDetectorMode.fast,
      minFaceSize: 0.20,
    ),
  );

  bool _cameraReady = false;
  bool _disposed = false;
  bool _isProcessingFrame = false;
  bool _isSubmitting = false;
  bool _checkingSession = true;

  late bool _hasTimeIn;
  late bool _hasTimeOut;
  AttendanceSessionType? _currentSession;
  int? _activeSlotIndex;
  String? _activeCheckpointKey;
  String? _activeCheckpointLabel;

  String _direction = 'left';
  String? _challengeNonce;
  String? _challengeSessionId;
  String? _error;
  String? _hint;

  Color _overlayFlashColor = Colors.transparent;
  final List<String> _flashColors = [];
  final List<Color> _flashColorSequence = [
    const Color(0xFFFF0000),
    const Color(0xFF00FF00),
    const Color(0xFF0000FF),
  ];
  final List<String> _flashColorNames = ['red', 'green', 'blue'];

  _LivenessStep _step = _LivenessStep.lookCenter;

  // Stream & looping flash state
  Timer? _flashLoopTimer;
  double _centerYaw = 0.0;
  int _steadyCenterFrames = 0;
  int _activeFlashIndex = -1;
  int _flashTicks = 0;
  final Map<int, _RawStreamFrame> _rawFlashFrames = {};
  _RawStreamFrame? _rawCenterFrame;
  _RawStreamFrame? _rawTurnedFrame;

  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _hasTimeIn = widget.hasTimeIn;
    _hasTimeOut = widget.hasTimeOut;
    _activeSlotIndex = widget.slotIndex;
    _activeCheckpointKey = widget.checkpointKey;
    _activeCheckpointLabel = widget.checkpointLabel;

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

  String _formatCheckpointLabel(String key) {
    switch (key) {
      case 'morning_time_in':
        return 'Morning Time-In';
      case 'morning_time_out':
        return 'Morning Time-Out';
      case 'afternoon_time_in':
        return 'Afternoon Time-In';
      case 'afternoon_time_out':
        return 'Afternoon Time-Out';
      case 'time_out':
        return 'Time-Out Attendance';
      case 'time_in':
        return 'Time-In Attendance';
      default:
        return key
            .split('_')
            .where((p) => p.isNotEmpty)
            .map((p) => '${p[0].toUpperCase()}${p.substring(1)}')
            .join(' ');
    }
  }

  // --------------------------------------------------------------------------
  // CONTINUOUS LOOPING RGB FLASH CONTROLLER
  // --------------------------------------------------------------------------

  void _startFlashLoop() {
    _stopFlashLoop(clearColor: false);
    _activeFlashIndex = 0;
    _flashTicks = 1;

    if (mounted && !_disposed) {
      setState(() {
        _overlayFlashColor = _flashColorSequence[0];
      });
    }

    _flashLoopTimer = Timer.periodic(_flashCycleInterval, (timer) {
      if (_disposed || !mounted || _isSubmitting) {
        timer.cancel();
        return;
      }

      if (_step != _LivenessStep.lookCenter && _step != _LivenessStep.turn) {
        _stopFlashLoop();
        return;
      }

      _activeFlashIndex = (_activeFlashIndex + 1) % _flashColorSequence.length;
      _flashTicks++;

      setState(() {
        _overlayFlashColor = _flashColorSequence[_activeFlashIndex];
      });
    });
  }

  void _stopFlashLoop({bool clearColor = true}) {
    _flashLoopTimer?.cancel();
    _flashLoopTimer = null;
    _activeFlashIndex = -1;

    if (clearColor && mounted && !_disposed) {
      setState(() {
        _overlayFlashColor = Colors.transparent;
      });
    }
  }

  // --------------------------------------------------------------------------
  // AUTOMATIC SESSION DETECTION (4-CHECKPOINT + LEGACY 2-CHECKPOINT)
  // --------------------------------------------------------------------------

  Future<DateTime> _getNormalizedLocalNow() async {
    final deviceNow = DateTime.now();
    try {
      final trusted = await SecureTimeService.instance
          .getTrustedTime()
          .timeout(const Duration(milliseconds: 500));
      final localTrusted = trusted.toLocal();
      if (localTrusted.year >= 2025 &&
          localTrusted.difference(deviceNow).abs() < const Duration(hours: 2)) {
        return localTrusted;
      }
    } catch (_) {}
    return deviceNow;
  }

  Future<AttendanceSessionType?> _determineCurrentSession() async {
    final now = await _getNormalizedLocalNow();

    if (_activeCheckpointKey != null && _activeCheckpointKey!.isNotEmpty) {
      final isOut = _activeCheckpointKey!.endsWith('time_out') ||
          _activeCheckpointKey == 'out';
      _activeCheckpointLabel ??= _formatCheckpointLabel(_activeCheckpointKey!);

      final windowStr = isOut ? widget.timeOutWindow : widget.timeInWindow;
      if (windowStr != null && windowStr.trim().isNotEmpty) {
        final win = _parseWindowString(windowStr, now);
        if (win.start != null && win.end != null) {
          var adjustedEnd = win.end!;
          if (adjustedEnd.isBefore(win.start!)) {
            adjustedEnd = adjustedEnd.add(const Duration(days: 1));
          }
          final inside =
              (now.isAfter(win.start!) || now.isAtSameMomentAs(win.start!)) &&
                  (now.isBefore(adjustedEnd) ||
                      now.isAtSameMomentAs(adjustedEnd));
          if (!inside) return null;
        }
      }

      return isOut
          ? AttendanceSessionType.timeOut
          : AttendanceSessionType.timeIn;
    }

    final rawDays = widget.event.raw['days'];
    if (rawDays is List && rawDays.isNotEmpty) {
      final todayStr = DateFormat('yyyy-MM-dd').format(now);
      Map<String, dynamic>? dayMap;
      for (final entry in rawDays) {
        if (entry is Map) {
          final d = (entry['date'] ?? entry['event_date'])?.toString().trim();
          if (d != null && d.startsWith(todayStr)) {
            dayMap = Map<String, dynamic>.from(entry);
            break;
          }
        }
      }
      dayMap ??= rawDays.first is Map
          ? Map<String, dynamic>.from(rawDays.first as Map)
          : null;

      final rawSlots = dayMap?['slots'];
      if (rawSlots is List && rawSlots.isNotEmpty) {
        for (int i = 0; i < rawSlots.length; i++) {
          final s = rawSlots[i];
          if (s is! Map) continue;
          final slotMap = Map<String, dynamic>.from(s);
          final slotIndex =
              int.tryParse(slotMap['slot_index']?.toString() ?? '') ?? i;
          final periodRaw =
              (slotMap['period'] ?? slotMap['session'] ?? '')
                  .toString()
                  .trim()
                  .toLowerCase();

          final prefix = (periodRaw == 'morning' || slotIndex == 0)
              ? 'morning'
              : ((periodRaw == 'afternoon' || slotIndex == 1)
                  ? 'afternoon'
                  : 'slot_$slotIndex');

          final inRecorded = slotMap['has_time_in'] == true ||
              slotMap['time_in_recorded'] == true;
          final outRecorded = slotMap['has_time_out'] == true ||
              slotMap['time_out_recorded'] == true;

          final inWin = _slotCheckpointWindow(slotMap, now, isTimeIn: true);
          final outWin = _slotCheckpointWindow(slotMap, now, isTimeIn: false);

          bool inside(_TimeWindow w) {
            if (w.start == null || w.end == null) return false;
            var end = w.end!;
            if (end.isBefore(w.start!)) end = end.add(const Duration(days: 1));
            return (now.isAfter(w.start!) || now.isAtSameMomentAs(w.start!)) &&
                (now.isBefore(end) || now.isAtSameMomentAs(end));
          }

          if (!outRecorded && inside(outWin)) {
            _activeSlotIndex = slotIndex;
            _activeCheckpointKey = '${prefix}_time_out';
            _activeCheckpointLabel =
                _formatCheckpointLabel(_activeCheckpointKey!);
            return AttendanceSessionType.timeOut;
          }
          if (!inRecorded && inside(inWin)) {
            _activeSlotIndex = slotIndex;
            _activeCheckpointKey = '${prefix}_time_in';
            _activeCheckpointLabel =
                _formatCheckpointLabel(_activeCheckpointKey!);
            return AttendanceSessionType.timeIn;
          }
        }
        return null;
      }
    }

    if (_hasTimeIn && _hasTimeOut) return null;

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

  _TimeWindow _slotCheckpointWindow(
    Map<String, dynamic> slotMap,
    DateTime now, {
    required bool isTimeIn,
  }) {
    final combinedKey = isTimeIn ? 'time_in_window' : 'time_out_window';
    final shortCombinedKey = isTimeIn ? 'time_in' : 'time_out';
    final combined =
        (slotMap[combinedKey] ?? slotMap[shortCombinedKey])?.toString();
    if (combined != null && combined.contains(RegExp(r'[-–]'))) {
      return _parseWindowString(combined, now);
    }

    final startStr = (isTimeIn
            ? (slotMap['time_in_start'] ??
                slotMap['time_in_start_time'] ??
                slotMap['start_time'])
            : (slotMap['time_out_start'] ?? slotMap['time_out_start_time']))
        ?.toString();
    final endStr = (isTimeIn
            ? (slotMap['time_in_end'] ?? slotMap['time_in_end_time'])
            : (slotMap['time_out_end'] ??
                slotMap['time_out_end_time'] ??
                slotMap['end_time']))
        ?.toString();

    return _TimeWindow(
      startStr != null ? _parseSingleTime(startStr, now) : null,
      endStr != null ? _parseSingleTime(endStr, now) : null,
    );
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
                  setState(() {
                    if (_challengeNonce == 'offline-nonce') {
                      _direction = _pickRandomDirection();
                    }
                    _step = _LivenessStep.lookCenter;
                    _error = null;
                    _isSubmitting = false;
                  });
                  await _startLiveStreamVerification();
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
  // CAMERA & REAL-TIME HEAD-TURN STREAM SEQUENCE
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
          AttendanceService.instance
              .requestLivenessChallenge(
                eventId: widget.event.id!,
                slotIndex: _activeSlotIndex,
                checkpointKey: _activeCheckpointKey,
              )
              .timeout(
                const Duration(seconds: 3),
                onTimeout: () => const LivenessChallengeResult(
                  success: false,
                  message: 'Challenge timeout',
                  networkUnavailable: true,
                ),
              ),
        ]);
      }();

      await _showInstructionModal();

      if (_disposed || !mounted) return;

      final results = await initFuture;
      if (_disposed || !mounted) return;

      _position = results[1] as Position?;
      if (_position != null) {
        _positionFetchedAt = DateTime.now();
      }

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

      await _startLiveStreamVerification();
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
    if (!mounted || _disposed || _isSubmitting) return;
    _stopFlashLoop();
    await _stopStream();

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
        _positionFetchedAt = DateTime.now();
      }

      if (pos != null) {
        _checkGeofence(pos);
      } else if (widget.event.geofenceEnabled) {
        throw Exception(
          'Unable to get your GPS location. Please enable Location Services and try again.',
        );
      }

      await _startLiveStreamVerification();
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
                  'Look straight at the camera while your screen loops RED, GREEN, and BLUE light, then turn your head to the requested direction when prompted.',
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
                          'Keep phone steady at eye level. The screen will flash continuously until you complete the head turn.',
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

    _camera = controller;
    if (mounted) setState(() => _cameraReady = true);
  }

  Future<Position?> _getAccuratePosition({
    Duration timeout = const Duration(seconds: 3),
  }) async {
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
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeout,
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

  Future<void> _startLiveStreamVerification() async {
    final controller = _camera;
    if (controller == null || !controller.value.isInitialized || _disposed) {
      return;
    }

    _stopFlashLoop();
    _rawFlashFrames.clear();
    _flashColors.clear();
    _rawCenterFrame = null;
    _rawTurnedFrame = null;
    _steadyCenterFrames = 0;
    _centerYaw = 0.0;
    _flashTicks = 0;
    _isSubmitting = false;

    if (!mounted || _disposed) return;

    setState(() {
      _overlayFlashColor = Colors.transparent;
      _step = _LivenessStep.lookCenter;
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
        _step == _LivenessStep.verifying ||
        _step == _LivenessStep.passed ||
        _step == _LivenessStep.failed) {
      return;
    }

    _isProcessingFrame = true;

    try {
      final inputImage = _toInputImage(image);
      if (inputImage == null) return;

      final faces = await _faceDetector.processImage(inputImage);
      if (_disposed || !mounted) return;

      if (faces.isEmpty) {
        const msg = 'Position your face clearly inside the circle...';
        if (_hint != msg) {
          setState(() => _hint = msg);
        }
        return;
      }

      if (faces.length > 1) {
        const msg = 'Multiple faces detected. Keep only your face in frame.';
        if (_hint != msg) {
          setState(() => _hint = msg);
        }
        return;
      }

      final face = faces.first;
      final double yaw = face.headEulerAngleY ?? 0.0;

      // Capture latest flash frame for whichever color is currently active in the loop
      if (_activeFlashIndex >= 0 &&
          _activeFlashIndex < _flashColorSequence.length) {
        _rawFlashFrames[_activeFlashIndex] = _copyRawFrame(image, isFlash: true);
      }

      // STEP 1: Center pose + start continuous RGB flash loop
      if (_step == _LivenessStep.lookCenter) {
        if (yaw.abs() > 16.0) {
          const msg = 'Look straight at the camera first...';
          if (_hint != msg) {
            setState(() => _hint = msg);
          }
          return;
        }

        if (_flashLoopTimer == null) {
          _steadyCenterFrames++;
          if (_steadyCenterFrames < 2) return;

          _rawCenterFrame = _copyRawFrame(image, isFlash: false);
          _centerYaw = yaw;
          _startFlashLoop();

          setState(() {
            _hint = 'Hold still while light flashes...';
          });
          return;
        }

        // Wait until at least 1 full R-G-B cycle (3 ticks) has flashed, then prompt to turn
        // while keeping the RGB flash loop running continuously!
        if (_flashTicks >= _flashColorSequence.length &&
            _rawFlashFrames.length >= _flashColorSequence.length) {
          setState(() {
            _step = _LivenessStep.turn;
            _hint =
                'Now turn your head clearly to your ${_direction.toUpperCase()}...';
          });
        }
        return;
      }

      // STEP 2: Keep RGB flash looping until user completes the turn (or fails wrong way)
      if (_step == _LivenessStep.turn) {
        final double deltaYaw = yaw - _centerYaw;
        final bool turnedLeft = deltaYaw > _requiredTurnAngle;
        final bool turnedRight = deltaYaw < -_requiredTurnAngle;

        if (_direction == 'left') {
          if (turnedRight) {
            _stopFlashLoop();
            await _stopStream();
            if (!mounted || _disposed) return;
            setState(() {
              _step = _LivenessStep.failed;
            });
            await _showInstantPosePopup(
              title: 'Wrong Direction',
              message:
                  'You turned RIGHT, but you need to turn LEFT. Please try again.',
            );
            return;
          }
          if (!turnedLeft) {
            return;
          }
        } else {
          if (turnedLeft) {
            _stopFlashLoop();
            await _stopStream();
            if (!mounted || _disposed) return;
            setState(() {
              _step = _LivenessStep.failed;
            });
            await _showInstantPosePopup(
              title: 'Wrong Direction',
              message:
                  'You turned LEFT, but you need to turn RIGHT. Please try again.',
            );
            return;
          }
          if (!turnedRight) {
            return;
          }
        }

        // Turn completed! Stop looping flash and camera stream, then submit immediately
        _rawTurnedFrame = _copyRawFrame(image, isFlash: false);
        _stopFlashLoop();
        await _stopStream();

        if (!mounted || _disposed) return;
        setState(() {
          _step = _LivenessStep.verifying;
          _hint = 'Turn confirmed! Submitting attendance...';
        });

        await _encodeAndSubmitFromStream();
      }
    } catch (e) {
      debugPrint('Attendance liveness stream error: $e');
    } finally {
      _isProcessingFrame = false;
    }
  }

  _RawStreamFrame _copyRawFrame(CameraImage image, {required bool isFlash}) {
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
      isFlash: isFlash,
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

  Future<void> _encodeAndSubmitFromStream() async {
    if (_isSubmitting || _rawCenterFrame == null || _rawTurnedFrame == null) {
      return;
    }

    _isSubmitting = true;

    try {
      // Reuse already-verified position if recent (< 30s), otherwise do a quick 1.5s lookup
      Position? freshPos = _position;
      final bool isStale = freshPos == null ||
          _positionFetchedAt == null ||
          DateTime.now().difference(_positionFetchedAt!) >
              const Duration(seconds: 30);

      if (widget.event.geofenceEnabled && isStale) {
        freshPos = await _getAccuratePosition(
              timeout: const Duration(milliseconds: 1500),
            ) ??
            _position;
        if (!mounted || _disposed) return;
        _position = freshPos;
        if (freshPos != null) {
          _positionFetchedAt = DateTime.now();
        }
      }

      if (freshPos != null) {
        _checkGeofence(freshPos);
      } else if (widget.event.geofenceEnabled) {
        throw Exception(
          'Unable to verify your GPS location inside the venue geofence.',
        );
      }

      final tempDir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;

      final orderedFlashRaw = <_RawStreamFrame>[];
      final orderedFlashColors = <String>[];
      for (int i = 0; i < _flashColorNames.length; i++) {
        final raw = _rawFlashFrames[i];
        if (raw != null) {
          orderedFlashRaw.add(raw);
          orderedFlashColors.add(_flashColorNames[i]);
        }
      }

      // Single fast isolate encode pass (already downsampled & JPEG-compressed)
      final encoded = await Future.wait<Uint8List>([
        compute(_encodeRawStreamToJpeg, _rawCenterFrame!),
        compute(_encodeRawStreamToJpeg, _rawTurnedFrame!),
        ...orderedFlashRaw.map((r) => compute(_encodeRawStreamToJpeg, r)),
      ]);

      Future<XFile> writeTemp(String tag, Uint8List bytes) async {
        final f = File('${tempDir.path}/att_${ts}_$tag.jpg');
        await f.writeAsBytes(bytes, flush: false);
        return XFile(f.path);
      }

      final files = await Future.wait<XFile>([
        writeTemp('center', encoded[0]),
        writeTemp('turned', encoded[1]),
        for (int i = 2; i < encoded.length; i++)
          writeTemp('flash_${i - 2}', encoded[i]),
      ]);

      if (!mounted || _disposed) return;

      _flashColors
        ..clear()
        ..addAll(orderedFlashColors);

      await _submitAttendance(
        compressedCenter: files[0],
        compressedTurned: files[1],
        compressedFlashFrames: files.sublist(2),
      );
    } catch (e) {
      if (!mounted || _disposed) return;
      HapticFeedback.heavyImpact();
      final msg = e.toString().replaceFirst('Exception: ', '');
      _fail(msg);
      await _showInstantPosePopup(
        title: 'Verification Failed',
        message: msg,
      );
    } finally {
      _isSubmitting = false;
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

    dynamic result;
    try {
      result = await AttendanceService.instance
          .mobileCheckIn(
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
            slotIndex: _activeSlotIndex,
            checkpointKey: _activeCheckpointKey,
          )
          .timeout(_serverVerifyTimeout);
    } on TimeoutException {
      result = null;
    } catch (_) {
      result = null;
    }

    if (!mounted || _disposed) return;

    final bool isSuccess = result != null && result.success == true;
    final String resultMessage = result != null
        ? (result.message?.toString() ?? 'Verification failed.')
        : 'Server response timed out. Saving offline...';
    final bool isNetworkUnavailable =
        result == null || result.networkUnavailable == true;

    if (!isSuccess) {
      final msg = resultMessage.toLowerCase();

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

      if (isNetworkUnavailable) {
        setState(() => _hint = 'Saving locally for background sync...');
        final trustedTime = await _getNormalizedLocalNow();

        try {
          final offlineQueueResult = await AttendanceService.instance
              .queueOfflineAttendance(
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
                slotIndex: _activeSlotIndex,
                checkpointKey: _activeCheckpointKey,
              )
              .timeout(const Duration(seconds: 5));

          if (!mounted || _disposed) return;

          if (!offlineQueueResult.success) {
            _fail(offlineQueueResult.message);
            return;
          }
        } catch (e) {
          _fail('Failed to save offline attendance: $e');
          return;
        }
      } else {
        _fail(resultMessage);
        _showClosedDialog(resultMessage);
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

        final sessionText = _activeCheckpointLabel ??
            (_currentSession == AttendanceSessionType.timeIn
                ? 'Time-In'
                : 'Time-Out');

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
    _stopFlashLoop();
    setState(() {
      _step = _LivenessStep.failed;
      _error = message;
    });
  }

  @override
  void dispose() {
    _flashLoopTimer?.cancel();
    _pulseController.dispose();
    _disposed = true;
    _stopStream();
    _faceDetector.close();
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeController.isDarkMode;
    final bool isFlashing = _overlayFlashColor != Colors.transparent;

    return Scaffold(
      backgroundColor: isFlashing
          ? _overlayFlashColor
          : Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: isFlashing
            ? _overlayFlashColor
            : (isDark ? const Color(0xFF1E293B) : brandNavy),
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
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: isFlashing ? Colors.white : muted,
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
                            color: (isFlashing ? Colors.white : brandGold)
                                .withValues(
                              alpha: 0.3 + (_pulseController.value * 0.4),
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
                        color: isFlashing ? _overlayFlashColor : brandGold,
                        width: isFlashing ? 8 : 4,
                      ),
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
            if (!isFlashing)
              Positioned(
                bottom: 30,
                child: ElevatedButton(
                  onPressed: (_isSubmitting || _currentSession == null)
                      ? null
                      : () {
                          setState(() {
                            if (_challengeNonce == 'offline-nonce') {
                              _direction = _pickRandomDirection();
                            }
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
        : (_activeCheckpointLabel ??
            (isTimeIn
                ? 'Time-In Attendance'
                : isTimeOut
                    ? 'Time-Out Attendance'
                    : 'Attendance Verification'));

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

class _TimeWindow {
  final DateTime? start;
  final DateTime? end;
  const _TimeWindow(this.start, this.end);
}