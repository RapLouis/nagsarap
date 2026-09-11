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

  // Offline bursts.
  static const int centerBurstCount = 3;
  static const int blinkBurstCount = 5;
  static const int turnBurstCount = 4;
  static const int smileBurstCount = 4;
  static const int returnBurstCount = 3;

  static const Duration offlinePoseDelay = Duration(milliseconds: 1400);

  static const Duration offlineBurstGap = Duration(milliseconds: 160);

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

  String? _error;

  _AttendanceStep _step = _AttendanceStep.preparing;

  // Online accepted frames.
  XFile? _centerFrame;
  XFile? _blinkFrame;
  XFile? _turnedFrame;
  XFile? _smileFrame;
  XFile? _returnedFrame;

  // Offline burst frames.
  List<XFile> _centerCandidates = <XFile>[];

  List<XFile> _blinkCandidates = <XFile>[];

  List<XFile> _turnedCandidates = <XFile>[];

  List<XFile> _smileCandidates = <XFile>[];

  List<XFile> _returnedCandidates = <XFile>[];

  double? _centerYaw;
  double? _centerEyeOpenness;
  double? _centerMouthWidth;

  bool _blinkClosedDetected = false;

  static const int maxBadFramesBeforeMessage = 6;

  Duration get _captureInterval {
    if (_step == _AttendanceStep.blink) {
      return blinkCaptureInterval;
    }

    return normalCaptureInterval;
  }

  bool get _waitingForBlinkReopen {
    return _step == _AttendanceStep.blink && _blinkClosedDetected;
  }

  @override
  void initState() {
    super.initState();

    _prepare();
  }

  // ===========================================================================
  // PREPARE
  // ===========================================================================

  Future<void> _prepare() async {
    try {
      if (widget.event.id == null) {
        throw Exception('Invalid event ID.');
      }

      final position = await _getPosition();

      if (!mounted || _disposed) {
        return;
      }

      _position = position;

      _checkLocalGeofence(position);

      await _startCamera();
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

  Future<Position> _getPosition() async {
    final enabled = await Geolocator.isLocationServiceEnabled();

    if (!enabled) {
      throw Exception('Location services are disabled.');
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Location permission is required.');
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
  }

  void _checkLocalGeofence(Position position) {
    if (!widget.event.geofenceEnabled) {
      return;
    }

    final lat = widget.event.latitude;

    final lng = widget.event.longitude;

    final radius = widget.event.geofenceRadius;

    if (lat == null || lng == null || radius <= 0) {
      return;
    }

    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      lat,
      lng,
    );

    if (distance > radius) {
      throw Exception(
        'You are ${distance.toStringAsFixed(1)} m '
        'from the event location. '
        'Allowed radius: $radius m.',
      );
    }
  }

  // ===========================================================================
  // CAMERA
  // ===========================================================================

  Future<void> _startCamera() async {
    final cameras = await availableCameras();

    if (cameras.isEmpty) {
      throw StateError('No camera available.');
    }

    var camera = cameras.first;

    for (final item in cameras) {
      if (item.lensDirection == CameraLensDirection.front) {
        camera = item;
        break;
      }
    }

    final controller = CameraController(
      camera,
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

    await Future<void>.delayed(const Duration(milliseconds: 800));

    await _startOnline();
  }

  void _reset() {
    _centerFrame = null;
    _blinkFrame = null;
    _turnedFrame = null;
    _smileFrame = null;
    _returnedFrame = null;

    _centerCandidates = <XFile>[];

    _blinkCandidates = <XFile>[];

    _turnedCandidates = <XFile>[];

    _smileCandidates = <XFile>[];

    _returnedCandidates = <XFile>[];

    _centerYaw = null;
    _centerEyeOpenness = null;
    _centerMouthWidth = null;

    _blinkClosedDetected = false;
    _badFrames = 0;
  }

  // ===========================================================================
  // ONLINE
  // ===========================================================================

  Future<void> _startOnline() async {
    if (_running ||
        _camera == null ||
        !_camera!.value.isInitialized ||
        _disposed) {
      return;
    }

    _reset();

    _offlineMode = false;

    setState(() {
      _running = true;
      _step = _AttendanceStep.center;
    });

    while (mounted &&
        !_disposed &&
        _running &&
        !_offlineMode &&
        _step != _AttendanceStep.verifying &&
        _step != _AttendanceStep.failed) {
      await _onlineFrame();

      if (!_running || _offlineMode || _disposed) {
        break;
      }

      await Future<void>.delayed(_captureInterval);
    }
  }

  Future<void> _onlineFrame() async {
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
            _error = result.message;
          });
        }

        return;
      }

      final yaw = result.yaw;

      final eye = result.eyeOpenness;

      final mouth = result.mouthWidth;

      if (yaw == null || eye == null || mouth == null) {
        return;
      }

      _badFrames = 0;

      if (_error != null) {
        setState(() {
          _error = null;
        });
      }

      await _processOnline(frame: frame, yaw: yaw, eye: eye, mouth: mouth);
    } finally {
      _analyzing = false;
    }
  }

  Future<void> _processOnline({
    required XFile frame,
    required double yaw,
    required double eye,
    required double mouth,
  }) async {
    switch (_step) {
      case _AttendanceStep.center:
        if (yaw.abs() <= centerYawLimit) {
          _centerFrame = frame;
          _centerYaw = yaw;
          _centerEyeOpenness = eye;
          _centerMouthWidth = mouth;
          _blinkClosedDetected = false;

          setState(() {
            _step = _AttendanceStep.blink;
          });
        }
        break;

      case _AttendanceStep.blink:
        final baseline = _centerEyeOpenness;

        if (baseline == null) {
          return;
        }

        if (!_blinkClosedDetected) {
          if (eye <= baseline * blinkRatio) {
            _blinkClosedDetected = true;

            _blinkFrame = frame;

            setState(() {});
          }
        } else if (eye >= baseline * blinkReopenRatio) {
          setState(() {
            _step = _AttendanceStep.turn;
          });
        }
        break;

      case _AttendanceStep.turn:
        final center = _centerYaw;

        if (center != null && (yaw - center).abs() >= turnYawDelta) {
          _turnedFrame = frame;

          setState(() {
            _step = _AttendanceStep.smile;
          });
        }
        break;

      case _AttendanceStep.smile:
        final baseline = _centerMouthWidth;

        if (baseline != null && mouth >= baseline * smileRatio) {
          _smileFrame = frame;

          setState(() {
            _step = _AttendanceStep.returnCenter;
          });
        }
        break;

      case _AttendanceStep.returnCenter:
        final center = _centerYaw;

        if (center != null &&
            yaw.abs() <= centerYawLimit &&
            (yaw - center).abs() <= returnYawDelta) {
          _returnedFrame = frame;

          await _submitOnline();
        }
        break;

      default:
        break;
    }
  }

  // ===========================================================================
  // OFFLINE BURST
  // ===========================================================================

  void _beginOffline() {
    if (_offlineMode || _disposed) {
      return;
    }

    _running = false;
    _offlineMode = true;

    _reset();

    final generation = ++_offlineGeneration;

    setState(() {
      _step = _AttendanceStep.center;
      _error = null;
    });

    Future<void>.delayed(const Duration(milliseconds: 500), () {
      if (_offlineActive(generation)) {
        _runOffline(generation);
      }
    });
  }

  bool _offlineActive(int generation) {
    return mounted &&
        !_disposed &&
        _offlineMode &&
        generation == _offlineGeneration;
  }

  Future<bool> _wait(int generation, Duration duration) async {
    const interval = Duration(milliseconds: 100);

    var elapsed = Duration.zero;

    while (elapsed < duration) {
      if (!_offlineActive(generation)) {
        return false;
      }

      await Future<void>.delayed(interval);

      elapsed += interval;
    }

    return true;
  }

  Future<void> _prepareStep(int generation, _AttendanceStep step) async {
    if (!_offlineActive(generation)) {
      return;
    }

    setState(() {
      _step = step;
      _error = null;
    });

    await _wait(generation, offlinePoseDelay);
  }

  Future<List<XFile>> _burst(int generation, int count) async {
    final camera = _camera;

    if (camera == null || !camera.value.isInitialized) {
      return <XFile>[];
    }

    final frames = <XFile>[];

    setState(() {
      _offlineCaptureBusy = true;
    });

    try {
      for (var i = 0; i < count; i++) {
        if (!_offlineActive(generation)) {
          break;
        }

        while (camera.value.isTakingPicture) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }

        frames.add(await camera.takePicture());

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

    return frames;
  }

  Future<void> _runOffline(int generation) async {
    try {
      await _prepareStep(generation, _AttendanceStep.center);

      _centerCandidates = await _burst(generation, centerBurstCount);

      await _prepareStep(generation, _AttendanceStep.blink);

      _blinkCandidates = await _burst(generation, blinkBurstCount);

      await _wait(generation, const Duration(milliseconds: 700));

      await _prepareStep(generation, _AttendanceStep.turn);

      _turnedCandidates = await _burst(generation, turnBurstCount);

      await _prepareStep(generation, _AttendanceStep.smile);

      _smileCandidates = await _burst(generation, smileBurstCount);

      await _prepareStep(generation, _AttendanceStep.returnCenter);

      _returnedCandidates = await _burst(generation, returnBurstCount);

      if (!_offlineActive(generation)) {
        return;
      }

      await _saveOffline();
    } catch (e) {
      _fail('Offline camera capture failed. Please try again.');
    }
  }

  // ===========================================================================
  // SUBMIT ONLINE
  // ===========================================================================

  Future<void> _submitOnline() async {
    final eventId = widget.event.id;

    final position = _position;

    if (eventId == null ||
        position == null ||
        _centerFrame == null ||
        _blinkFrame == null ||
        _turnedFrame == null ||
        _smileFrame == null ||
        _returnedFrame == null) {
      _fail('Attendance evidence is incomplete.');

      return;
    }

    setState(() {
      _running = false;
      _step = _AttendanceStep.verifying;
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

    if (result.networkUnavailable) {
      _offlineMode = true;

      _centerCandidates = <XFile>[_centerFrame!];

      _blinkCandidates = <XFile>[_blinkFrame!];

      _turnedCandidates = <XFile>[_turnedFrame!];

      _smileCandidates = <XFile>[_smileFrame!];

      _returnedCandidates = <XFile>[_returnedFrame!];

      await _saveOffline();

      return;
    }

    if (!result.success) {
      _fail(result.message);
      return;
    }

    await _onlineSuccess(result);
  }

  // ===========================================================================
  // SAVE OFFLINE
  // ===========================================================================

  Future<void> _saveOffline() async {
    final eventId = widget.event.id;

    final position = _position;

    if (eventId == null || position == null) {
      _fail('Event or GPS data is missing.');

      return;
    }

    if (_centerCandidates.isEmpty ||
        _blinkCandidates.isEmpty ||
        _turnedCandidates.isEmpty ||
        _smileCandidates.isEmpty ||
        _returnedCandidates.isEmpty) {
      _fail('Offline biometric burst is incomplete.');

      return;
    }

    setState(() {
      _step = _AttendanceStep.verifying;
    });

    final result = await AttendanceService.instance.queueOfflineAttendance(
      eventId: eventId,
      latitude: position.latitude,
      longitude: position.longitude,
      locationAccuracy: position.accuracy,
      attendanceTime: DateTime.now(),
      centerCandidates: _centerCandidates,
      blinkCandidates: _blinkCandidates,
      turnedCandidates: _turnedCandidates,
      smileCandidates: _smileCandidates,
      returnedCandidates: _returnedCandidates,
    );

    if (!mounted || _disposed) {
      return;
    }

    if (!result.success) {
      _fail(result.message);
      return;
    }

    await _offlineSuccess();
  }

  void _fail(String message) {
    if (!mounted || _disposed) {
      return;
    }

    _offlineGeneration++;

    setState(() {
      _running = false;
      _offlineCaptureBusy = false;
      _step = _AttendanceStep.failed;
      _error = message;
    });
  }

  Future<void> _retry() async {
    _offlineGeneration++;

    setState(() {
      _offlineMode = false;
      _initializing = false;
      _error = null;
      _step = _AttendanceStep.preparing;
    });

    await _startOnline();
  }

  // ===========================================================================
  // DIALOGS
  // ===========================================================================

  Future<void> _onlineSuccess(AttendanceResult result) async {
    final attendance = result.data?['attendance'];

    var status = 'Recorded';

    if (attendance is Map && attendance['status'] != null) {
      final value = attendance['status'].toString();

      if (value.isNotEmpty) {
        status =
            '${value[0].toUpperCase()}'
            '${value.substring(1).toLowerCase()}';
      }
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Attendance Recorded'),
          content: Text('${widget.event.name}\n\n$status'),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Done'),
            ),
          ],
        );
      },
    );

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _offlineSuccess() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Saved Offline'),
          content: const Text(
            'Multiple biometric candidates were saved for every challenge step.\n\n'
            'Pending Verification & Sync\n\n'
            'When connection returns, the server will analyze the candidate frames, choose the valid liveness evidence, verify your face and geofence, and only then record attendance.',
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Done'),
            ),
          ],
        );
      },
    );

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  // ===========================================================================
  // TEXT
  // ===========================================================================

  String get _instruction {
    if (_offlineMode) {
      switch (_step) {
        case _AttendanceStep.center:
          return _offlineCaptureBusy
              ? 'Capturing centered frames...'
              : 'Look straight and hold still';

        case _AttendanceStep.blink:
          return _offlineCaptureBusy
              ? 'Capturing blink frames...'
              : 'Close both eyes fully and HOLD';

        case _AttendanceStep.turn:
          return _offlineCaptureBusy
              ? 'Capturing head-turn frames...'
              : 'Turn left or right and HOLD';

        case _AttendanceStep.smile:
          return _offlineCaptureBusy
              ? 'Capturing smile frames...'
              : 'Smile clearly and HOLD';

        case _AttendanceStep.returnCenter:
          return _offlineCaptureBusy
              ? 'Capturing final center frames...'
              : 'Look straight again and HOLD';

        case _AttendanceStep.verifying:
          return 'Saving offline evidence...';

        case _AttendanceStep.failed:
          return 'Offline attendance stopped';

        case _AttendanceStep.preparing:
          return 'Preparing offline attendance...';
      }
    }

    switch (_step) {
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
        return 'Return your face to center';

      case _AttendanceStep.verifying:
        return 'Verifying attendance...';

      case _AttendanceStep.failed:
        return 'Verification stopped';

      case _AttendanceStep.preparing:
        return 'Preparing camera...';
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
      default:
        return 0;
    }
  }

  // ===========================================================================
  // UI
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final camera = _camera;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        title: const Text('Record Attendance'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.event.name,
                      style: const TextStyle(
                        color: navy,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (widget.event.venue.isNotEmpty) Text(widget.event.venue),
                  ],
                ),
              ),

              if (_offlineMode) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3CD),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: gold),
                  ),
                  child: const Text(
                    'Offline Mode\nMultiple frames are captured automatically for every challenge step.',
                    style: TextStyle(color: navy, fontWeight: FontWeight.w600),
                  ),
                ),
              ],

              const SizedBox(height: 24),

              Container(
                width: 290,
                height: 290,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.black,
                  shape: BoxShape.circle,
                  border: Border.all(color: gold, width: 5),
                ),
                child:
                    _initializing ||
                        camera == null ||
                        !camera.value.isInitialized
                    ? const Center(child: CircularProgressIndicator())
                    : Transform.scale(scaleX: -1, child: CameraPreview(camera)),
              ),

              const SizedBox(height: 24),

              if (_stepNumber > 0) Text('Step $_stepNumber of 5'),

              const SizedBox(height: 8),

              Text(
                _instruction,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: navy,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              if (_position != null)
                Text('GPS accuracy ±${_position!.accuracy.round()} m'),

              if (_offlineCaptureBusy ||
                  _step == _AttendanceStep.verifying) ...[
                const SizedBox(height: 20),
                const CircularProgressIndicator(),
              ],

              if (_error != null) ...[
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ],

              if (_step == _AttendanceStep.failed) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _retry,
                    child: const Text('Try Again'),
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
    _offlineMode = false;

    _offlineGeneration++;

    _camera?.dispose();

    super.dispose();
  }
}
