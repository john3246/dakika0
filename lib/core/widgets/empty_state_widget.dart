// ─── core/widgets/empty_state_widget.dart ────────────────────────────────────
// Reusable empty & error state layout used across order lists, the admin panel,
// and the courier feed screen.  Accepts an icon, a message, and an optional
// Retry callback.

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

enum EmptyStateType { empty, error }

class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onRetry;
  final EmptyStateType type;

  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onRetry,
    this.type = EmptyStateType.empty,
  });

  /// Convenience constructor for error states.
  const EmptyStateWidget.error({
    super.key,
    this.icon = Icons.wifi_off_rounded,
    this.title = 'Something went wrong',
    this.subtitle = 'We had trouble loading your data.',
    this.onRetry,
  }) : type = EmptyStateType.error;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isError = type == EmptyStateType.error;

    final Color iconColor = isError
        ? AppColors.error.withOpacity(0.7)
        : (isDark ? AppColors.gold.withOpacity(0.6) : AppColors.navy.withOpacity(0.3));

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Icon bubble ───────────────────────────────────────────────
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: iconColor.withOpacity(0.1),
              ),
              child: Icon(icon, size: 42, color: iconColor),
            ),

            const SizedBox(height: 20),

            // ── Title ─────────────────────────────────────────────────────
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white70 : AppColors.navy,
                  ),
            ),

            // ── Subtitle ──────────────────────────────────────────────────
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.white38 : Colors.grey.shade600,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],

            // ── Retry button ──────────────────────────────────────────────
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try Again'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isError ? AppColors.error : AppColors.navy,
                  side: BorderSide(
                    color: isError
                        ? AppColors.error.withOpacity(0.5)
                        : AppColors.navy.withOpacity(0.4),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
