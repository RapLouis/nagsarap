import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

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

  final ImagePicker imagePicker = ImagePicker();

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
  // PICK + FAST VALIDATE PROFILE PHOTO
  // --------------------------------------------------------------------------

  Future<void> pickProfilePhoto() async {
    if (validatingPhoto || registering) {
      return;
    }

    try {
      // Optimized for ultra-fast upload & AI scan speed
      final XFile? image = await imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 1024,
        maxHeight: 1024,
      );

      if (image == null) {
        return;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        profilePhoto = image;
        validatingPhoto = true;
        facePhotoValid = false;
        photoValidationMessage = 'Scanning reference photo...';
      });

      final result =
          await RegistrationService.instance.validateReferencePhoto(
        profilePhoto: image,
      );

      if (!mounted) {
        return;
      }

      if (result.success) {
        setState(() {
          validatingPhoto = false;
          facePhotoValid = true;
          photoValidationMessage = result.message;
        });

        return;
      }

      setState(() {
        validatingPhoto = false;
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
            primaryText: 'Choose Another Photo',
            primaryAction: () {
              Navigator.of(dialogContext).pop();
            },
          );
        },
      );
    } catch (e) {
      debugPrint('Reference photo error: $e');

      if (!mounted) {
        return;
      }

      setState(() {
        validatingPhoto = false;
        facePhotoValid = false;
        photoValidationMessage = 'Unable to process the selected photo.';
      });

      await showSimpleError(
        title: 'Photo Error',
        message:
            'Unable to process the selected photo. Please try another image.',
      );
    }
  }

  // --------------------------------------------------------------------------
  // REMOVE PROFILE PHOTO
  // --------------------------------------------------------------------------

  void removeProfilePhoto() {
    if (registering || validatingPhoto) {
      return;
    }

    setState(() {
      profilePhoto = null;
      facePhotoValid = false;
      photoValidationMessage = null;
    });
  }

  // --------------------------------------------------------------------------
  // FORM 5
  // --------------------------------------------------------------------------

  Future<void> pickForm5() async {
    if (registering) {
      return;
    }

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

      if (selectedFile == null) {
        return;
      }

      final int fileSize = await selectedFile.length();
      const int maxFileSize = 10 * 1024 * 1024;

      if (fileSize > maxFileSize) {
        await showSimpleError(
          title: 'File Too Large',
          message: 'Your Form 5 must not exceed 10 MB.',
        );

        return;
      }

      final lowerName = selectedFile.name.toLowerCase();

      if (!lowerName.endsWith('.pdf')) {
        await showSimpleError(
          title: 'Invalid Form 5',
          message: 'Please select a PDF copy of your Form 5.',
        );

        return;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        form5 = selectedFile;
      });
    } catch (e) {
      debugPrint('Form 5 error: $e');

      await showSimpleError(
        title: 'Unable to Select File',
        message: 'The Form 5 could not be selected.',
      );
    }
  }

  void removeForm5() {
    if (registering) {
      return;
    }

    setState(() {
      form5 = null;
    });
  }

  // --------------------------------------------------------------------------
  // STUDENT NUMBER FORMATTER
  // --------------------------------------------------------------------------

  void formatStudentNumber(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    final limitedDigits =
        digits.length > 8 ? digits.substring(0, 8) : digits;

    String formatted;

    if (limitedDigits.length <= 2) {
      formatted = limitedDigits;
    } else {
      formatted =
          '${limitedDigits.substring(0, 2)}-${limitedDigits.substring(2)}';
    }

    if (studentNumberController.text != formatted) {
      studentNumberController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(
          offset: formatted.length,
        ),
      );
    }

    setState(() {});
  }

  // --------------------------------------------------------------------------
  // VALIDATION CHECKS
  // --------------------------------------------------------------------------

  bool get hasMinimumLength => passwordController.text.length >= 12;

  bool get hasNumber => RegExp(r'[0-9]').hasMatch(passwordController.text);

  bool get hasSpecialCharacter =>
      RegExp(r'''[!@#$%^&*(),.?":{}|<>_\-+=/\\[\]]''')
          .hasMatch(passwordController.text);

  bool get passwordsMatch =>
      passwordController.text.isNotEmpty &&
      passwordController.text == confirmPasswordController.text;

  bool get validEmail => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
      .hasMatch(emailController.text.trim());

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
  // REGISTER
  // --------------------------------------------------------------------------

  Future<void> submitRegistration() async {
    if (!canRegister || registering) {
      return;
    }

    final selectedPhoto = profilePhoto;
    final selectedForm5 = form5;

    if (selectedPhoto == null || selectedForm5 == null) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      registering = true;
    });

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

    if (!mounted) {
      return;
    }

    setState(() {
      registering = false;
    });

    if (!result.success) {
      await showSimpleError(
        title: 'Registration Failed',
        message: result.message,
      );

      return;
    }

    final studentName =
        '${firstNameController.text.trim()} ${surnameController.text.trim()}';

    // Proceed to live face verification with Liveness steps
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RegistrationFaceVerificationScreen(
          studentName: studentName,
        ),
      ),
    );
  }

  Future<void> showSimpleError({
    required String title,
    required String message,
  }) async {
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AppDialog(
          type: AppDialogType.error,
          title: title,
          message: message,
          primaryText: 'Okay',
          primaryAction: () {
            Navigator.of(dialogContext).pop();
          },
        );
      },
    );
  }

  // --------------------------------------------------------------------------
  // CUSTOM ROUNDED INPUT FIELD BUILDER
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
            hint: 'e.g. 23-140040',
            controller: studentNumberController,
            keyboardType: TextInputType.number,
            helperText: 'Format: YY-NNNNNN (e.g. 23-140040)',
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
              onPressed: () {
                setState(() {
                  hidePassword = !hidePassword;
                });
              },
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
                  passed: hasMinimumLength,
                  text: 'At least 12 characters',
                ),
                _PasswordRequirement(
                  passed: hasNumber,
                  text: 'At least one number',
                ),
                _PasswordRequirement(
                  passed: hasSpecialCharacter,
                  text: 'At least one special character',
                ),
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
              onPressed: () {
                setState(() {
                  hideConfirmPassword = !hideConfirmPassword;
                });
              },
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
                    color: passwordsMatch
                        ? AppColors.success
                        : AppColors.error,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    passwordsMatch
                        ? 'Passwords match'
                        : 'Passwords do not match',
                    style: TextStyle(
                      fontSize: 11,
                      color: passwordsMatch
                          ? AppColors.success
                          : AppColors.error,
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
                                : Icons.file_upload_outlined,
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
                          profilePhoto?.name ?? 'Upload Profile Picture',
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
                                  'Clear, well-lit headshot (JPG, JPEG, PNG)',
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
                      color: form5 != null
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
                          'PDF document only (Max 10MB)',
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