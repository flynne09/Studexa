import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Consistent, accessible feedback messages for user-initiated actions.
class AppFeedback {
  AppFeedback._();

  static void success(
    BuildContext context,
    String message, {
    String title = 'Success',
    Duration duration = const Duration(seconds: 4),
  }) {
    _show(
      context,
      title: title,
      message: message,
      icon: Icons.check_circle_outline_rounded,
      color: AppTheme.success,
      backgroundColor: AppTheme.successContainer,
      borderColor: AppTheme.successBorder,
      duration: duration,
    );
  }

  static void error(
    BuildContext context,
    String message, {
    String title = 'Something went wrong',
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 5),
  }) {
    _show(
      context,
      title: title,
      message: message,
      icon: Icons.error_outline_rounded,
      color: AppTheme.error,
      backgroundColor: AppTheme.errorContainer,
      borderColor: AppTheme.errorBorder,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
    );
  }

  static void warning(
    BuildContext context,
    String message, {
    String title = 'Action needed',
    Duration duration = const Duration(seconds: 4),
  }) {
    _show(
      context,
      title: title,
      message: message,
      icon: Icons.warning_amber_rounded,
      color: AppTheme.warning,
      backgroundColor: AppTheme.warningContainer,
      borderColor: AppTheme.warningBorder,
      duration: duration,
    );
  }

  static void info(
    BuildContext context,
    String message, {
    String title = 'Notice',
    bool compact = false,
    Duration duration = const Duration(seconds: 3),
  }) {
    _show(
      context,
      title: title,
      message: message,
      icon: Icons.info_outline_rounded,
      color: AppTheme.info,
      backgroundColor: AppTheme.infoContainer,
      borderColor: AppTheme.infoBorder,
      compact: compact,
      duration: duration,
    );
  }

  static void _show(
    BuildContext context, {
    required String title,
    required String message,
    required IconData icon,
    required Color color,
    required Color backgroundColor,
    required Color borderColor,
    required Duration duration,
    bool compact = false,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    if (compact) {
      messenger.hideCurrentMaterialBanner();
      messenger.showMaterialBanner(
        MaterialBanner(
          backgroundColor: backgroundColor,
          dividerColor: borderColor,
          elevation: 1,
          leading: Icon(icon, color: color, size: 20),
          leadingPadding: const EdgeInsets.only(left: AppTheme.spacingLg),
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingLg,
            vertical: AppTheme.spacingSm,
          ),
          content: Semantics(
            liveRegion: true,
            label: '$title. $message',
            child: Text(
              message,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                height: 1.3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Dismiss',
              onPressed: messenger.hideCurrentMaterialBanner,
              icon: const Icon(
                Icons.close_rounded,
                color: AppTheme.textSecondary,
                size: 19,
              ),
            ),
          ],
        ),
      );
      return;
    }

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: backgroundColor,
          elevation: 4,
          behavior: SnackBarBehavior.floating,
          duration: duration,
          showCloseIcon: actionLabel == null,
          closeIconColor: AppTheme.textSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: AppTheme.borderRadiusMd,
            side: BorderSide(color: borderColor),
          ),
          content: Semantics(
            liveRegion: true,
            label: '$title. $message',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 21),
                ),
                const SizedBox(width: AppTheme.spacingMd),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        message,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          action: actionLabel != null && onAction != null
              ? SnackBarAction(
                  label: actionLabel,
                  textColor: color,
                  onPressed: onAction,
                )
              : null,
        ),
      );
  }
}
