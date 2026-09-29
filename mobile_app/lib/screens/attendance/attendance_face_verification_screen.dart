import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../models/event_item.dart';
import '../../services/attendance_service.dart';

enum _AttendanceStep {
  center,
  turn,
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

  // Fast two-capture flow. The final Laravel/Python verification remains
  // authoritative, so the phone does not upload camera frames repeatedly
  // while the user is moving.
  static const Duration centerCaptureDelay = Duration(milliseconds: 450);
  static const Duration turnCaptureDelay = Duration(milliseconds: 750);

  static const Duration offlinePoseDelay = Duration(milliseconds: 900);

  static const int maxBadFramesBeforeMessage = 8;

  CameraController? _camera;
  Position? _position;

  bool _running = false;
  bool _disposed = false;

  bool _offlineMode = false;
  bool _offlineCaptureBusy = false;

  int _offlineGeneration = 0;
  String? _error;

  _AttendanceStep _step = _AttendanceStep.center;

  XFile? _centerFrame;
  XFile? _turnedFrame;

  XFile? _offlineCenterFrame;
  XFile? _offlineTurnedFrame;

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
      final eventId = widget.event.id;
      if (eventId == null) {
        throw Exception('Invalid event ID.');
      }

      // Start all independent work together. This removes the old
      // camera -> GPS -> 300ms wait -> challenge waterfall.
      final cameraFuture = _startCamera();
      final positionFuture = _getPosition();
      final challengeFuture =
          AttendanceService.instance.requestLivenessChallenge(
        eventId: eventId,
      );

      await cameraFuture;

      if (!mounted || _disposed) {
        return;
      }

      setState(() {
        _step = _AttendanceStep.center;
        _error = null;
      });

      final results = await Future.wait<Object>([
        positionFuture,
        challengeFuture,
      ]);

      if (!mounted || _disposed) {
        return;
      }

      final position = results[0] as Position;
      final challengeResult = results[1] as LivenessChallengeResult;

      _position = position;
      _checkLocalGeofence(position);

