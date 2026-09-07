import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../services/auth_service.dart';
import '../auth/auth_gate.dart';

class HomeScreen extends StatelessWidget {
  final Map<String, dynamic>? user;

  final Map<String, dynamic>? student;

  const HomeScreen({super.key, this.user, this.student});

  @override
  Widget build(BuildContext context) {
    final firstName =
        student?['firstname']?.toString() ??
        user?['name']?.toString() ??
        'Student';

    final studentNumber = student?['student_number']?.toString() ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            /*
            |--------------------------------------------------------------------------
            | HEADER
            |--------------------------------------------------------------------------
            */

            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
              color: AppColors.navy,
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 28,
                    backgroundColor: Color(0xFFD9D9D9),
                    child: Icon(Icons.person, color: Colors.white),
                  ),

                  const SizedBox(width: 14),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome, $firstName',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),

                        if (studentNumber.isNotEmpty)
                          Text(
                            studentNumber,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFFB8B8D9),
                            ),
                          ),
                      ],
                    ),
                  ),

                  IconButton(
                    onPressed: () {},
                    icon: const Icon(
                      Icons.account_circle_outlined,
                      color: AppColors.gold,
                      size: 34,
                    ),
                  ),
                ],
              ),
            ),

            /*
            |--------------------------------------------------------------------------
            | CONTENT
            |--------------------------------------------------------------------------
            */
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Today\'s Activity',
                      style: TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),

                    const SizedBox(height: 6),

                    const Text(
                      'Login connection successful. We will connect real events in the next stages.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),

                    const SizedBox(height: 24),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Column(
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            color: AppColors.success,
                            size: 54,
                          ),
                          SizedBox(height: 14),
                          Text(
                            'Laravel API Connected',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 7),
                          Text(
                            'Your Sanctum token has been stored securely on this device.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 25),

                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await AuthService.instance.logout();

                          if (!context.mounted) {
                            return;
                          }

                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(builder: (_) => const AuthGate()),
                            (route) => false,
                          );
                        },
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text('Test Logout'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
