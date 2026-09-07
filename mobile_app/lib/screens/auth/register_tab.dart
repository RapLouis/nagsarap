import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/app_colors.dart';
import '../../services/registration_service.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_text_field.dart';
import 'registration_face_verification_screen.dart';

class RegisterTab extends StatefulWidget {
  const RegisterTab({super.key});

  @override
  State<RegisterTab> createState() => _RegisterTabState();
}

class _RegisterTabState extends State<RegisterTab> {
  /*
  |--------------------------------------------------------------------------
  | CONTROLLERS
  |--------------------------------------------------------------------------
  */

  final studentNumberController = TextEditingController();

  final surnameController = TextEditingController();

  final firstNameController = TextEditingController();

  final middleNameController = TextEditingController();

  final extensionController = TextEditingController();

  final emailController = TextEditingController();

  final passwordController = TextEditingController();

  final confirmPasswordController = TextEditingController();

  /*
  |--------------------------------------------------------------------------
  | FILES
  |--------------------------------------------------------------------------
  */

  final ImagePicker imagePicker = ImagePicker();

  XFile? profilePhoto;
  XFile? form5;

  /*
  |--------------------------------------------------------------------------
  | STATE
  |--------------------------------------------------------------------------
  */

  bool hidePassword = true;

  bool hideConfirmPassword = true;

  bool validatingPhoto = false;

  bool facePhotoValid = false;

  bool registering = false;

  String? photoValidationMessage;

  /*
  |--------------------------------------------------------------------------
  | DISPOSE
  |--------------------------------------------------------------------------
  */

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

  /*
  |--------------------------------------------------------------------------
  | PICK + REAL VALIDATE PROFILE PHOTO
  |--------------------------------------------------------------------------
  */

  Future<void> pickProfilePhoto() async {
    if (validatingPhoto || registering) {
      return;
    }

    try {
      final XFile? image = await imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
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

        photoValidationMessage = 'Checking image quality and detecting face...';
      });

      /*
      |--------------------------------------------------------------------------
      | REAL SERVER VALIDATION
      |--------------------------------------------------------------------------
      |
      | Flutter
      |    ↓
      | Laravel API
      |    ↓
      | FaceService
      |    ↓
      | Python OpenCV + InsightFace
      |
      */

      final result = await RegistrationService.instance.validateReferencePhoto(
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

      /*
      |--------------------------------------------------------------------------
      | INVALID IMAGE
      |--------------------------------------------------------------------------
      */

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

  /*
  |--------------------------------------------------------------------------
  | REMOVE PROFILE PHOTO
  |--------------------------------------------------------------------------
  */

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

  /*
  |--------------------------------------------------------------------------
  | FORM 5
  |--------------------------------------------------------------------------
  */

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

  /*
  |--------------------------------------------------------------------------
  | STUDENT NUMBER
  |--------------------------------------------------------------------------
  */

  void formatStudentNumber(String value) {
    String numbers = value.replaceAll(RegExp(r'[^0-9]'), '');

    if (numbers.length > 8) {
      numbers = numbers.substring(0, 8);
    }

    String formatted;

    if (numbers.length > 2) {
      formatted = '${numbers.substring(0, 2)}-${numbers.substring(2)}';
    } else {
      formatted = numbers;
    }

    if (studentNumberController.text != formatted) {
      studentNumberController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }

    setState(() {});
  }

  /*
  |--------------------------------------------------------------------------
  | VALIDATION
  |--------------------------------------------------------------------------
  */

  bool get hasMinimumLength => passwordController.text.length >= 8;

  bool get hasUppercase => RegExp(r'[A-Z]').hasMatch(passwordController.text);

  bool get hasSpecialCharacter =>
      RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=]').hasMatch(passwordController.text);

  bool get passwordsMatch =>
      passwordController.text.isNotEmpty &&
      passwordController.text == confirmPasswordController.text;

  bool get validEmail =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
          .hasMatch(emailController.text.trim());

  bool get validStudentNumber =>
      RegExp(r'^\d{2}-\d{6}$').hasMatch(studentNumberController.text.trim());

  /*
  |--------------------------------------------------------------------------
  | CAN REGISTER
  |--------------------------------------------------------------------------
  */

  bool get canRegister =>
      validStudentNumber &&
      firstNameController.text.trim().isNotEmpty &&
      surnameController.text.trim().isNotEmpty &&
      validEmail &&
      hasMinimumLength &&
      hasUppercase &&
      hasSpecialCharacter &&
      passwordsMatch &&
      profilePhoto != null &&
      facePhotoValid &&
      form5 != null &&
      !validatingPhoto &&
      !registering;

