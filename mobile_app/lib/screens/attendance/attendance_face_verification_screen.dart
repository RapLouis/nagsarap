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
  const AttendanceFaceVerificationScreen({super.key, required this.event});

  final EventItem event;

  @override
  State<AttendanceFaceVerificationScreen> createState() =>
      _AttendanceFaceVerificationScreenState();
}

class _AttendanceFaceVerificationScreenState
    extends State<AttendanceFaceVerificationScreen> {
  static const Color navy = Color(0xFF080878);

  static const Color gold = Color(0xFFFFC800);

  static const Color background = Color(0xFFF7F7FB);

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

  bool _offlineMode = false;

  bool _manualCaptureBusy = false;

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

  // ===========================================================================
  // PREPARE LOCATION + CAMERA
  // ===========================================================================

  Future<void> _prepareAttendance() async {
    try {
      final eventId = widget.event.id;

      if (eventId == null) {
        throw Exception('The selected event does not have a valid ID.');
      }

      final position = await _getCurrentPosition();

      if (!mounted || _disposed) {
        return;
      }

      _position = position;

      /*
       * Client-side geofence pre-check.
       *
       * Laravel remains authoritative and
       * verifies this again during online
       * check-in or offline synchronization.
       */
      _validateLocalGeofence(position);

      await _initializeCamera();
    } catch (e) {
      if (!mounted || _disposed) {
        return;
      }

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

  void _validateLocalGeofence(Position position) {
    if (!widget.event.geofenceEnabled) {
      return;
    }

    final eventLatitude = widget.event.latitude;

    final eventLongitude = widget.event.longitude;

    final radius = widget.event.geofenceRadius;

    if (eventLatitude == null || eventLongitude == null || radius <= 0) {
      /*
       * Do not invent location settings.
       * Laravel will reject invalid event
       * geofence configuration.
       */
      return;
    }

    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      eventLatitude,
      eventLongitude,
    );

    if (distance > radius) {
      final outsideBy = distance - radius;

      throw Exception(
        'You are ${distance.toStringAsFixed(1)} m '
        'from the event location.\n'
        'Allowed radius: $radius m.\n'
        'Move ${outsideBy.toStringAsFixed(1)} m closer.',
      );
    }
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
        _step = _AttendanceStep.preparing;
      });

      await Future<void>.delayed(const Duration(milliseconds: 900));

      if (!mounted || _disposed) {
        return;
      }

      await _startOnlineChallenge();
    } on CameraException catch (e) {
      if (!mounted || _disposed) {
        return;
      }

      setState(() {
        _initializing = false;

        _step = _AttendanceStep.failed;

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

        _step = _AttendanceStep.failed;

        _error = 'Unable to start the camera.';
      });
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

    _blinkClosedDetected = false;

    _badFrames = 0;
  }

  // ===========================================================================
  // ONLINE CHALLENGE
  // ===========================================================================

  Future<void> _startOnlineChallenge() async {
    final controller = _camera;

    if (_running ||
        controller == null ||
        !controller.value.isInitialized ||
        _disposed) {
      return;
    }

    _offlineMode = false;

    _resetChallenge();

    if (!mounted) {
      return;
    }

    setState(() {
      _running = true;
      _error = null;
      _step = _AttendanceStep.center;
    });

    while (mounted &&
        !_disposed &&
        _running &&
        !_offlineMode &&
        _step != _AttendanceStep.verifying &&
        _step != _AttendanceStep.failed) {
      await _captureAndAnalyze();

      if (!mounted ||
          _disposed ||
          !_running ||
          _offlineMode ||
          _step == _AttendanceStep.verifying ||
          _step == _AttendanceStep.failed) {
        break;
      }

      await Future<void>.delayed(_currentCaptureInterval);
    }
  }

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

      final result = await AttendanceService.instance.analyzeLivenessFrame(
        frame: frame,
      );

      if (!mounted || _disposed || !_running) {
        return;
      }

      /*
       * Laravel is unreachable.
       *
       * Switch to safe offline evidence
       * collection. No successful attendance
       * is claimed at this point.
       */
      if (result.networkUnavailable) {
        _switchToOfflineMode();

        return;
      }

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

          if (!mounted) {
            return;
          }

          setState(() {
            _step = _AttendanceStep.blink;
          });
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

            if (mounted) {
              setState(() {});
            }
          }
        } else if (eyeOpenness >= reopenThreshold) {
          if (_blinkFrame == null) {
            _fail('Blink frame was not captured. Please try again.');

            return;
          }

          if (!mounted) {
            return;
          }

          setState(() {
            _step = _AttendanceStep.turn;
          });
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

          if (!mounted) {
            return;
          }

          setState(() {
            _step = _AttendanceStep.smile;
          });
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

          if (!mounted) {
            return;
          }

          setState(() {
            _step = _AttendanceStep.returnCenter;
          });
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

          await _submitOnlineAttendance();
        }

        break;

      case _AttendanceStep.preparing:
      case _AttendanceStep.verifying:
      case _AttendanceStep.failed:
        break;
    }
  }

  // ===========================================================================
  // OFFLINE MODE
  // ===========================================================================

  void _switchToOfflineMode() {
    _running = false;

    _offlineMode = true;

    _resetChallenge();

    if (!mounted || _disposed) {
      return;
    }

    setState(() {
      _step = _AttendanceStep.center;

      _error = null;
    });
  }

  Future<void> _captureOfflineStep() async {
    if (_manualCaptureBusy || _disposed) {
      return;
    }

    final controller = _camera;

    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture) {
      return;
    }

    _manualCaptureBusy = true;

    try {
      final frame = await controller.takePicture();

      if (!mounted || _disposed) {
        return;
      }

      switch (_step) {
        case _AttendanceStep.center:
          _centerFrame = frame;

          setState(() {
            _step = _AttendanceStep.blink;
          });

          break;

        case _AttendanceStep.blink:
          _blinkFrame = frame;

          setState(() {
            _step = _AttendanceStep.turn;
          });

          break;

        case _AttendanceStep.turn:
          _turnedFrame = frame;

          setState(() {
            _step = _AttendanceStep.smile;
          });

          break;

        case _AttendanceStep.smile:
          _smileFrame = frame;

          setState(() {
            _step = _AttendanceStep.returnCenter;
          });

          break;

        case _AttendanceStep.returnCenter:
          _returnedFrame = frame;

          await _queueOfflineAttendance();

          break;

        case _AttendanceStep.preparing:
        case _AttendanceStep.verifying:
        case _AttendanceStep.failed:
          break;
      }
    } on CameraException catch (e) {
      if (!mounted || _disposed) {
        return;
      }

      setState(() {
        _error = 'Camera capture failed: ${e.description ?? e.code}';
      });
    } finally {
      _manualCaptureBusy = false;
    }
  }

  // ===========================================================================
  // ONLINE SUBMIT
  // ===========================================================================

  Future<void> _submitOnlineAttendance() async {
    final position = _position;

    final eventId = widget.event.id;

    if (eventId == null) {
      _fail('The selected event does not have a valid ID.');

      return;
    }

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

    if (!mounted || _disposed) {
      return;
    }

    setState(() {
      _running = false;

      _step = _AttendanceStep.verifying;

      _error = null;
    });

    final result = await AttendanceService.instance.mobileCheckIn(
      eventId: eventId,
      latitude: position.latitude,
      longitude: position.longitude,
      locationAccuracy: position.accuracy,
      centerFrame: _centerFrame!,
      blinkFrame: _blinkFrame!,
      turnedFrame: _turnedFrame!,
      smileFrame: _smileFrame!,
      returnedFrame: _returnedFrame!,
    );

    if (!mounted || _disposed) {
      return;
    }

    /*
     * Connection disappeared after the
     * challenge had already completed.
     *
     * Do not throw those frames away.
     * Store them for secure server
     * verification later.
     */
    if (result.networkUnavailable) {
      _offlineMode = true;

      await _queueOfflineAttendance();

      return;
    }

    if (!result.success) {
      _fail(result.message);

      return;
    }

    await _showOnlineSuccess(result);
  }

  // ===========================================================================
  // QUEUE OFFLINE
  // ===========================================================================

  Future<void> _queueOfflineAttendance() async {
    final position = _position;

    final eventId = widget.event.id;

    if (eventId == null) {
      _fail('The selected event does not have a valid ID.');

      return;
    }

    if (position == null) {
      _fail('Your GPS location is unavailable.');

      return;
    }

    if (_centerFrame == null ||
        _blinkFrame == null ||
        _turnedFrame == null ||
        _smileFrame == null ||
        _returnedFrame == null) {
      _fail('The offline biometric evidence is incomplete. Please try again.');

      return;
    }

    if (!mounted || _disposed) {
      return;
    }

    setState(() {
      _running = false;

      _step = _AttendanceStep.verifying;

      _error = null;
    });

    /*
     * attendance_time is the moment the
     * complete offline verification evidence
     * was captured.
     *
     * sync_time will be generated later by
     * Laravel.
     */
    final attendanceTime = DateTime.now();

    final result = await AttendanceService.instance.queueOfflineAttendance(
      eventId: eventId,
      latitude: position.latitude,
      longitude: position.longitude,
      locationAccuracy: position.accuracy,
      attendanceTime: attendanceTime,
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

    await _showOfflineQueuedSuccess();
  }

  // ===========================================================================
  // ERROR / RETRY
  // ===========================================================================

  void _fail(String message) {
    if (!mounted || _disposed) {
      return;
    }

    setState(() {
      _running = false;

      _step = _AttendanceStep.failed;

      _error = message;
    });
  }

  Future<void> _retry() async {
    if (_disposed) {
      return;
    }

    setState(() {
      _initializing = true;

      _running = false;

      _offlineMode = false;

      _error = null;

      _step = _AttendanceStep.preparing;
    });

    _resetChallenge();

    try {
      final position = await _getCurrentPosition();

      _validateLocalGeofence(position);

      if (!mounted || _disposed) {
        return;
      }

      _position = position;

      _initializing = false;

      await _startOnlineChallenge();
    } catch (e) {
      if (!mounted || _disposed) {
        return;
      }

      setState(() {
        _initializing = false;

        _step = _AttendanceStep.failed;

        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ===========================================================================
  // SUCCESS DIALOGS
  // ===========================================================================

  Future<void> _showOnlineSuccess(AttendanceResult result) async {
    final attendance = result.data?['attendance'];

    String status = 'Recorded';

    if (attendance is Map && attendance['status'] != null) {
      final raw = attendance['status'].toString();

      if (raw.isNotEmpty) {
        status =
            '${raw[0].toUpperCase()}'
            '${raw.substring(1).toLowerCase()}';
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
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
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

  Future<void> _showOfflineQueuedSuccess() async {
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
                  color: gold,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.cloud_upload_outlined,
                  color: navy,
                  size: 40,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Saved Offline',
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
              const SizedBox(height: 16),
              const Text(
                'Your GPS position and biometric challenge were safely saved on this device.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF55555F),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3BF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Pending Verification & Sync',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: navy, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'When Laravel becomes reachable, the saved frames will be verified by MediaPipe, OpenCV and InsightFace before attendance is accepted.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF777783),
                  fontSize: 12,
                  height: 1.4,
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
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
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

  // ===========================================================================
  // TEXT
  // ===========================================================================

  String get _instruction {
    if (_offlineMode) {
      switch (_step) {
        case _AttendanceStep.preparing:
          return 'Preparing offline attendance...';

        case _AttendanceStep.center:
          return 'Look straight at the camera, then tap Capture';

        case _AttendanceStep.blink:
          return 'Close both eyes and keep them closed, then tap Capture';

        case _AttendanceStep.turn:
          return 'Turn your head clearly left or right, then tap Capture';

        case _AttendanceStep.smile:
          return 'Smile clearly, then tap Capture';

        case _AttendanceStep.returnCenter:
          return 'Return your face to the center, then tap Capture';

        case _AttendanceStep.verifying:
          return 'Saving attendance securely on this device...';

        case _AttendanceStep.failed:
          return 'Offline attendance stopped';
      }
    }

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

  // ===========================================================================
  // BUILD
  // ===========================================================================

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
              _buildEventCard(),

              if (_offlineMode) ...[
                const SizedBox(height: 12),
                _buildOfflineBanner(),
              ],

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

              Text(
                _offlineMode
                    ? 'Internet is unavailable. Follow each challenge carefully. Final liveness and identity verification will happen on the server when this record syncs.'
                    : 'Keep only your face inside the guide. Do not use a photo or another screen.',
                textAlign: TextAlign.center,
                style: const TextStyle(
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

              if (_offlineMode && _stepNumber >= 1 && _stepNumber <= 5) ...[
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: navy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _manualCaptureBusy ? null : _captureOfflineStep,
                    icon: _manualCaptureBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.camera_alt_rounded),
                    label: Text(
                      _manualCaptureBusy
                          ? 'Capturing...'
                          : 'Capture Step $_stepNumber',
                    ),
                  ),
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

  Widget _buildEventCard() {
    return Container(
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
    );
  }

  Widget _buildOfflineBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6D6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: gold),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.cloud_off_rounded, color: navy, size: 21),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'Offline Mode\nThis record will remain pending until Laravel verifies the saved biometric evidence.',
              style: TextStyle(
                color: navy,
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // DISPOSE
  // ===========================================================================

  @override
  void dispose() {
    _disposed = true;

    _running = false;

    _camera?.dispose();

    super.dispose();
  }
}
