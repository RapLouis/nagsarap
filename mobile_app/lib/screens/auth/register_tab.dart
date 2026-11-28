import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';

import '../../core/app_colors.dart';
import '../../services/registration_service.dart';
import '../../widgets/app_dialog.dart';
import 'registration_face_verification_screen.dart';

class RegisterTab extends StatefulWidget {
  const RegisterTab({super.key});

  @override
  State<RegisterTab> createState() => _RegisterTabState();
}

class _RegisterTabState extends State<RegisterTab> {
  // --------------------------------------------------------------------------
  // CONTROLLERS
  // --------------------------------------------------------------------------

  final studentNumberController = TextEditingController();
  final surnameController = TextEditingController();
  final firstNameController = TextEditingController();
  final middleNameController = TextEditingController();
  final extensionController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  // --------------------------------------------------------------------------
  // FILES
  // --------------------------------------------------------------------------

  XFile? profilePhoto;
  XFile? form5;

  // --------------------------------------------------------------------------
  // STATE
  // --------------------------------------------------------------------------

  bool hidePassword = true;
  bool hideConfirmPassword = true;

  bool validatingPhoto = false;
  bool facePhotoValid = false;
  bool registering = false;

  String? photoValidationMessage;

  // --------------------------------------------------------------------------
  // DISPOSE
  // --------------------------------------------------------------------------

  @override
  void dispose() {
    studentNumberController.dispose();
    surnameController.dispose();
    firstNameController.dispose();
    middleNameController.dispose();
    extensionController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();

    super.dispose();
  }

  // --------------------------------------------------------------------------
  // INSTRUCTION -> CAMERA PERMISSION -> CAMERA CAPTURE
  // --------------------------------------------------------------------------

  Future<void> pickProfilePhoto() async {
    if (validatingPhoto || registering) {
      return;
    }

    // 1. Show Instructions Modal first
    final bool? proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEFF6FF),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.camera_front_rounded,
                    color: AppColors.navy,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Profile Photo Instructions',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'To register your account, you must take a live reference photo of your face using your camera.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.black87,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Column(
                    children: [
                      _InstructionRow(
                        icon: Icons.light_mode_outlined,
                        text: 'Ensure your face is brightly and evenly lit.',
                      ),
                      SizedBox(height: 8),
                      _InstructionRow(
                        icon: Icons.face_retouching_natural_outlined,
                        text: 'Remove hats, heavy glasses, or face coverings.',
                      ),
                      SizedBox(height: 8),
                      _InstructionRow(
                        icon: Icons.center_focus_strong_outlined,
                        text: 'Keep your face centered inside the circle.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.navy,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Allow Camera & Continue',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (proceed != true || !mounted) return;

    // 2. Request Camera Permission
    final cameraStatus = await Permission.camera.request();
    if (!mounted) return;

    if (!cameraStatus.isGranted) {
      await showSimpleError(
        title: 'Camera Permission Required',
        message:
            'Camera access is required to take your live profile photo. Please enable camera permission in your settings.',
      );
      return;
    }

    // 3. Open Camera Screen
    try {
      final XFile? image = await Navigator.of(context).push<XFile>(
        MaterialPageRoute(
          builder: (_) => const ProfileCameraScreen(),
        ),
      );

      if (image == null || !mounted) {
        return;
      }

      setState(() {
        profilePhoto = image;
        validatingPhoto = true;
        facePhotoValid = false;
        photoValidationMessage = 'Scanning reference photo...';
      });

      final result = await RegistrationService.instance.validateReferencePhoto(
        profilePhoto: image,
      );

      if (!mounted) return;

      if (result.success) {
        setState(() {
          facePhotoValid = true;
          photoValidationMessage = result.message;
        });
        return;
      }

      setState(() {
        facePhotoValid = false;
        photoValidationMessage = result.message;
      });

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AppDialog(
            type: AppDialogType.error,
            title: 'Photo Not Accepted',
            message: result.message,
            primaryText: 'Retake Photo',
            primaryAction: () => Navigator.of(dialogContext).pop(),
          );
        },
      );
    } catch (e) {
      debugPrint('Reference photo error: $e');

      if (!mounted) return;

      setState(() {
        facePhotoValid = false;
        photoValidationMessage = 'Unable to process captured photo.';
      });

      await showSimpleError(
        title: 'Photo Error',
        message:
            'Unable to process the captured photo. Please try retaking the image.',
      );
    } finally {
      if (mounted) {
        setState(() {
          validatingPhoto = false;
        });
      }
    }
  }

