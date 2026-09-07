import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../services/registration_service.dart';
import '../../widgets/app_dialog.dart';
import 'auth_gate.dart';

enum _LivenessStep {
  center,
  blink,
  turn,
  smile,
  returnCenter,
  ready,
  verifying,
}

class RegistrationFaceVerificationScreen
    extends StatefulWidget {
  const RegistrationFaceVerificationScreen({
    super.key,
  });

  @override
  State<RegistrationFaceVerificationScreen>
      createState() =>
          _RegistrationFaceVerificationScreenState();
}

class _RegistrationFaceVerificationScreenState
    extends State<
        RegistrationFaceVerificationScreen> {
  CameraController? _cameraController;

  bool _initializing = true;
  String? _cameraError;

  _LivenessStep _step =
      _LivenessStep.center;

  XFile? _centerFrame;
  XFile? _blinkFrame;
  XFile? _turnedFrame;
  XFile? _smileFrame;
  XFile? _returnedFrame;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras =
          await availableCameras();

      if (cameras.isEmpty) {
        throw Exception(
          'No camera is available.',
        );
      }

      CameraDescription frontCamera =
          cameras.first;

      for (final camera in cameras) {
        if (camera.lensDirection ==
            CameraLensDirection.front) {
          frontCamera = camera;
          break;
        }
      }

      final controller =
          CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController =
            controller;
        _initializing = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _initializing = false;
        _cameraError =
            'Unable to open the front camera. Please allow camera permission and try again.';
      });
    }
  }

  String get _instruction {
    switch (_step) {
      case _LivenessStep.center:
        return 'Look directly at the camera with a neutral face.';

      case _LivenessStep.blink:
        return 'Close both eyes fully, then capture.';

      case _LivenessStep.turn:
        return 'Turn your head clearly left or right.';

      case _LivenessStep.smile:
        return 'Face the camera and smile clearly.';

      case _LivenessStep.returnCenter:
        return 'Return to the center and look directly at the camera.';

      case _LivenessStep.ready:
        return 'Liveness frames captured. Submit them for server verification.';

      case _LivenessStep.verifying:
        return 'MediaPipe, OpenCV and InsightFace are verifying you...';
    }
  }

  String get _buttonText {
    switch (_step) {
      case _LivenessStep.center:
        return 'Capture Center';

      case _LivenessStep.blink:
        return 'Capture Blink';

      case _LivenessStep.turn:
        return 'Capture Head Turn';

      case _LivenessStep.smile:
        return 'Capture Smile';

      case _LivenessStep.returnCenter:
        return 'Capture Final Center';

      case _LivenessStep.ready:
        return 'Verify My Face';

      case _LivenessStep.verifying:
        return 'Verifying...';
    }
  }

  Future<void> _captureStep() async {
    if (_step == _LivenessStep.ready) {
      await _verify();
      return;
    }

    if (_step ==
        _LivenessStep.verifying) {
      return;
    }

    final controller =
        _cameraController;

    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture) {
      return;
    }

    try {
      final frame =
          await controller.takePicture();

      if (!mounted) {
        return;
      }

      setState(() {
        switch (_step) {
          case _LivenessStep.center:
            _centerFrame = frame;
            _step =
                _LivenessStep.blink;
            break;

          case _LivenessStep.blink:
            _blinkFrame = frame;
            _step =
                _LivenessStep.turn;
            break;

          case _LivenessStep.turn:
            _turnedFrame = frame;
            _step =
                _LivenessStep.smile;
            break;

          case _LivenessStep.smile:
            _smileFrame = frame;
            _step =
                _LivenessStep.returnCenter;
            break;

          case _LivenessStep.returnCenter:
            _returnedFrame = frame;
            _step =
                _LivenessStep.ready;
            break;

          case _LivenessStep.ready:
          case _LivenessStep.verifying:
            break;
        }
      });
    } catch (_) {
      await _showError(
        'Camera Error',
        'Unable to capture the camera frame. Please try again.',
      );
    }
  }

  void _reset() {
    if (_step ==
        _LivenessStep.verifying) {
      return;
    }

    setState(() {
      _centerFrame = null;
      _blinkFrame = null;
      _turnedFrame = null;
      _smileFrame = null;
      _returnedFrame = null;
      _step =
          _LivenessStep.center;
    });
  }

  Future<void> _verify() async {
    if (_centerFrame == null ||
        _blinkFrame == null ||
        _turnedFrame == null ||
        _smileFrame == null ||
        _returnedFrame == null) {
      return;
    }

    setState(() {
      _step =
          _LivenessStep.verifying;
    });

    final result =
        await RegistrationService
            .instance
            .verifyRegistrationFace(
      centerFrame:
          _centerFrame!,
      blinkFrame:
          _blinkFrame!,
      turnedFrame:
          _turnedFrame!,
      smileFrame:
          _smileFrame!,
      returnedFrame:
          _returnedFrame!,
    );

    if (!mounted) {
      return;
    }

    if (!result.success) {
      setState(() {
        _step =
            _LivenessStep.ready;
      });

      await _showError(
        result.code ==
                'LIVENESS_FAILED'
            ? 'Liveness Failed'
            : 'Verification Failed',
        result.message,
      );

      if (mounted) {
        _reset();
      }

      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (
        dialogContext,
      ) {
        return AppDialog(
          type:
              AppDialogType.success,
          title:
              'Identity Verified',
          message:
              'Your biometric registration has been completed successfully.',
          primaryText:
              'Continue',
          primaryAction: () {
            Navigator.of(
              dialogContext,
            ).pop();
          },
        );
      },
    );

    if (!mounted) {
      return;
    }

    Navigator.of(context)
        .pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) =>
            const AuthGate(),
      ),
      (route) => false,
    );
  }

  Future<void> _showError(
    String title,
    String message,
  ) async {
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (
        dialogContext,
      ) {
        return AppDialog(
          type:
              AppDialogType.error,
          title: title,
          message: message,
          primaryText:
              'Try Again',
          primaryAction: () {
            Navigator.of(
              dialogContext,
            ).pop();
          },
        );
      },
    );
  }

  Widget _stepIndicator(
    String title,
    int index,
  ) {
    final currentIndex =
        switch (_step) {
      _LivenessStep.center => 0,
      _LivenessStep.blink => 1,
      _LivenessStep.turn => 2,
      _LivenessStep.smile => 3,
      _LivenessStep.returnCenter => 4,
      _LivenessStep.ready => 5,
      _LivenessStep.verifying => 5,
    };

    final completed =
        index < currentIndex;

    final active =
        index == currentIndex;

    return Expanded(
      child: Column(
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor:
                completed
                    ? AppColors.success
                    : active
                        ? AppColors.gold
                        : Colors.grey.shade200,
            child: completed
                ? const Icon(
                    Icons.check,
                    size: 14,
                    color:
                        Colors.white,
                  )
                : Text(
                    '${index + 1}',
                    style:
                        const TextStyle(
                      fontSize: 10,
                      fontWeight:
                          FontWeight.bold,
                      color:
                          AppColors.navy,
                    ),
                  ),
          ),
          const SizedBox(
            height: 5,
          ),
          Text(
            title,
            textAlign:
                TextAlign.center,
            style: TextStyle(
              fontSize: 9,
              fontWeight:
                  active
                      ? FontWeight.w700
                      : FontWeight.w500,
              color:
                  active
                      ? AppColors.navy
                      : AppColors
                          .textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _cameraController
        ?.dispose();

    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return PopScope(
      canPop:
          _step !=
              _LivenessStep.verifying,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Live Face Verification',
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.all(
              22,
            ),
            child: Column(
              children: [
                const Text(
                  'Complete the liveness challenge',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight:
                        FontWeight.w800,
                    color:
                        AppColors.navy,
                  ),
                ),
                const SizedBox(
                  height: 6,
                ),
                const Text(
                  'The captured frames are verified by the same Laravel, MediaPipe, OpenCV and InsightFace services used by the system.',
                  textAlign:
                      TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color:
                        AppColors
                            .textSecondary,
                  ),
                ),
                const SizedBox(
                  height: 24,
                ),

                Expanded(
                  child: Center(
                    child:
                        _buildCamera(),
                  ),
                ),

                const SizedBox(
                  height: 18,
                ),

                Text(
                  _instruction,
                  textAlign:
                      TextAlign.center,
                  style:
                      const TextStyle(
                    fontSize: 15,
                    fontWeight:
                        FontWeight.w700,
                    color:
                        AppColors.navy,
                  ),
                ),

                const SizedBox(
                  height: 18,
                ),

                Row(
                  children: [
                    _stepIndicator(
                      'Center',
                      0,
                    ),
                    _stepIndicator(
                      'Blink',
                      1,
                    ),
                    _stepIndicator(
                      'Turn',
                      2,
                    ),
                    _stepIndicator(
                      'Smile',
                      3,
                    ),
                    _stepIndicator(
                      'Return',
                      4,
                    ),
                  ],
                ),

                const SizedBox(
                  height: 22,
                ),

                SizedBox(
                  width:
                      double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        _initializing ||
                                _cameraError !=
                                    null ||
                                _step ==
                                    _LivenessStep
                                        .verifying
                            ? null
                            : _captureStep,
                    icon:
                        _step ==
                                _LivenessStep
                                    .verifying
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth:
                                      2,
                                  color:
                                      Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons
                                    .camera_alt_rounded,
                              ),
                    label:
                        Text(
                      _buttonText,
                    ),
                  ),
                ),

                if (_step !=
                        _LivenessStep.center &&
                    _step !=
                        _LivenessStep
                            .verifying) ...[
                  const SizedBox(
                    height: 8,
                  ),
                  TextButton(
                    onPressed:
                        _reset,
                    child:
                        const Text(
                      'Restart Liveness Check',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCamera() {
    if (_initializing) {
      return const CircularProgressIndicator(
        color: AppColors.navy,
      );
    }

    if (_cameraError != null) {
      return Column(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          const Icon(
            Icons
                .camera_alt_outlined,
            size: 50,
            color:
                AppColors.error,
          ),
          const SizedBox(
            height: 12,
          ),
          Text(
            _cameraError!,
            textAlign:
                TextAlign.center,
          ),
        ],
      );
    }

    final controller =
        _cameraController;

    if (controller == null ||
        !controller.value
            .isInitialized) {
      return const Text(
        'Camera unavailable.',
      );
    }

    return Container(
      width: 285,
      height: 360,
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(
          150,
        ),
        border: Border.all(
          color:
              _step ==
                      _LivenessStep.ready
                  ? AppColors.success
                  : AppColors.gold,
          width: 4,
        ),
      ),
      clipBehavior:
          Clip.antiAlias,
      child: Transform.scale(
        scaleX: -1,
        child:
            CameraPreview(
          controller,
        ),
      ),
    );
  }
}