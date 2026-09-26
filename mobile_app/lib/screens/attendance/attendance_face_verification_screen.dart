import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../models/event_item.dart';
import '../../services/attendance_service.dart';

enum _AttendanceStep {
  preparing,
  center,
  turn,
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

  // Tolerant live guidance: the face can sit slightly off-center.
  // Final Laravel/Python verification remains authoritative.
  static const double centerYawLimit = 0.30;
  static const double turnYawDelta = 0.07;
  static const double returnYawDelta = 0.16;

  static const Duration captureInterval = Duration(milliseconds: 400);
  static const int stableFramesRequired = 2;

  // Offline capture still collects multiple frames because
  // MediaPipe cannot be reached while the phone is offline.
  static const int centerBurstCount = 3;
  static const int turnBurstCount = 4;
  static const int returnBurstCount = 3;

  static const Duration offlinePoseDelay = Duration(milliseconds: 1400);

  static const Duration offlineBurstGap = Duration(milliseconds: 160);

  static const int maxBadFramesBeforeMessage = 8;

  CameraController? _camera;
  Position? _position;

  bool _initializing = true;
  bool _running = false;
  bool _analyzing = false;
  bool _disposed = false;

  bool _offlineMode = false;
  bool _offlineCaptureBusy = false;

  int _offlineGeneration = 0;
  int _badFrames = 0;
  int _stableCenterFrames = 0;
  int _stableTurnFrames = 0;
  int _stableReturnFrames = 0;

  double? _bestTurnDelta;
  double? _bestReturnDelta;

  String? _error;

  _AttendanceStep _step = _AttendanceStep.preparing;

  XFile? _centerFrame;
  XFile? _turnedFrame;
  XFile? _returnedFrame;

  List<XFile> _centerCandidates = <XFile>[];
  List<XFile> _turnedCandidates = <XFile>[];
  List<XFile> _returnedCandidates = <XFile>[];

  double? _centerYaw;

  String? _challengeDirection;
  String? _challengeNonce;
  String? _challengeSessionId;
  String _offlineDirection = 'left';

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      if (widget.event.id == null) {
        throw Exception('Invalid event ID.');
      }

      await _startCamera();

      if (!mounted || _disposed) {
        return;
      }

      final position = await _getPosition();

      if (!mounted || _disposed) {
        return;
      }

      _position = position;

      _checkLocalGeofence(position);

      if (!mounted || _disposed) {
        return;
      }

      await Future<void>.delayed(const Duration(milliseconds: 300));

      if (!mounted || _disposed) {
        return;
      }

      final challengeResult = await AttendanceService.instance
          .requestLivenessChallenge(eventId: widget.event.id!);

      if (!mounted || _disposed) {
        return;
      }

      if (challengeResult.networkUnavailable) {
        _offlineDirection = Random.secure().nextBool() ? 'right' : 'left';
        _beginOffline();
        return;
      }

      if (!challengeResult.success || challengeResult.challenge == null) {
        throw Exception(challengeResult.message);
      }

      final challenge = challengeResult.challenge!;
      _challengeDirection = challenge.direction;
      _offlineDirection = challenge.direction;
      _challengeNonce = challenge.nonce;
      _challengeSessionId = challenge.sessionId;