  void removeProfilePhoto() {
    if (registering || validatingPhoto) return;

    setState(() {
      profilePhoto = null;
      facePhotoValid = false;
      photoValidationMessage = null;
    });
  }

  // --------------------------------------------------------------------------
  // FORM 5 SELECTION
  // --------------------------------------------------------------------------

  Future<void> pickForm5() async {
    if (registering) return;

    try {
      const fs.XTypeGroup pdfType = fs.XTypeGroup(
        label: 'PDF documents',
        extensions: <String>['pdf'],
        uniformTypeIdentifiers: <String>['com.adobe.pdf'],
        mimeTypes: <String>['application/pdf'],
      );

      final XFile? selectedFile = await fs.openFile(
        acceptedTypeGroups: <fs.XTypeGroup>[pdfType],
      );

      if (selectedFile == null) return;

      final int fileSize = await selectedFile.length();
      if (fileSize > 10 * 1024 * 1024) {
        await showSimpleError(
          title: 'File Too Large',
          message: 'Your Form 5 must not exceed 10 MB.',
        );
        return;
      }

      if (!selectedFile.name.toLowerCase().endsWith('.pdf')) {
        await showSimpleError(
          title: 'Invalid Form 5',
          message: 'Please select a PDF copy of your Form 5.',
        );
        return;
      }

      if (!mounted) return;

      setState(() {
        form5 = selectedFile;
      });
    } catch (e) {
      debugPrint('Form 5 error: $e');
      await showSimpleError(
        title: 'Unable to Select File',
        message: 'The Form 5 could not be loaded.',
      );
    }
  }

  void removeForm5() {
    if (registering) return;
    setState(() {
      form5 = null;
    });
  }

  // --------------------------------------------------------------------------
  // FORMATTER & VALIDATIONS
  // --------------------------------------------------------------------------

  void formatStudentNumber(String value) {
    var sanitized = value.replaceAll(RegExp(r'[^0-9-]'), '');

    if (sanitized.length > 9) {
      sanitized = sanitized.substring(0, 9);
    }

    if (studentNumberController.text != sanitized) {
      final offset = studentNumberController.selection.baseOffset;
      final clampedOffset =
          offset < 0 ? sanitized.length : offset.clamp(0, sanitized.length);

      studentNumberController.value = TextEditingValue(
        text: sanitized,
        selection: TextSelection.collapsed(offset: clampedOffset),
      );
    }
    setState(() {});
  }

  bool get hasMinimumLength => passwordController.text.length >= 12;
  bool get hasNumber => RegExp(r'[0-9]').hasMatch(passwordController.text);
  bool get hasSpecialCharacter =>
      RegExp(r'''[!@#$%^&*(),.?":{}|<>_\-+=/\\[\]]''')
          .hasMatch(passwordController.text);
  bool get passwordsMatch =>
      passwordController.text.isNotEmpty &&
      passwordController.text == confirmPasswordController.text;
  bool get validEmail =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(emailController.text.trim());
  bool get validStudentNumber =>
      RegExp(r'^\d{2}-\d{6}$').hasMatch(studentNumberController.text.trim());

  bool get canRegister =>
      validStudentNumber &&
      firstNameController.text.trim().isNotEmpty &&
      surnameController.text.trim().isNotEmpty &&
      validEmail &&
      hasMinimumLength &&
      hasNumber &&
      hasSpecialCharacter &&
      passwordsMatch &&
      profilePhoto != null &&
      facePhotoValid &&
      form5 != null &&
      !validatingPhoto &&
      !registering;

  // --------------------------------------------------------------------------
  // SUBMIT REGISTRATION
  // --------------------------------------------------------------------------