  /*
  |--------------------------------------------------------------------------
  | REGISTER
  |--------------------------------------------------------------------------
  */

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

    /*
    |--------------------------------------------------------------------------
    | REGISTRATION CREATED
    |--------------------------------------------------------------------------
    |
    | Laravel has now:
    |
    | - created the User
    | - created the Student
    | - stored the reference photo
    | - stored the Form 5
    | - returned a Sanctum token
    |
    | RegistrationService saves that token.
    |
    */

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AppDialog(
          type: AppDialogType.success,
          title: 'Registration Successful',
          message: 'Your account has been created. Continue to live face verification.',
          primaryText: 'Continue',
          primaryAction: () {
            Navigator.of(dialogContext).pop();
          },
        );
      },
    );

    if (!mounted) {
      return;
    }

    /*
    |--------------------------------------------------------------------------
    | STAGE 14
    |--------------------------------------------------------------------------
    |
    | DO NOT enter the dashboard yet.
    |
    | Go to the live biometric verification screen.
    |
    | Flutter camera
    |      ↓
    | Laravel API
    |      ↓
    | MediaPipe
    | OpenCV
    | InsightFace
    |      ↓
    | verification_status = verified
    |
    */

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const RegistrationFaceVerificationScreen(),
      ),
    );
  }

  /*
  |--------------------------------------------------------------------------
  | ERROR DIALOG
  |--------------------------------------------------------------------------
  */

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

  /*
  |--------------------------------------------------------------------------
  | UI
  |--------------------------------------------------------------------------
  */

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 30, 28, 45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /*
          |--------------------------------------------------------------------------
          | STUDENT NUMBER
          |--------------------------------------------------------------------------
          */

          AppTextField(
            label: 'Student Number *',
            hint: '24-010342',
            controller: studentNumberController,
            keyboardType: TextInputType.number,
            maxLength: 9,
            helperText: 'Format: YY-NNNNNN (example: 24-010342)',
            textInputAction: TextInputAction.next,
            onChanged: formatStudentNumber,
          ),

          const SizedBox(height: 18),

          /*
          |--------------------------------------------------------------------------
          | FIRST + SURNAME
          |--------------------------------------------------------------------------
          */
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  label: 'First Name *',
                  hint: 'First Name',
                  controller: firstNameController,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) {
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppTextField(
                  label: 'Surname *',
                  hint: 'Surname',
                  controller: surnameController,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) {
                    setState(() {});
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          /*
          |--------------------------------------------------------------------------
          | MIDDLE + EXTENSION
          |--------------------------------------------------------------------------
          */
          Row(
            children: [
              Expanded(
                flex: 2,
                child: AppTextField(
                  label: 'Middle Name',
                  hint: 'Middle Name',
                  controller: middleNameController,
                  textInputAction: TextInputAction.next,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppTextField(
                  label: 'Extension',
                  hint: 'Jr.',
                  controller: extensionController,
                  textInputAction: TextInputAction.next,
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          /*
          |--------------------------------------------------------------------------
          | EMAIL
          |--------------------------------------------------------------------------
          */
          AppTextField(
            label: 'Email Address *',
            hint: 'example@email.com',
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            onChanged: (_) {
              setState(() {});
            },
          ),

          if (emailController.text.isNotEmpty && !validEmail) ...[
            const SizedBox(height: 6),
            const Text(
              'Enter a valid email address',
              style: TextStyle(fontSize: 10, color: AppColors.error),
            ),
          ],

          const SizedBox(height: 18),

          /*
          |--------------------------------------------------------------------------
          | PASSWORD
          |--------------------------------------------------------------------------
          */
          AppTextField(
            label: 'Set Password *',
            hint: 'Enter your password',
            controller: passwordController,
            obscureText: hidePassword,
            textInputAction: TextInputAction.next,
            onChanged: (_) {
              setState(() {});
            },
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
              ),
            ),
          ),

          const SizedBox(height: 10),

          _PasswordRequirement(
            passed: hasMinimumLength,
            text: 'At least 8 characters',
          ),

          _PasswordRequirement(
            passed: hasUppercase,
            text: 'At least one uppercase letter',
          ),

          _PasswordRequirement(
            passed: hasSpecialCharacter,
            text: 'At least one special character',
          ),

          const SizedBox(height: 18),

          /*
          |--------------------------------------------------------------------------
          | CONFIRM PASSWORD
          |--------------------------------------------------------------------------
          */
          AppTextField(
            label: 'Confirm Password *',
            hint: 'Confirm your password',
            controller: confirmPasswordController,
            obscureText: hideConfirmPassword,
            textInputAction: TextInputAction.done,
            onChanged: (_) {
              setState(() {});
            },
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
              ),
            ),
          ),

          if (confirmPasswordController.text.isNotEmpty) ...[
            const SizedBox(height: 7),
            Row(
              children: [
                Icon(
                  passwordsMatch
                      ? Icons.check_circle_rounded
                      : Icons.cancel_rounded,
                  size: 15,
                  color: passwordsMatch ? AppColors.success : AppColors.error,
                ),
                const SizedBox(width: 6),
                Text(
                  passwordsMatch ? 'Passwords match' : 'Passwords do not match',
                  style: TextStyle(
                    fontSize: 11,
                    color: passwordsMatch ? AppColors.success : AppColors.error,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 26),

          /*
          |--------------------------------------------------------------------------
          | REFERENCE PHOTO
          |--------------------------------------------------------------------------
          */
          const Text(
            'Reference Photo *',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),

          const SizedBox(height: 5),

          const Text(
            'Upload one clear face photo. The actual server will validate it before registration.',
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),

          const SizedBox(height: 10),

          InkWell(
            onTap: validatingPhoto || registering ? null : pickProfilePhoto,
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: facePhotoValid ? AppColors.success : AppColors.gold,
                  width: 1.3,
                ),
              ),
              child: Column(
                children: [
                  if (validatingPhoto)
                    const SizedBox(
                      width: 42,
                      height: 42,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: AppColors.navy,
                      ),
                    )
                  else
                    Icon(
                      facePhotoValid
                          ? Icons.verified_rounded
                          : Icons.add_a_photo_outlined,
                      size: 48,
                      color: facePhotoValid
                          ? AppColors.success
                          : AppColors.navy,
                    ),

                  const SizedBox(height: 10),

                  Text(
                    profilePhoto?.name ?? 'Upload Reference Photo',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 5),

                  Text(
                    validatingPhoto
                        ? 'Validating with face service...'
                        : photoValidationMessage ?? 'JPG, JPEG or PNG',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: facePhotoValid
                          ? AppColors.success
                          : AppColors.textSecondary,
                    ),
                  ),

                  if (profilePhoto != null && !validatingPhoto) ...[
                    const SizedBox(height: 7),
                    TextButton(
                      onPressed: removeProfilePhoto,
                      child: const Text('Remove Photo'),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 22),

          /*
          |--------------------------------------------------------------------------
          | FORM 5
          |--------------------------------------------------------------------------
          */
          const Text(
            'Form 5 Document *',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),

          const SizedBox(height: 5),

          const Text(
            'Upload your current Form 5 for student information verification.',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),

          const SizedBox(height: 10),

          InkWell(
            onTap: registering ? null : pickForm5,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: form5 != null ? AppColors.success : AppColors.gold,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    form5 != null
                        ? Icons.check_circle_outline_rounded
                        : Icons.upload_file_outlined,
                    size: 45,
                    color: form5 != null ? AppColors.success : AppColors.navy,
                  ),

                  const SizedBox(height: 8),

                  Text(
                    form5?.name ?? 'Upload your Form 5',
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 4),

                  const Text(
                    'PDF only • Maximum 10 MB',
                    style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                  ),

                  if (form5 != null)
                    TextButton(
                      onPressed: removeForm5,
                      child: const Text('Remove Form 5'),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 30),

          /*
          |--------------------------------------------------------------------------
          | CREATE ACCOUNT
          |--------------------------------------------------------------------------
          */
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: canRegister ? submitRegistration : null,
              child: registering
                  ? const SizedBox(
                      width: 23,
                      height: 23,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Create Student Account'),
            ),
          ),

          const SizedBox(height: 15),

          const Center(
            child: Text(
              'Your account will require live facial verification before activation.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/*
|--------------------------------------------------------------------------
| PASSWORD REQUIREMENT
|--------------------------------------------------------------------------
*/

class _PasswordRequirement extends StatelessWidget {
  final bool passed;

  final String text;

  const _PasswordRequirement({required this.passed, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Icon(
            passed ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 14,
            color: passed ? AppColors.success : AppColors.textMuted,
          ),
          const SizedBox(width: 7),
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              color: passed ? AppColors.success : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