      if (!challengeResult.success || challengeResult.challenge == null) {
        if (challengeResult.networkUnavailable) {
          _offlineDirection =
              DateTime.now().microsecond.isEven ? 'right' : 'left';
          _beginOffline();
          return;
        }

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
        'Location services are disabled. Turn on Location/GPS and try again.',
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
        'Location permission is permanently denied. Enable it from the app settings.',
      );
    }

    // Medium accuracy is enough for the event geofence and is substantially
    // faster than waiting for a high-accuracy GPS fix.
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 3),
        ),
      );
    } catch (_) {
      final lastKnown = await Geolocator.getLastKnownPosition();

      if (lastKnown != null) {
        return lastKnown;
      }

      throw Exception(
        'Unable to get your location. Keep Location/GPS turned on and try again.',
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
      _error = null;
    });
  }

  void _resetEvidence() {
    _centerFrame = null;
    _turnedFrame = null;
    _offlineCenterFrame = null;
    _offlineTurnedFrame = null;
  }

  Future<void> _startOnline() async {
    final camera = _camera;

    if (_running ||
        camera == null ||
        !camera.value.isInitialized ||
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

    try {
      // One local capture instead of repeatedly uploading frames to Laravel
      // while waiting for a centered pose.
      await Future<void>.delayed(centerCaptureDelay);

      if (!mounted || _disposed || !_running) {
        return;
      }

      _centerFrame = await camera.takePicture();

      if (!mounted || _disposed || !_running) {
        return;
      }

      setState(() {
        _step = _AttendanceStep.turn;
        _error = null;
      });

      // Give the user a short, predictable window to turn toward the
      // server-selected direction. Python performs the authoritative pose
      // check on the two submitted frames.
      await Future<void>.delayed(turnCaptureDelay);

      if (!mounted || _disposed || !_running) {
        return;
      }

      _turnedFrame = await camera.takePicture();

      if (!mounted || _disposed || !_running) {
        return;
      }

      await _submitOnline();
    } catch (e) {
      if (!mounted || _disposed) {
        return;
      }

      _fail(_cleanError(e));
    }
  }

  Future<void> _submitOnline() async {
    final eventId = widget.event.id;
    final position = _position;
    final centerFrame = _centerFrame;
    final turnedFrame = _turnedFrame;

    if (eventId == null ||
        position == null ||
        centerFrame == null ||
        turnedFrame == null ||
        _challengeNonce == null ||
        _challengeSessionId == null) {
      _fail('Attendance evidence is incomplete. Please try again.');
      return;
    }

    if (!mounted) return;

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
      centerFrame: centerFrame,
      turnedFrame: turnedFrame,
      challengeNonce: _challengeNonce!,
      sessionId: _challengeSessionId!,
    );

    if (!mounted || _disposed) return;

    if (result.networkUnavailable) {
      await _saveOffline(
        centerFrame: centerFrame,
        turnedFrame: turnedFrame,
      );
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
    if (_offlineMode || _disposed) return;

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
      if (!_offlineSequenceActive(generation)) return;

      setState(() {
        _step = _AttendanceStep.center;
        _error = null;
      });

      await Future<void>.delayed(offlinePoseDelay);
      if (!_offlineSequenceActive(generation)) return;

      final camera = _camera;
      if (camera == null || !camera.value.isInitialized) {
        throw Exception('Camera is not ready.');
      }

      if (mounted) {
        setState(() => _offlineCaptureBusy = true);
      }

      final center = await camera.takePicture();
      _offlineCenterFrame = center;

      if (mounted) {
        setState(() {
          _offlineCaptureBusy = false;
          _step = _AttendanceStep.turn;
        });
      }

      await Future<void>.delayed(offlinePoseDelay);
      if (!_offlineSequenceActive(generation)) return;

      if (mounted) {
        setState(() => _offlineCaptureBusy = true);
      }

      final turned = await camera.takePicture();
      _offlineTurnedFrame = turned;

      if (mounted) {
        setState(() {
          _offlineCaptureBusy = false;
          _step = _AttendanceStep.verifying;
        });
      }

      if (!_offlineSequenceActive(generation)) return;

      await _saveOffline(
        centerFrame: center,
        turnedFrame: turned,
      );
    } catch (e) {
      if (_offlineSequenceActive(generation)) {
        _fail(_cleanError(e));
      }
    } finally {
      if (mounted && !_disposed) {
        setState(() => _offlineCaptureBusy = false);
      }
    }
  }

  Future<void> _saveOffline({
    XFile? centerFrame,
    XFile? turnedFrame,
  }) async {
    final eventId = widget.event.id;
    final position = _position;
    final center = centerFrame ?? _offlineCenterFrame;
    final turned = turnedFrame ?? _offlineTurnedFrame;

    if (eventId == null || position == null) {
      _fail('Event or GPS data is missing.');
      return;
    }

    if (center == null || turned == null) {
      _fail('Offline biometric evidence is incomplete.');
      return;
    }

    if (!mounted) return;

    setState(() {
      _offlineMode = true;
      _running = false;
      _step = _AttendanceStep.verifying;
      _offlineCaptureBusy = true;
      _error = null;
    });

    final result = await AttendanceService.instance.queueOfflineAttendance(
      eventId: eventId,
      latitude: position.latitude,
      longitude: position.longitude,
      locationAccuracy: position.accuracy,
      attendanceTime: DateTime.now(),
      centerFrame: center,
      turnedFrame: turned,
      livenessDirection: _offlineDirection,
    );

    if (!mounted || _disposed) return;

    setState(() => _offlineCaptureBusy = false);

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

    if (mounted) {
      setState(() {
        _step = _AttendanceStep.center;
        _error = null;
      });
    }

    try {
      if (_camera == null || !_camera!.value.isInitialized) {
        await _startCamera();
      }

      if (!mounted || _disposed) {
        return;
      }

      final positionFuture = _getPosition();
      final challengeFuture =
          AttendanceService.instance.requestLivenessChallenge(
        eventId: widget.event.id!,
      );

      final results = await Future.wait<Object>([
        positionFuture,
        challengeFuture,
      ]);

      if (!mounted || _disposed) {
        return;
      }

      final position = results[0] as Position;
      final challengeResult = results[1] as LivenessChallengeResult;

      _position = position;
      _checkLocalGeofence(position);

      if (!challengeResult.success || challengeResult.challenge == null) {
        if (challengeResult.networkUnavailable) {
          _offlineDirection =
              DateTime.now().microsecond.isEven ? 'right' : 'left';
          _beginOffline();
          return;
        }

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
              ? 'Capturing your centered face...'
              : 'Look straight and hold still';

        case _AttendanceStep.turn:
          return _offlineCaptureBusy
              ? 'Capturing your head turn...'
              : (_offlineDirection == 'right'
                    ? 'Turn your head to your RIGHT → and hold'
                    : '← Turn your head to your LEFT and hold');

        case _AttendanceStep.verifying:
          return 'Saving offline attendance...';

        case _AttendanceStep.failed:
          return 'Attendance stopped';

      }
    }

    switch (_step) {
      case _AttendanceStep.center:
        return 'Look straight at the camera';

      case _AttendanceStep.turn:
        return _challengeDirection == 'right'
            ? 'Turn your head to your RIGHT →'
            : '← Turn your head to your LEFT';

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
                    camera == null || !camera.value.isInitialized
                    ? const SizedBox.expand()
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
                        'Step $_stepNumber of 2',
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