  Future<void> submitRegistration() async {
    if (!canRegister || registering) return;

    final selectedPhoto = profilePhoto;
    final selectedForm5 = form5;
    if (selectedPhoto == null || selectedForm5 == null) return;

    FocusScope.of(context).unfocus();

    setState(() {
      registering = true;
    });

    try {
      final result = await RegistrationService.instance.register(
        studentNumber: studentNumberController.text,
        surname: surnameController.text,
        firstname: firstNameController.text,
        middlename: middleNameController.text,
        ext: extensionController.text,
        email: emailController.text,
        password: passwordController.text,
        passwordConfirmation: confirmPasswordController.text,
        profilePhoto: selectedPhoto,
        form5: selectedForm5,
      );

      if (!mounted) return;

      if (!result.success) {
        await showSimpleError(
          title: 'Registration Failed',
          message: result.message,
        );
        return;
      }

      final studentName =
          '${firstNameController.text.trim()} ${surnameController.text.trim()}';

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RegistrationFaceVerificationScreen(
            studentName: studentName,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Registration exception: $e');
      if (!mounted) return;
      await showSimpleError(
        title: 'Registration Error',
        message:
            'An error occurred during submission. Please check your network connection.',
      );
    } finally {
      if (mounted) {
        setState(() {
          registering = false;
        });
      }
    }
  }

  Future<void> showSimpleError({
    required String title,
    required String message,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AppDialog(
          type: AppDialogType.error,
          title: title,
          message: message,
          primaryText: 'Okay',
          primaryAction: () => Navigator.of(dialogContext).pop(),
        );
      },
    );
  }

  // --------------------------------------------------------------------------
  // UI BUILDERS
  // --------------------------------------------------------------------------

