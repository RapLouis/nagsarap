import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../core/app_colors.dart';

class RegistrationFaceVerificationScreen extends StatefulWidget {
  const RegistrationFaceVerificationScreen({super.key});

  @override
  State<RegistrationFaceVerificationScreen> createState() =>
      _RegistrationFaceVerificationScreenState();
}

class _RegistrationFaceVerificationScreenState
    extends State<RegistrationFaceVerificationScreen> {
  CameraController? _camera;
  bool _cameraReady = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    final selected = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    _camera = CameraController(
      selected,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await _camera!.initialize();
    if (mounted) {
      setState(() {
        _cameraReady = true;
      });
    }
  }

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        title: const Text('Register Face Biometrics'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 30),
            const Text(
              'Face Registration',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Align your face inside the circle',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const Spacer(),
            
            Center(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black,
                  border: Border.all(color: AppColors.gold, width: 4),
                ),
                child: ClipOval(
                  child: _cameraReady && _camera != null && _camera!.value.isInitialized
                      ? FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: 250,
                            height: 250 * _camera!.value.aspectRatio,
                            child: CameraPreview(_camera!),
                          ),
                        )
                      : const Center(
                          child: CircularProgressIndicator(color: AppColors.gold),
                        ),
                ),
              ),
            ),
            
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Capture & Register',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}