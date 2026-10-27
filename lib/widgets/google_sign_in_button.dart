import 'package:flutter/material.dart';
import 'google_logo.dart';

/// Styled "Continue with Google" button matching the Studexa design language.
class GoogleSignInButton extends StatelessWidget {
  /// Creates a [GoogleSignInButton] with tap handler, loading state, and custom label.
  const GoogleSignInButton({
    super.key,
    required this.onPressed,
    this.isLoading = false,
    this.text = 'Continue with Google',
  });

  /// Callback invoked when the button is tapped while not loading.
  final VoidCallback? onPressed;

  /// Whether an OAuth sign-in flow is currently in progress.
  final bool isLoading;

  /// Button label displayed next to the [GoogleLogo].
  final String text;

  static const _surfaceWhite = Color(0xFFFBF9F8);
  static const _outlineVariant = Color(0xFFC6C5D4);
  static const _textPrimary = Color(0xFF1B1C1C);

  /// Builds the full-width outlined Google Sign-In button or a progress spinner when [isLoading] is true.
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: _surfaceWhite,
          foregroundColor: _textPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          side: const BorderSide(color: _outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: isLoading ? null : onPressed,
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(_textPrimary),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const GoogleLogo(size: 20),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// A subtle horizontal "OR" divider matching the Studexa form layout.
class AuthDivider extends StatelessWidget {
  /// Creates an [AuthDivider] with an optional center [label] (defaults to `'OR'`).
  const AuthDivider({super.key, this.label = 'OR'});

  /// Text displayed between the left and right horizontal divider lines.
  final String label;

  static const _dividerColor = Color(0xFFC6C5D4);
  static const _labelColor = Color(0xFF767683);

  /// Builds the centered label flanked by two expanded [Divider] lines.
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Divider(
            color: _dividerColor,
            thickness: 0.8,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _labelColor,
              letterSpacing: 1.0,
            ),
          ),
        ),
        const Expanded(
          child: Divider(
            color: _dividerColor,
            thickness: 0.8,
          ),
        ),
      ],
    );
  }
}
