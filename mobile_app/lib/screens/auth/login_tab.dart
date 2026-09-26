import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../services/auth_service.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_text_field.dart';
import '../home/home_screen.dart';

class LoginTab extends StatefulWidget {
  const LoginTab({super.key});

  @override
  State<LoginTab> createState() => _LoginTabState();
}

class _LoginTabState extends State<LoginTab> {
  final studentNumberController = TextEditingController();

  final passwordController = TextEditingController();

  bool rememberMe = false;

  bool hidePassword = true;

  bool loading = false;

  @override
  void dispose() {
    studentNumberController.dispose();

    passwordController.dispose();

    super.dispose();
  }

  /*
  |--------------------------------------------------------------------------
  | STUDENT NUMBER FORMAT
  |--------------------------------------------------------------------------
  */

  void formatStudentNumber(String value) {
    var numbers = value.replaceAll(RegExp(r'[^0-9]'), '');

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
  }

  /*
  |--------------------------------------------------------------------------
  | LOGIN
  |--------------------------------------------------------------------------
  */

  Future<void> login() async {
    if (loading) {
      return;
    }

    final studentNumber = studentNumberController.text.trim();

    final password = passwordController.text;

    if (studentNumber.isEmpty) {
      await showError(
        'Student Number Required',
        'Enter your student number before logging in.',
      );

      return;
    }

    if (!RegExp(r'^\d{2}-\d{6}$').hasMatch(studentNumber)) {
      await showError(
        'Invalid Student Number',
        'Use the format YY-NNNNNN, for example 23-140012.',
      );

      return;
    }

    if (password.isEmpty) {
      await showError(
        'Password Required',
        'Enter your password before logging in.',
      );

      return;
    }

    setState(() {
      loading = true;
    });

    final result = await AuthService.instance.login(
      studentNumber: studentNumber,
      password: password,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      loading = false;
    });

    if (!result.success) {
      await showError('Unable to Log In', result.message);

      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => HomeScreen(user: result.user, student: result.student),
      ),
      (route) => false,
    );
  }

  Future<void> showError(String title, String message) async {
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
          primaryText: 'Try Again',
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
      padding: const EdgeInsets.fromLTRB(30, 34, 30, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            label: 'Student ID',
            hint: '23-140012',
            controller: studentNumberController,
            keyboardType: TextInputType.number,
            maxLength: 9,
            textInputAction: TextInputAction.next,
            onChanged: formatStudentNumber,
          ),

          const SizedBox(height: 28),

          AppTextField(
            label: 'Password',
            hint: 'Enter your Password',
            controller: passwordController,
            obscureText: hidePassword,
            textInputAction: TextInputAction.done,
            prefixIcon: const Icon(Icons.lock_outline, size: 20),
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

          const SizedBox(height: 13),

          Row(
            children: [
              SizedBox(
                width: 30,
                height: 30,
                child: Checkbox(
                  value: rememberMe,
                  activeColor: AppColors.navy,
                  onChanged: (value) {
                    setState(() {
                      rememberMe = value ?? false;
                    });
                  },
                ),
              ),

              const SizedBox(width: 5),

              const Expanded(
                child: Text(
                  'Remember me',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),

              TextButton(
                onPressed: () {
                  /*
                   * Forgot password
                   * comes later.
                   */
                },
                child: const Text(
                  'Forgot password?',
                  style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: loading ? null : login,
              child: loading
                  ? const SizedBox(
                      width: 23,
                      height: 23,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Log in'),
            ),
          ),
        ],
      ),
    );
  }
}
