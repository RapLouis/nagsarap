import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../models/event_item.dart';
import '../../services/attendance_service.dart';


enum _AttendanceStep {
  preparing,
  center,
  blink,
  turn,
  smile,
  returnCenter,
  verifying,
  failed,
}

class AttendanceFaceVerificationScreen extends StatefulWidget {
  final EventItem event;

  const AttendanceFaceVerificationScreen({super.key, required this.event});

  @override
  State<AttendanceFaceVerificationScreen> createState() =>
      _AttendanceFaceVerificationScreenState();
}

class _AttendanceFaceVerificationScreenState
    extends State<AttendanceFaceVerificationScreen> {
  static const Color navy = Color(0xFF080878);
  static const Color gold = Color(0xFFFFC800);
  static const Color background = Color(0xFFF7F7FB);

  // Keep these aligned with the working registration challenge/Python service.
  static const double centerYawLimit = 0.08;
  static const double turnYawDelta = 0.06;
  static const double returnYawDelta = 0.06;
  static const double blinkRatio = 0.88;
  static const double blinkReopenRatio = 0.92;
  static const double smileRatio = 1.04;

  static const Duration normalCaptureInterval = Duration(milliseconds: 250);
  static const Duration blinkCaptureInterval = Duration(milliseconds: 80);

  CameraController? _camera;
  Position? _position;

  bool _initializing = true;
  bool _running = false;
  bool _analyzing = false;
  bool _disposed = false;
  String? _error;

  _AttendanceStep _step = _AttendanceStep.preparing;

  XFile? _centerFrame;
  XFile? _blinkFrame;
  XFile? _turnedFrame;
  XFile? _smileFrame;
  XFile? _returnedFrame;

  double? _centerYaw;
  double? _centerEyeOpenness;
  double? _centerMouthWidth;
  bool _blinkClosedDetected = false;

  int _badFrames = 0;
  static const int maxBadFramesBeforeMessage = 6;

  Duration get _currentCaptureInterval {
    return _step == _AttendanceStep.blink
        ? blinkCaptureInterval
        : normalCaptureInterval;
  }

  bool get _waitingForBlinkReopen =>
      _step == _AttendanceStep.blink && _blinkClosedDetected;

  @override
  void initState() {
    super.initState();
    _prepareAttendance();
  }

  Future<void> _prepareAttendance() async {
    try {
      final position = await _getCurrentPosition();
      if (!mounted || _disposed) return;
      _position = position;
      await _initializeCamera();
    } catch (e) {
      if (!mounted || _disposed) return;
      setState(() {
        _initializing = false;
        _step = _AttendanceStep.failed;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<Position> _getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception(
        'Location services are disabled. Turn on GPS and try again.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw Exception(
        'Location permission is required to verify the event geofence.',
      );
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permission is permanently denied. Enable it in Android settings.',
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
  }

  Future<void> _initializeCamera() async {
    if (_disposed) return;

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
        _step = _AttendanceStep.preparing;
      });

      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted || _disposed) return;
      await _startChallenge();
    } on CameraException catch (e) {
      if (!mounted || _disposed) return;
      setState(() {
        _initializing = false;
        _step = _AttendanceStep.failed;
        _error = e.code == 'CameraAccessDenied'
            ? 'Camera permission was denied. Allow camera access and try again.'
            : 'Unable to start camera: ${e.description ?? e.code}';
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

    if (!mounted) return;
    setState(() {
      _running = true;
      _error = null;
      _step = _AttendanceStep.center;
    });

    while (mounted &&
        !_disposed &&
        _running &&
        _step != _AttendanceStep.verifying &&
        _step != _AttendanceStep.failed) {
      await _captureAndAnalyze();

      if (!mounted ||
          _disposed ||
          !_running ||
          _step == _AttendanceStep.verifying ||
          _step == _AttendanceStep.failed) {
        break;
      }

      await Future<void>.delayed(_currentCaptureInterval);
    }
  }

  void _resetChallenge() {
    _centerFrame = null;
    _blinkFrame = null;
    _turnedFrame = null;
    _smileFrame = null;
    _returnedFrame = null;
    _centerYaw = null;
    _centerEyeOpenness = null;
    _centerMouthWidth = null;
    _blinkClosedDetected = false;
    _badFrames = 0;
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

    final result =
    await AttendanceService.instance
        .analyzeLivenessFrame(
  frame: frame,
);

      if (!mounted || _disposed || !_running) return;

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
      final eye = result.eyeOpenness;
      final mouth = result.mouthWidth;

      if (yaw == null || eye == null || mouth == null) {
        _badFrames++;
        if (_badFrames >= maxBadFramesBeforeMessage && mounted) {
          setState(() {
            _error = 'Unable to read facial measurements. Keep your face clearly visible.';
          });
        }
        return;
      }

      _badFrames = 0;
      if (_error != null && mounted) {
        setState(() => _error = null);
      }

      await _processMeasurement(
        frame: frame,
        yaw: yaw,
        eyeOpenness: eye,
        mouthWidth: mouth,
      );
    } on CameraException catch (e) {
      if (!mounted || _disposed) return;
      setState(() {
        _error = 'Camera capture failed: ${e.description ?? e.code}';
      });
    } catch (_) {
      _badFrames++;
      if (_badFrames >= maxBadFramesBeforeMessage && mounted) {
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
    required double eyeOpenness,
    required double mouthWidth,
  }) async {
    switch (_step) {
      case _AttendanceStep.center:
        if (yaw.abs() <= centerYawLimit) {
          _centerFrame = frame;
          _centerYaw = yaw;
          _centerEyeOpenness = eyeOpenness;
          _centerMouthWidth = mouthWidth;
          _blinkClosedDetected = false;
          if (!mounted) return;
          setState(() => _step = _AttendanceStep.blink);
        }
        break;

      case _AttendanceStep.blink:
        final baseline = _centerEyeOpenness;
        if (baseline == null || baseline <= 0) {
          _fail('Center eye measurement was lost. Please try again.');
          return;
        }

        final closedThreshold = baseline * blinkRatio;
        final reopenThreshold = baseline * blinkReopenRatio;

        if (!_blinkClosedDetected) {
          if (eyeOpenness <= closedThreshold) {
            _blinkClosedDetected = true;
            _blinkFrame = frame;
            if (mounted) setState(() {});
          }
        } else if (eyeOpenness >= reopenThreshold) {
          if (_blinkFrame == null) {
            _fail('Blink frame was not captured. Please try again.');
            return;
          }
          if (!mounted) return;
          setState(() => _step = _AttendanceStep.turn);
        }
        break;

      case _AttendanceStep.turn:
        final baseline = _centerYaw;
        if (baseline == null) {
          _fail('Center measurements were lost. Please try again.');
          return;
        }

        if ((yaw - baseline).abs() >= turnYawDelta) {
          _turnedFrame = frame;
          if (!mounted) return;
          setState(() => _step = _AttendanceStep.smile);
        }
        break;

      case _AttendanceStep.smile:
        final baseline = _centerMouthWidth;
        if (baseline == null || baseline <= 0) {
          _fail('Center measurements were lost. Please try again.');
          return;
        }

        if (mouthWidth >= baseline * smileRatio) {
          _smileFrame = frame;
          if (!mounted) return;
          setState(() => _step = _AttendanceStep.returnCenter);
        }
        break;

      case _AttendanceStep.returnCenter:
        final originalYaw = _centerYaw;
        if (originalYaw == null) {
          _fail('Center measurements were lost. Please try again.');
          return;
        }

        final centered = yaw.abs() <= centerYawLimit;
        final returned = (yaw - originalYaw).abs() <= returnYawDelta;

        if (centered && returned) {
          _returnedFrame = frame;
          await _submitAttendance();
        }
        break;

      case _AttendanceStep.preparing:
      case _AttendanceStep.verifying:
      case _AttendanceStep.failed:
        break;
    }
  }

  Future<void> _submitAttendance() async {
    final position = _position;

    if (_centerFrame == null ||
        _blinkFrame == null ||
        _turnedFrame == null ||
        _smileFrame == null ||
        _returnedFrame == null) {
      _fail('Some biometric frames were not captured. Please try again.');
      return;
    }

    if (position == null) {
      _fail('Your location could not be read. Please try again.');
      return;
    }

    if (!mounted || _disposed) return;

    setState(() {
      _running = false;
      _step = _AttendanceStep.verifying;
      _error = null;
    });

    final result = await AttendanceService.instance.mobileCheckIn(
      eventId: widget.event.id!,
      latitude: _position!.latitude,
      longitude: _position!.longitude,
      locationAccuracy: _position!.accuracy,
      centerFrame: _centerFrame!,
      blinkFrame: _blinkFrame!,
      turnedFrame: _turnedFrame!,
      smileFrame: _smileFrame!,
      returnedFrame: _returnedFrame!,
    );

    if (!mounted || _disposed) return;

   if (!result.success) {
    if (result.code == 'OUTSIDE_GEOFENCE') {
        final data = result.data;

        final distance =
            (data?['distance_meters'] as num?)?.toDouble();

        final radius =
            (data?['allowed_radius_meters'] as num?)?.toDouble();

        if (distance != null && radius != null) {
        final metersOutside =
            (distance - radius).clamp(0.0, double.infinity);

        _fail(
            'You are ${distance.toStringAsFixed(1)} m from the event location.\n'
            'Allowed radius: ${radius.toStringAsFixed(0)} m.\n'
            'Move ${metersOutside.toStringAsFixed(1)} m closer.',
        );

        return;
        }
    }

    _fail(result.message);
    return;
}

    await _showSuccess(result);
  }

  void _fail(String message) {
    if (!mounted || _disposed) return;
    setState(() {
      _running = false;
      _step = _AttendanceStep.failed;
      _error = message;
    });
  }

  Future<void> _retry() async {
    if (_disposed) return;

    if (_position == null) {
      setState(() {
        _initializing = true;
        _error = null;
        _step = _AttendanceStep.preparing;
      });
      await _prepareAttendance();
      return;
    }

    setState(() {
      _error = null;
      _step = _AttendanceStep.preparing;
    });
    await _startChallenge();
  }

  Future<void> _showSuccess(AttendanceResult result) async {
    final attendance = result.data?['attendance'];
    String status = 'Recorded';

    if (attendance is Map && attendance['status'] != null) {
      final raw = attendance['status'].toString();
      if (raw.isNotEmpty) {
        status = '${raw[0].toUpperCase()}${raw.substring(1).toLowerCase()}';
      }
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          contentPadding: const EdgeInsets.fromLTRB(28, 30, 28, 24),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: Color(0xFF00B934),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 48,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Attendance Recorded',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF1E1E24),
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.event.name,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF55555F), fontSize: 14),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3BF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  style: const TextStyle(
                    color: navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: navy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (mounted && !_disposed) {
      Navigator.of(context).pop(true);
    }
  }

  String get _instruction {
    switch (_step) {
      case _AttendanceStep.preparing:
        return 'Preparing camera and location...';
      case _AttendanceStep.center:
        return 'Look straight at the camera';
      case _AttendanceStep.blink:
        return _waitingForBlinkReopen
            ? 'Open your eyes'
            : 'Blink both eyes naturally';
      case _AttendanceStep.turn:
        return 'Turn your head left or right';
      case _AttendanceStep.smile:
        return 'Smile clearly';
      case _AttendanceStep.returnCenter:
        return 'Return your face to the center';
      case _AttendanceStep.verifying:
        return 'Verifying face, liveness and geofence...';
      case _AttendanceStep.failed:
        return 'Verification stopped';
    }
  }

  int get _stepNumber {
    switch (_step) {
      case _AttendanceStep.center:
        return 1;
      case _AttendanceStep.blink:
        return 2;
      case _AttendanceStep.turn:
        return 3;
      case _AttendanceStep.smile:
        return 4;
      case _AttendanceStep.returnCenter:
        return 5;
      case _AttendanceStep.preparing:
        return 0;
      case _AttendanceStep.verifying:
        return 6;
      case _AttendanceStep.failed:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _camera;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Record Attendance',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 30),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE5E5EC)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.event.name,
                      style: const TextStyle(
                        color: navy,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (widget.event.venue.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, size: 18),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              widget.event.venue,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: 290,
                height: 290,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _step == _AttendanceStep.failed ? Colors.red : gold,
                    width: 5,
                  ),
                  color: Colors.black,
                ),
                clipBehavior: Clip.antiAlias,
                child:
                    _initializing ||
                        controller == null ||
                        !controller.value.isInitialized
                    ? const Center(
                        child: CircularProgressIndicator(color: gold),
                      )
                    : Transform.scale(
                        scaleX: -1,
                        child: CameraPreview(controller),
                      ),
              ),
              const SizedBox(height: 24),
              if (_stepNumber >= 1 && _stepNumber <= 5)
                Text(
                  'Step $_stepNumber of 5',
                  style: const TextStyle(
                    color: Color(0xFF777783),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                _instruction,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: navy,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Keep only your face inside the guide. Do not use a photo or another screen.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF777783),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              if (_position != null) ...[
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.gps_fixed_rounded,
                      color: Color(0xFF00A33C),
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'GPS accuracy ±${_position!.accuracy.round()} m',
                      style: const TextStyle(
                        color: Color(0xFF55555F),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
              if (_step == _AttendanceStep.verifying) ...[
                const SizedBox(height: 22),
                const CircularProgressIndicator(color: navy),
              ],
              if (_error != null) ...[
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFFCDD2)),
                  ),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFB71C1C),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              if (_step == _AttendanceStep.failed) ...[
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: navy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try Again'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _running = false;
    _camera?.dispose();
    super.dispose();
  }
}
