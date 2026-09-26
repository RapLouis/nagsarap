import 'package:flutter/material.dart';

import '../core/app_colors.dart';

enum AppDialogType { success, error, warning, info }

class AppDialog extends StatelessWidget {
  final AppDialogType type;
  final String title;
  final String message;

  final String primaryText;
  final VoidCallback primaryAction;

  final String? secondaryText;
  final VoidCallback? secondaryAction;

  const AppDialog({
    super.key,
    required this.type,
    required this.title,
    required this.message,
    required this.primaryText,
    required this.primaryAction,
    this.secondaryText,
    this.secondaryAction,
  });

  Color get color {
    switch (type) {
      case AppDialogType.success:
        return AppColors.success;

      case AppDialogType.error:
        return AppColors.error;

      case AppDialogType.warning:
        return AppColors.warning;

      case AppDialogType.info:
        return AppColors.info;
    }
  }

  IconData get icon {
    switch (type) {
      case AppDialogType.success:
        return Icons.check_rounded;

      case AppDialogType.error:
        return Icons.close_rounded;

      case AppDialogType.warning:
        return Icons.warning_amber_rounded;

      case AppDialogType.info:
        return Icons.info_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 32, 26, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.12),
              ),
              child: Icon(icon, color: color, size: 48),
            ),

            const SizedBox(height: 24),

            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),

            const SizedBox(height: 10),

            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),

            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: primaryAction,
                child: Text(primaryText),
              ),
            ),

            if (secondaryText != null) ...[
              const SizedBox(height: 6),

              TextButton(
                onPressed: secondaryAction,
                child: Text(secondaryText!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