      await _startOnline();
    } catch (e) {
      if (!mounted || _disposed) {
        return;
      }

      setState(() {
        _initializing = false;
        _running = false;
        _step = _AttendanceStep.failed;
        _error = _cleanError(e);
      });
    }
  }

  String _cleanError(Object error) {
    return error.toString().replaceFirst('Exception: ', '');
  }

  Future<Position> _getPosition() async {
    final enabled = await Geolocator.isLocationServiceEnabled();

    if (!enabled) {
      throw Exception(
        'Location services are disabled. '
        'Turn on Location/GPS and try again.',
      );
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw Exception('Location permission is required to record attendance.');
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permission is permanently denied. '
        'Enable it from the app settings.',
      );
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (_) {
      final lastKnown = await Geolocator.getLastKnownPosition();

      if (lastKnown != null) {
        return lastKnown;
      }

      throw Exception(
        'Unable to get your location. '
        'Keep Location/GPS turned on and try again.',
      );
    }
  }

  void _checkLocalGeofence(Position position) {
    if (!widget.event.geofenceEnabled) {
      return;
    }

    final latitude = widget.event.latitude;
    final longitude = widget.event.longitude;
    final radius = widget.event.geofenceRadius;

    if (latitude == null || longitude == null || radius <= 0) {
      return;
    }

    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      latitude,
      longitude,
    );

    if (distance > radius) {
      final remaining = distance - radius;

      throw Exception(
        'You are outside the event area. Move about '
        '${remaining.round()} m closer to the event location and try again.',
      );
    }
  }

  Future<void> _startCamera() async {
    final cameras = await availableCameras();

    if (cameras.isEmpty) {
      throw Exception('No camera is available on this device.');
    }

    CameraDescription selectedCamera = cameras.first;

    for (final camera in cameras) {
      if (camera.lensDirection == CameraLensDirection.front) {
        selectedCamera = camera;
        break;
      }
    }

    final controller = CameraController(
      selectedCamera,
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
    });
  }

  void _resetEvidence() {
    _centerFrame = null;
    _turnedFrame = null;
    _returnedFrame = null;

    _centerCandidates = <XFile>[];
    _turnedCandidates = <XFile>[];
    _returnedCandidates = <XFile>[];

    _centerYaw = null;

    _badFrames = 0;
    _stableCenterFrames = 0;
    _stableTurnFrames = 0;
    _stableReturnFrames = 0;
    _bestTurnDelta = null;
    _bestReturnDelta = null;
  }

  Future<void> _startOnline() async {
    if (_running ||
        _camera == null ||
        !_camera!.value.isInitialized ||
        _disposed) {
      return;
    }

    _resetEvidence();

    _offlineMode = false;

    if (!mounted) {
      return;
    }

    setState(() {
      _running = true;
      _step = _AttendanceStep.center;
      _error = null;
    });

    while (mounted &&
        !_disposed &&
        _running &&
        !_offlineMode &&
        _step != _AttendanceStep.verifying &&
        _step != _AttendanceStep.failed) {
      await _analyzeOnlineFrame();

      if (!_running || _offlineMode || _disposed) {
        break;
      }

      await Future<void>.delayed(captureInterval);
    }
  }

  Future<void> _analyzeOnlineFrame() async {
    if (_analyzing || !_running || _disposed) {
      return;
    }

    final camera = _camera;

    if (camera == null ||
        !camera.value.isInitialized ||
        camera.value.isTakingPicture) {
      return;
    }

    _analyzing = true;

    try {
      final frame = await camera.takePicture();

      final result = await AttendanceService.instance.analyzeLivenessFrame(
        frame: frame,
      );

      if (!mounted || _disposed) {
        return;
      }

      if (result.networkUnavailable) {
        _beginOffline();
        return;
      }

      if (!result.success || !result.faceDetected) {
        _badFrames++;

        if (_badFrames >= maxBadFramesBeforeMessage) {
          setState(() {
            _error = result.message.isNotEmpty
                ? result.message
                : 'Keep one face clearly visible inside the camera.';
          });
        }

        // Do not move to another challenge.
        return;
      }

      final yaw = result.yaw;

      if (yaw == null) {
        _badFrames++;

        if (_badFrames >= maxBadFramesBeforeMessage) {
          setState(() {
            _error = 'Keep your face clearly visible while the camera reads your head position.';
          });
        }

        return;
      }

      if (!result.faceInComfortableZone) {
        _badFrames++;

        if (_badFrames >= maxBadFramesBeforeMessage) {
          setState(() {
            _error = 'Move slightly closer to the middle so your whole face stays visible.';
          });
        }

        return;
      }

      _badFrames = 0;

      if (_error != null) {
        setState(() {
          _error = null;
        });
      }

      await _processOnlineMeasurement(frame: frame, yaw: yaw);
    } catch (e) {
      if (!mounted || _disposed) {
        return;
      }

      setState(() {
        _error = _cleanError(e);
      });
    } finally {
      _analyzing = false;
    }
  }

  Future<void> _processOnlineMeasurement({
    required XFile frame,
    required double yaw,
  }) async {
    switch (_step) {
      case _AttendanceStep.center:
        if (yaw.abs() <= centerYawLimit) {
          _stableCenterFrames++;

          final currentBest = _centerYaw;
          if (currentBest == null || yaw.abs() < currentBest.abs()) {
            _centerFrame = frame;
            _centerYaw = yaw;
          }

          if (_stableCenterFrames >= stableFramesRequired) {
            if (!mounted) {
              return;
            }

            setState(() {
              _step = _AttendanceStep.turn;
              _error = null;
            });
          }
        } else {
          _stableCenterFrames = 0;
        }
        break;

      case _AttendanceStep.turn:
        final centerYaw = _centerYaw;

        if (centerYaw == null) {
          _stableCenterFrames = 0;
          return;
        }

        final direction = _challengeDirection;
        if (direction == null) {
          return;
        }

        final signedDelta = yaw - centerYaw;
        final requestedDelta = direction == 'left' ? signedDelta : -signedDelta;

        if (requestedDelta >= turnYawDelta) {
          _stableTurnFrames++;

          if (_bestTurnDelta == null || requestedDelta > _bestTurnDelta!) {
            _bestTurnDelta = requestedDelta;
            _turnedFrame = frame;
          }

          if (_stableTurnFrames >= stableFramesRequired) {
            if (!mounted) {
              return;
            }

            setState(() {
              _step = _AttendanceStep.returnCenter;
              _error = null;
            });
          }
        } else {
          _stableTurnFrames = 0;
        }
        break;

      case _AttendanceStep.returnCenter:
        final centerYaw = _centerYaw;

        if (centerYaw == null) {
          _stableReturnFrames = 0;
          return;
        }

        final centered = yaw.abs() <= centerYawLimit;
        final returned = (yaw - centerYaw).abs() <= returnYawDelta;

        if (centered && returned) {
          _stableReturnFrames++;

          final difference = (yaw - centerYaw).abs();

          if (_bestReturnDelta == null || difference < _bestReturnDelta!) {
            _bestReturnDelta = difference;
            _returnedFrame = frame;
          }

          if (_stableReturnFrames >= stableFramesRequired) {
            await _submitOnline();
          }
        } else {
          _stableReturnFrames = 0;
        }
        break;

      case _AttendanceStep.preparing:
      case _AttendanceStep.verifying:
      case _AttendanceStep.failed:
        break;
    }
  }

  Future<void> _submitOnline() async {
    final eventId = widget.event.id;
    final position = _position;

    final centerFrame = _centerFrame;
    final turnedFrame = _turnedFrame;
    final returnedFrame = _returnedFrame;

    if (eventId == null ||
        position == null ||
        centerFrame == null ||
        turnedFrame == null ||
        returnedFrame == null) {
      _fail('Attendance evidence is incomplete. Please try again.');
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _running = false;
      _step = _AttendanceStep.verifying;
      _error = null;
    });

    // Keep the current backend/service API unchanged.
    //
    // Only these actual challenges are performed:
    //
    // center -> turn -> center
    //
    // The old blink/smile parameters are filled
    // with existing accepted frames for compatibility.
    final result = await AttendanceService.instance.mobileCheckIn(
      eventId: eventId,
      latitude: position.latitude,
      longitude: position.longitude,
      locationAccuracy: position.accuracy,
      centerFrame: centerFrame,
      blinkFrame: centerFrame,
      turnedFrame: turnedFrame,
      smileFrame: turnedFrame,
      returnedFrame: returnedFrame,
      challengeNonce: _challengeNonce!,
      sessionId: _challengeSessionId!,
    );

    if (!mounted || _disposed) {
      return;
    }

    if (result.networkUnavailable) {
      _centerCandidates = <XFile>[centerFrame];

      _turnedCandidates = <XFile>[turnedFrame];

      _returnedCandidates = <XFile>[returnedFrame];

      await _saveOffline();
      return;
    }

    if (!result.success) {
      _fail(result.message);
      return;
    }

    await _showSuccess(
      title: 'Attendance Recorded',
      message: result.message,
      offline: false,
    );
  }

  void _beginOffline() {
    if (_offlineMode || _disposed) {
      return;
    }

    _offlineGeneration++;

    final generation = _offlineGeneration;

    _resetEvidence();

    _offlineMode = true;
    _running = false;

    if (mounted) {
      setState(() {
        _step = _AttendanceStep.center;
        _error = null;
      });
    }

    Future<void>.microtask(() => _runOfflineSequence(generation));
  }

  bool _offlineSequenceActive(int generation) {
    return mounted &&
        !_disposed &&
        _offlineMode &&
        generation == _offlineGeneration;
  }

  Future<void> _runOfflineSequence(int generation) async {
    try {
      // CENTER
      if (!_offlineSequenceActive(generation)) {
        return;
      }

      setState(() {
        _step = _AttendanceStep.center;
        _error = null;
      });

      await Future<void>.delayed(offlinePoseDelay);

      if (!_offlineSequenceActive(generation)) {
        return;
      }

      _centerCandidates = await _captureOfflineBurst(
        centerBurstCount,
        generation,
      );

      // TURN LEFT OR RIGHT
      if (!_offlineSequenceActive(generation)) {
        return;
      }

      setState(() {
        _step = _AttendanceStep.turn;
      });

      await Future<void>.delayed(offlinePoseDelay);

      if (!_offlineSequenceActive(generation)) {
        return;
      }

      _turnedCandidates = await _captureOfflineBurst(
        turnBurstCount,
        generation,
      );

      // RETURN CENTER
      if (!_offlineSequenceActive(generation)) {
        return;
      }

      setState(() {
        _step = _AttendanceStep.returnCenter;
      });

      await Future<void>.delayed(offlinePoseDelay);

      if (!_offlineSequenceActive(generation)) {
        return;
      }

      _returnedCandidates = await _captureOfflineBurst(
        returnBurstCount,
        generation,
      );

      if (!_offlineSequenceActive(generation)) {
        return;
      }

      await _saveOffline();
    } catch (e) {
      if (!_offlineSequenceActive(generation)) {
        return;
      }

      _fail(_cleanError(e));
    }
  }

  Future<List<XFile>> _captureOfflineBurst(int count, int generation) async {
    final camera = _camera;

    if (camera == null || !camera.value.isInitialized) {
      throw Exception('Camera is not ready.');
    }

    final frames = <XFile>[];

    if (mounted) {
      setState(() {
        _offlineCaptureBusy = true;
      });
    }

    try {
      for (var i = 0; i < count; i++) {
        if (!_offlineSequenceActive(generation)) {
          break;
        }

        while (camera.value.isTakingPicture) {
          await Future<void>.delayed(const Duration(milliseconds: 30));

          if (!_offlineSequenceActive(generation)) {
            return frames;
          }
        }

        final frame = await camera.takePicture();

        frames.add(frame);

        if (i < count - 1) {
          await Future<void>.delayed(offlineBurstGap);
        }
      }
    } finally {
      if (mounted && !_disposed) {
        setState(() {
          _offlineCaptureBusy = false;
        });
      }
    }

    if (frames.isEmpty) {
      throw Exception('Unable to capture offline biometric evidence.');
    }

    return frames;
  }

  Future<void> _saveOffline() async {
    final eventId = widget.event.id;
    final position = _position;

    if (eventId == null || position == null) {
      _fail('Event or GPS data is missing.');
      return;
    }

    if (_centerCandidates.isEmpty ||
        _turnedCandidates.isEmpty ||
        _returnedCandidates.isEmpty) {
      _fail('Offline biometric evidence is incomplete.');
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _offlineMode = true;
      _running = false;
      _step = _AttendanceStep.verifying;
      _offlineCaptureBusy = true;
      _error = null;
    });

    // The existing offline service still expects
    // five candidate lists.
    //
    // Reuse the center and turn lists for the old
    // blink/smile slots so no service/database
    // changes are required.
    final result = await AttendanceService.instance.queueOfflineAttendance(
      eventId: eventId,
      latitude: position.latitude,
      longitude: position.longitude,
      locationAccuracy: position.accuracy,
      attendanceTime: DateTime.now(),
      centerCandidates: _centerCandidates,
      blinkCandidates: _centerCandidates,
      turnedCandidates: _turnedCandidates,
      smileCandidates: _turnedCandidates,
      returnedCandidates: _returnedCandidates,
      livenessDirection: _offlineDirection,
    );

    if (!mounted || _disposed) {
      return;
    }

    setState(() {
      _offlineCaptureBusy = false;
    });

    if (!result.success) {
      _fail(result.message);
      return;
    }

    await _showSuccess(
      title: 'Attendance Saved Offline',
      message: result.message,
      offline: true,
    );
  }

  void _fail(String message) {
    if (!mounted || _disposed) {
      return;
    }

    _running = false;
    _offlineMode = false;
    _offlineCaptureBusy = false;

    _offlineGeneration++;

    setState(() {
      _step = _AttendanceStep.failed;
      _error = message;
    });
  }

  Future<void> _retry() async {
    if (_disposed) {
      return;
    }

    _running = false;
    _offlineMode = false;
    _offlineCaptureBusy = false;

    _offlineGeneration++;

    _resetEvidence();

    setState(() {
      _step = _AttendanceStep.preparing;
      _error = null;
    });

    try {
      if (_camera == null || !_camera!.value.isInitialized) {
        setState(() {
          _initializing = true;
        });

        await _startCamera();
      }

      if (!mounted || _disposed) {
        return;
      }

      final position = await _getPosition();

      if (!mounted || _disposed) {
        return;
      }

      _position = position;

      _checkLocalGeofence(position);

      await _startOnline();
    } catch (e) {
      if (!mounted || _disposed) {
        return;
      }

      _fail(_cleanError(e));
    }
  }

  Future<void> _showSuccess({
    required String title,
    required String message,
    required bool offline,
  }) async {
    if (!mounted || _disposed) {
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: offline
                      ? const Color(0xFFFFF3CD)
                      : const Color(0xFFE8F8EE),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  offline
                      ? Icons.cloud_off_rounded
                      : Icons.check_circle_rounded,
                  size: 42,
                  color: offline
                      ? const Color(0xFFB88600)
                      : const Color(0xFF0A9F4B),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: navy,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF626273), height: 1.4),
              ),
              if (offline) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8DF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'This attendance is pending and will be '
                    'synchronized when internet becomes available.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: navy,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: navy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || _disposed) {
      return;
    }

    Navigator.of(context).pop(true);
  }

  String get _instruction {
    if (_offlineMode) {
      switch (_step) {
        case _AttendanceStep.center:
          return _offlineCaptureBusy
              ? 'Capturing centered frames...'
              : 'Look straight and hold still';

        case _AttendanceStep.turn:
          return _offlineCaptureBusy
              ? 'Capturing head-turn frames...'
              : (_offlineDirection == 'right'
                    ? 'Turn your head to your RIGHT → and hold'
                    : '← Turn your head to your LEFT and hold');

        case _AttendanceStep.returnCenter:
          return _offlineCaptureBusy
              ? 'Capturing final centered frames...'
              : 'Return your face to center and hold';

        case _AttendanceStep.verifying:
          return 'Saving offline attendance...';

        case _AttendanceStep.failed:
          return 'Attendance stopped';

        case _AttendanceStep.preparing:
          return 'Preparing camera...';
      }
    }

    switch (_step) {
      case _AttendanceStep.preparing:
        return 'Preparing camera...';

      case _AttendanceStep.center:
        return 'Look straight at the camera';

      case _AttendanceStep.turn:
        return _challengeDirection == 'right'
            ? 'Turn your head to your RIGHT →'
            : '← Turn your head to your LEFT';

      case _AttendanceStep.returnCenter:
        return 'Return your face to center';

      case _AttendanceStep.verifying:
        return 'Verifying attendance...';

      case _AttendanceStep.failed:
        return 'Verification stopped';
    }
  }

  int get _stepNumber {
    switch (_step) {
      case _AttendanceStep.center:
        return 1;

      case _AttendanceStep.turn:
        return 2;

      case _AttendanceStep.returnCenter:
        return 3;

      case _AttendanceStep.preparing:
      case _AttendanceStep.verifying:
      case _AttendanceStep.failed:
        return 0;
    }
  }

  Widget _buildCameraPreview(CameraController camera) {
    return CameraPreview(camera);
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;

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
        child: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE8E8F0)),
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
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 16,
                          color: Color(0xFF747484),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            widget.event.venue,
                            style: const TextStyle(
                              color: Color(0xFF747484),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (widget.event.geofenceEnabled) ...[
                    const SizedBox(height: 10),
                    const Row(
                      children: [
                        Icon(
                          Icons.my_location_rounded,
                          size: 16,
                          color: Color(0xFF53607A),
                        ),
                        SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Location check: you must be within the event area.',
                            style: TextStyle(
                              color: Color(0xFF53607A),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            if (_offlineMode)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3CD),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: gold),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.cloud_off_rounded, color: navy),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Offline Mode — attendance evidence '
                        'will be stored on this device.',
                        style: TextStyle(
                          color: navy,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            Expanded(
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(24),
                ),
                child:
                    _initializing ||
                        camera == null ||
                        !camera.value.isInitialized
                    ? const Center(
                        child: CircularProgressIndicator(color: gold),
                      )
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          _buildCameraPreview(camera),
                          Positioned(
                            left: 18,
                            top: 18,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Colors.greenAccent,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'LIVE',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_offlineMode)
                            Positioned(
                              right: 18,
                              top: 18,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: gold,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'OFFLINE',
                                  style: TextStyle(
                                    color: navy,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(18),
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Colors.transparent, Colors.black87],
                                ),
                              ),
                              child: Text(
                                _offlineMode
                                    ? 'Offline biometric capture'
                                    : 'Secure biometric verification',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 15,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7D6),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: gold),
                ),
                child: Column(
                  children: [
                    if (_stepNumber > 0) ...[
                      Text(
                        'Step $_stepNumber of 3',
                        style: const TextStyle(
                          color: Color(0xFF777787),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      _instruction,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: navy,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (_offlineCaptureBusy || _step == _AttendanceStep.verifying)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: CircularProgressIndicator(color: navy),
              ),

            if (_error != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFB71C1C)),
                ),
              ),

            if (_step == _AttendanceStep.failed)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: navy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try Again'),
                  ),
                ),
              ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _running = false;
    _offlineMode = false;

    _offlineGeneration++;

    _camera?.dispose();

    super.dispose();
  }
}
