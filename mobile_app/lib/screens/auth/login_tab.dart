import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../services/auth_service.dart';
import '../../widgets/app_dialog.dart';
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
        builder: (_) => const HomeScreen(),
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

  // --------------------------------------------------------------------------
  // CUSTOM ROUNDED INPUT FIELD BUILDER
  // --------------------------------------------------------------------------

  Widget _buildRoundedInputField({
    required String label,
    required String hint,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    TextInputAction textInputAction = TextInputAction.next,
    bool obscureText = false,
    Widget? prefixIcon,
    Widget? suffixIcon,
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.navy,
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
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRoundedInputField(
            label: 'Student ID',
            hint: '12-345678',
            controller: studentNumberController,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            prefixIcon: const Icon(
              Icons.tag_rounded,
              size: 18,
              color: AppColors.textMuted,
            ),
            onChanged: formatStudentNumber,
          ),

          const SizedBox(height: 20),

          _buildRoundedInputField(
            label: 'Password',
            hint: 'Enter your Password',
            controller: passwordController,
            obscureText: hidePassword,
            textInputAction: TextInputAction.done,
            prefixIcon: const Icon(
              Icons.lock_outline_rounded,
              size: 18,
              color: AppColors.textMuted,
            ),
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

          const SizedBox(height: 12),

          Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: rememberMe,
                  activeColor: AppColors.navy,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  onChanged: (value) {
                    setState(() {
                      rememberMe = value ?? false;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
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
                onPressed: () {},
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Forgot password?',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: loading ? null : login,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.navy,
                disabledBackgroundColor: const Color(0xFFCBD5E1),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              child: loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Log in',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}