  Widget _buildRoundedInputField({
    required String label,
    required String hint,
    required TextEditingController controller,
    bool isRequired = false,
    TextInputType keyboardType = TextInputType.text,
    TextInputAction textInputAction = TextInputAction.next,
    bool obscureText = false,
    Widget? prefixIcon,
    Widget? suffixIcon,
    String? helperText,
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            text: label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
            ),
            children: isRequired
                ? [
                    const TextSpan(
                      text: ' *',
                      style: TextStyle(
                        color: AppColors.gold,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ]
                : [],
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            obscureText: obscureText,
            onChanged: onChanged,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                fontSize: 13,
                color: Color(0xFF94A3B8),
              ),
              prefixIcon: prefixIcon,
              suffixIcon: suffixIcon,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 14,
              ),
              filled: true,
              fillColor: Colors.white,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: const BorderSide(
                  color: Color(0xFFCBD5E1),
                  width: 1.2,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: const BorderSide(
                  color: AppColors.gold,
                  width: 1.8,
                ),
              ),
            ),
          ),
        ),
        if (helperText != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              helperText,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRoundedInputField(
            label: 'Student Number',
            isRequired: true,
            hint: 'e.g. 23-123456',
            controller: studentNumberController,
            keyboardType: TextInputType.datetime,
            helperText: 'Format: YY-NNNNNN (e.g. 23-123456)',
            prefixIcon: const Icon(
              Icons.tag_rounded,
              size: 18,
              color: AppColors.textMuted,
            ),
            onChanged: formatStudentNumber,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildRoundedInputField(
                  label: 'Surname',
                  isRequired: true,
                  hint: 'Surname',
                  controller: surnameController,
                  prefixIcon: const Icon(
                    Icons.person_outline_rounded,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildRoundedInputField(
                  label: 'First Name',
                  isRequired: true,
                  hint: 'First name',
                  controller: firstNameController,
                  prefixIcon: const Icon(
                    Icons.person_outline_rounded,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildRoundedInputField(
                  label: 'Middle Name',
                  hint: 'Middle name',
                  controller: middleNameController,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildRoundedInputField(
                  label: 'Extension',
                  hint: 'Jr., Sr.',
                  controller: extensionController,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildRoundedInputField(
            label: 'Email Address',
            isRequired: true,
            hint: 'Enter your email address',
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            prefixIcon: const Icon(
              Icons.mail_outline_rounded,
              size: 18,
              color: AppColors.textMuted,
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (emailController.text.isNotEmpty && !validEmail) ...[
            const SizedBox(height: 4),
            const Padding(
              padding: EdgeInsets.only(left: 12),
              child: Text(
                'Enter a valid email address',
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.error,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          _buildRoundedInputField(
            label: 'Password',
            isRequired: true,
            hint: 'Create a password',
            controller: passwordController,
            obscureText: hidePassword,
            prefixIcon: const Icon(
              Icons.lock_outline_rounded,
              size: 18,
              color: AppColors.textMuted,
            ),
            onChanged: (_) => setState(() {}),
            suffixIcon: IconButton(
              onPressed: () => setState(() => hidePassword = !hidePassword),
              icon: Icon(
                hidePassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 18,
                color: AppColors.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Column(
              children: [
                _PasswordRequirement(
                    passed: hasMinimumLength, text: 'At least 12 characters'),
                _PasswordRequirement(
                    passed: hasNumber, text: 'At least one number'),
                _PasswordRequirement(
                    passed: hasSpecialCharacter,
                    text: 'At least one special character'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildRoundedInputField(
            label: 'Confirm Password',
            isRequired: true,
            hint: 'Confirm your password',
            controller: confirmPasswordController,
            obscureText: hideConfirmPassword,
            textInputAction: TextInputAction.done,
            prefixIcon: const Icon(
              Icons.lock_outline_rounded,
              size: 18,
              color: AppColors.textMuted,
            ),
            onChanged: (_) => setState(() {}),
            suffixIcon: IconButton(
              onPressed: () =>
                  setState(() => hideConfirmPassword = !hideConfirmPassword),
              icon: Icon(
                hideConfirmPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 18,
                color: AppColors.textMuted,
              ),
            ),
          ),
          if (confirmPasswordController.text.isNotEmpty) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Row(
                children: [
                  Icon(
                    passwordsMatch
                        ? Icons.check_circle_rounded
                        : Icons.cancel_rounded,
                    size: 14,
                    color: passwordsMatch ? AppColors.success : AppColors.error,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    passwordsMatch
                        ? 'Passwords match'
                        : 'Passwords do not match',
                    style: TextStyle(
                      fontSize: 11,
                      color:
                          passwordsMatch ? AppColors.success : AppColors.error,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          RichText(
            text: const TextSpan(
              text: 'Profile Picture',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.navy,
              ),
              children: [
                TextSpan(
                  text: ' *',
                  style: TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: validatingPhoto || registering ? null : pickProfilePhoto,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: facePhotoValid
                      ? AppColors.success
                      : const Color(0xFFE2E8F0),
                  width: 1.5,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x06000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: facePhotoValid
                          ? const Color(0xFFDCFCE7)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: validatingPhoto
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppColors.navy,
                            ),
                          )
                        : Icon(
                            facePhotoValid
                                ? Icons.check_circle_rounded
                                : Icons.camera_alt_rounded,
                            size: 24,
                            color: facePhotoValid
                                ? AppColors.success
                                : AppColors.navy,
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profilePhoto?.name ?? 'Take Profile Photo',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.navy,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          validatingPhoto
                              ? 'Scanning reference photo...'
                              : photoValidationMessage ??
                                  'Take a clear, well-lit live headshot',
                          style: TextStyle(
                            fontSize: 11,
                            color: facePhotoValid
                                ? AppColors.success
                                : AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (profilePhoto != null && !validatingPhoto)
                    IconButton(
                      onPressed: removeProfilePhoto,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.grey,
                        size: 18,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          RichText(
            text: const TextSpan(
              text: 'Form 5 Document',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.navy,
              ),
              children: [
                TextSpan(
                  text: ' *',
                  style: TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: registering ? null : pickForm5,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: form5 != null
                      ? AppColors.success
                      : const Color(0xFFE2E8F0),
                  width: 1.5,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x06000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: form5 != null
                          ? const Color(0xFFDCFCE7)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      form5 != null
                          ? Icons.description_rounded
                          : Icons.picture_as_pdf_outlined,
                      size: 24,
                      color:
                          form5 != null ? AppColors.success : AppColors.navy,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          form5?.name ?? 'Upload Form 5 PDF',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.navy,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'PDF document only (Maximum 10MB)',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (form5 != null)
                    IconButton(
                      onPressed: removeForm5,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.grey,
                        size: 18,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: canRegister ? submitRegistration : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.navy,
                disabledBackgroundColor: const Color(0xFFCBD5E1),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              child: registering
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Register & Verify Form 5',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 14),
          const Center(
            child: Text(
              'Your account will require live facial verification before activation.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InstructionRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InstructionRow({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.navy),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black87,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _PasswordRequirement extends StatelessWidget {
  final bool passed;
  final String text;

  const _PasswordRequirement({
    required this.passed,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            passed ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 13,
            color: passed ? AppColors.success : AppColors.textMuted,
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: passed ? AppColors.success : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// CLEAN CAMERA CAPTURE WITH LIGHTING & ALIGNMENT STABILITY GATE
// ============================================================================

class ProfileCameraScreen extends StatefulWidget {
  const ProfileCameraScreen({super.key});

  @override
  State<ProfileCameraScreen> createState() => _ProfileCameraScreenState();
}

class _ProfileCameraScreenState extends State<ProfileCameraScreen> {
  static const int _requiredStableFrames = 6;
  static const double _minBrightness = 28.0;
  static const double _maxBrightness = 245.0;
  static const double _maxYawDegrees = 14.0;
  static const double _maxRollDegrees = 14.0;

  CameraController? _cameraController;
  CameraDescription? _frontCamera;
  late final FaceDetector _faceDetector;

  bool _isInitialized = false;
  bool _isCapturing = false;
  bool _isProcessingFrame = false;

  int _stableFrames = 0;
  String _statusHint = 'Center your face inside the circle';
  String? _errorMessage;
  XFile? _capturedImage;

  @override
  void initState() {
    super.initState();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableTracking: false,
        enableContours: false,
        enableLandmarks: false,
        enableClassification: false,
        minFaceSize: 0.20,
      ),
    );
    _initFrontCamera();
  }

  Future<void> _initFrontCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _errorMessage = 'No camera found on this device.';
          });
        }
        return;
      }

      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _frontCamera = front;

      final CameraController controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await controller.initialize();

      try {
        await controller.setExposureMode(ExposureMode.auto);
      } catch (_) {}
      try {
        await controller.setFocusMode(FocusMode.auto);
      } catch (_) {}

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _isInitialized = true;
      });

      await _startQualityStream();
    } catch (e) {
      debugPrint('Camera initialization error: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Unable to access camera.';
        });
      }
    }
  }

  Future<void> _startQualityStream() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isStreamingImages) return;

    try {
      await controller.startImageStream(_onCameraImage);
    } catch (e) {
      debugPrint('Image stream start warning: $e');
    }
  }

  Future<void> _stopQualityStream() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    if (!controller.value.isStreamingImages) return;

    try {
      await controller.stopImageStream();
    } catch (_) {}
  }

  Future<void> _onCameraImage(CameraImage image) async {
    if (!mounted ||
        _isProcessingFrame ||
        _isCapturing ||
        _capturedImage != null) {
      return;
    }

    _isProcessingFrame = true;

    try {
      // 1. Detect face first so brightness is measured on the face region
      final inputImage = _toInputImage(image);
      if (inputImage == null) return;

      final faces = await _faceDetector.processImage(inputImage);
      if (!mounted || _capturedImage != null) return;

      if (faces.isEmpty) {
        final double centerBrightness = _measureRegionBrightness(image, null);
        if (centerBrightness < _minBrightness) {
          _updateGateState(
            stable: false,
            hint: 'Lighting is too dark. Move to a brighter area.',
          );
        } else {
          _updateGateState(
            stable: false,
            hint: 'Position your face inside the circle.',
          );
        }
        return;
      }

      if (faces.length > 1) {
        _updateGateState(
          stable: false,
          hint: 'Multiple faces detected. Ensure only you are in frame.',
        );
        return;
      }

      final face = faces.first;
      final bbox = face.boundingBox;

      // 2. Measure brightness specifically on the detected face region
      final double faceBrightness = _measureRegionBrightness(image, bbox);
      if (faceBrightness < _minBrightness) {
        _updateGateState(
          stable: false,
          hint: 'Lighting is too dark. Face a light source or brighten screen.',
        );
        return;
      }
      if (faceBrightness > _maxBrightness) {
        _updateGateState(
          stable: false,
          hint: 'Lighting is too bright or backlit.',
        );
        return;
      }

      // 3. Check position and frontal alignment
      final int rotation = _frontCamera?.sensorOrientation ?? 0;
      final bool isRotated = rotation == 90 || rotation == 270;
      final double frameW =
          (isRotated ? image.height : image.width).toDouble();
      final double frameH =
          (isRotated ? image.width : image.height).toDouble();

      final double faceWidthRatio = bbox.width / frameW;
      final double centerXRatio = bbox.center.dx / frameW;
      final double centerYRatio = bbox.center.dy / frameH;

      if (faceWidthRatio < 0.24) {
        _updateGateState(
          stable: false,
          hint: 'Move slightly closer to the camera.',
        );
        return;
      }

      if (faceWidthRatio > 0.80) {
        _updateGateState(
          stable: false,
          hint: 'Move slightly farther from the camera.',
        );
        return;
      }

      if ((centerXRatio - 0.5).abs() > 0.18 ||
          (centerYRatio - 0.5).abs() > 0.20) {
        _updateGateState(
          stable: false,
          hint: 'Center your face inside the circle.',
        );
        return;
      }

      final double yaw = (face.headEulerAngleY ?? 0).abs();
      final double roll = (face.headEulerAngleZ ?? 0).abs();

      if (yaw > _maxYawDegrees || roll > _maxRollDegrees) {
        _updateGateState(
          stable: false,
          hint: 'Look directly straight at the camera.',
        );
        return;
      }

      _updateGateState(
        stable: true,
        hint: _stableFrames + 1 >= _requiredStableFrames
            ? 'Ready — tap Capture Photo'
            : 'Hold steady...',
      );
    } catch (e) {
      debugPrint('Frame quality check error: $e');
    } finally {
      _isProcessingFrame = false;
    }
  }

  void _updateGateState({required bool stable, required String hint}) {
    if (!mounted) return;
    final int nextStable = stable
        ? (_stableFrames + 1).clamp(0, _requiredStableFrames)
        : 0;

    if (nextStable != _stableFrames || hint != _statusHint) {
      setState(() {
        _stableFrames = nextStable;
        _statusHint = hint;
      });
    }
  }

  double _measureRegionBrightness(CameraImage image, Rect? rotatedFaceBox) {
    if (image.planes.isEmpty) return 128.0;
    final Uint8List bytes = image.planes.first.bytes;
    if (bytes.isEmpty) return 128.0;

    final int w = image.width;
    final int h = image.height;
    final int bytesPerRow = image.planes.first.bytesPerRow;

    // Sample the center 50% of the raw sensor frame so dark backgrounds don't bias luma
    final int startX = (w * 0.25).round();
    final int endX = (w * 0.75).round();
    final int startY = (h * 0.25).round();
    final int endY = (h * 0.75).round();

    int sum = 0;
    int count = 0;

    if (image.format.group == ImageFormatGroup.bgra8888) {
      for (int y = startY; y < endY; y += 4) {
        final int rowOffset = y * bytesPerRow;
        for (int x = startX; x < endX; x += 4) {
          final int idx = rowOffset + x * 4;
          if (idx + 2 < bytes.length) {
            sum += (bytes[idx] + bytes[idx + 1] + bytes[idx + 2]) ~/ 3;
            count++;
          }
        }
      }
    } else {
      for (int y = startY; y < endY; y += 4) {
        final int rowOffset = y * bytesPerRow;
        for (int x = startX; x < endX; x += 4) {
          final int idx = rowOffset + x;
          if (idx < bytes.length) {
            sum += bytes[idx];
            count++;
          }
        }
      }
    }

    return count == 0 ? 128.0 : sum / count;
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
    final bytes = allBytes.done().buffer.asUint8List();

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  Future<void> _capturePhoto() async {
    final controller = _cameraController;
    if (_isCapturing ||
        controller == null ||
        !controller.value.isInitialized ||
        _stableFrames < _requiredStableFrames) {
      return;
    }

    setState(() {
      _isCapturing = true;
    });

    try {
      await _stopQualityStream();

      final XFile rawFile = await controller.takePicture();
      final XFile normalizedFile = await _normalizeFrontCapture(rawFile);

      if (mounted) {
        setState(() {
          _capturedImage = normalizedFile;
        });
      }
    } catch (e) {
      debugPrint('Photo capture error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to capture photo. Please try again.'),
          ),
        );
        await _startQualityStream();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  Future<XFile> _normalizeFrontCapture(XFile rawFile) async {
    try {
      final bytes = await rawFile.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return rawFile;

      final baked = img.bakeOrientation(decoded);
      final unmirrored = img.flipHorizontal(baked);

      // Gently lift shadow exposure if the captured photo is slightly dim
      double lumaSum = 0;
      int samples = 0;
      for (int y = unmirrored.height ~/ 4; y < (unmirrored.height * 3) ~/ 4; y += 8) {
        for (int x = unmirrored.width ~/ 4; x < (unmirrored.width * 3) ~/ 4; x += 8) {
          final pixel = unmirrored.getPixel(x, y);
          lumaSum += (pixel.r + pixel.g + pixel.b) / 3.0;
          samples++;
        }
      }
      final double avgLuma = samples > 0 ? lumaSum / samples : 128.0;

      img.Image finalImage = unmirrored;
      if (avgLuma < 85.0) {
        final double gain = (85.0 / avgLuma.clamp(25.0, 85.0)).clamp(1.0, 1.8);
        finalImage = img.adjustColor(
          unmirrored,
          brightness: gain,
          gamma: 0.90,
        );
      }

      final encoded = img.encodeJpg(finalImage, quality: 95);

      await File(rawFile.path).writeAsBytes(encoded, flush: true);
      return rawFile;
    } catch (_) {
      return rawFile;
    }
  }

  Future<void> _retakePhoto() async {
    setState(() {
      _capturedImage = null;
      _stableFrames = 0;
      _statusHint = 'Center your face inside the circle';
    });
    await _startQualityStream();
  }

  void _confirmPhoto() {
    if (_capturedImage != null) {
      Navigator.of(context).pop(_capturedImage);
    }
  }

  @override
  void dispose() {
    _stopQualityStream();
    _cameraController?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isReady = _stableFrames >= _requiredStableFrames;
    final double progress =
        (_stableFrames / _requiredStableFrames).clamp(0.0, 1.0);
    final int progressPct = (progress * 100).round();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE2E8F0)),
        ),
        title: Text(
          _capturedImage == null ? 'Take Profile Photo' : 'Review Photo',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            children: [
              const Text(
                'Position your face inside the circle in good lighting. Capture unlocks when alignment stabilizes.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: Color(0xFF475569),
                ),
              ),

              const Spacer(),

              // Circular Viewfinder (Native Sensor Aspect Ratio, Zero Distortion)
              Container(
                width: 280,
                height: 280,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(
                    color: _capturedImage != null || isReady
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFCBD5E1),
                    width: 3,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x120F172A),
                      blurRadius: 18,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Container(
                    color: const Color(0xFF0F172A),
                    child: _capturedImage != null
                        ? Image.file(
                            File(_capturedImage!.path),
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                          )
                        : (_isInitialized && _cameraController != null
                            ? _buildUndistortedPreview(_cameraController!)
                            : Center(
                                child: _errorMessage != null
                                    ? Padding(
                                        padding: const EdgeInsets.all(20),
                                        child: Text(
                                          _errorMessage!,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      )
                                    : const CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.5,
                                      ),
                              )),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Alignment & Lighting Loading Fill Bar
              if (_capturedImage == null) ...[
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Alignment & Lighting',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF334155),
                            ),
                          ),
                          Text(
                            '$progressPct%',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isReady
                                  ? const Color(0xFF16A34A)
                                  : const Color(0xFF475569),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 7,
                          backgroundColor: const Color(0xFFE2E8F0),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isReady
                                ? const Color(0xFF16A34A)
                                : const Color(0xFF2563EB),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isReady
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isReady
                          ? const Color(0xFF86EFAC)
                          : const Color(0xFFFDE68A),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isReady
                            ? Icons.check_circle_rounded
                            : Icons.info_outline_rounded,
                        size: 16,
                        color: isReady
                            ? const Color(0xFF15803D)
                            : const Color(0xFFB45309),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _statusHint,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isReady
                                ? const Color(0xFF15803D)
                                : const Color(0xFF92400E),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const Spacer(),

              // Bottom Action Buttons
              if (_capturedImage == null)
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF334155),
                            backgroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 46,
                        child: ElevatedButton.icon(
                          onPressed: (_isInitialized &&
                                  !_isCapturing &&
                                  isReady)
                              ? _capturePhoto
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F172A),
                            disabledBackgroundColor: const Color(0xFFCBD5E1),
                            disabledForegroundColor: const Color(0xFF64748B),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: _isCapturing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.camera_alt_rounded, size: 18),
                          label: Text(
                            _isCapturing ? 'Capturing...' : 'Capture Photo',
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: OutlinedButton.icon(
                          onPressed: _retakePhoto,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF334155),
                            backgroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text(
                            'Retake',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 46,
                        child: ElevatedButton.icon(
                          onPressed: _confirmPhoto,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF16A34A),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: const Text(
                            'Use This Photo',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUndistortedPreview(CameraController controller) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) {
      return CameraPreview(controller);
    }

    final double width = previewSize.height;
    final double height = previewSize.width;

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: width,
          height: height,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}