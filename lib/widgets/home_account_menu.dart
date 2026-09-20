import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shared profile menu used by the teacher and student dashboards.
class HomeAccountMenu extends StatelessWidget {
  const HomeAccountMenu({
    super.key,
    required this.displayName,
    required this.email,
    required this.roleLabel,
    required this.logoutItemKey,
    required this.onLogout,
  });

  final String displayName;
  final String email;
  final String roleLabel;
  final Key logoutItemKey;
  final VoidCallback onLogout;

  String get _initial {
    final trimmedName = displayName.trim();
    return trimmedName.isEmpty
        ? roleLabel[0].toUpperCase()
        : trimmedName[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '$roleLabel account options',
      color: AppTheme.surfaceWhite,
      surfaceTintColor: Colors.transparent,
      elevation: 10,
      offset: const Offset(0, 12),
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 320),
      shape: RoundedRectangleBorder(
        borderRadius: AppTheme.borderRadiusLg,
        side: const BorderSide(color: AppTheme.outlineSubtle),
      ),
      onSelected: (value) {
        if (value == 'logout') onLogout();
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  gradient: AppTheme.heroGradient,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  _initial,
                  style: const TextStyle(
                    color: AppTheme.onPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryContainer,
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusPill,
                        ),
                      ),
                      child: Text(
                        '$roleLabel Account',
                        style: const TextStyle(
                          color: AppTheme.primaryNavy,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          key: logoutItemKey,
          value: 'logout',
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.errorContainer,
              borderRadius: AppTheme.borderRadiusMd,
              border: Border.all(color: AppTheme.errorBorder),
            ),
            child: const Row(
              children: [
                Icon(Icons.logout_rounded, color: AppTheme.error, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Log Out',
                        style: TextStyle(
                          color: AppTheme.error,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Return to role selection',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          gradient: AppTheme.heroGradient,
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.surfaceWhite, width: 2),
          boxShadow: AppTheme.cardShadow,
        ),
        alignment: Alignment.center,
        child: Text(
          _initial,
          style: const TextStyle(
            color: AppTheme.onPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

Future<bool> showStudexaLogoutDialog(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppTheme.surfaceWhite,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: AppTheme.borderRadiusXl),
      title: const Row(
        children: [
          _LogoutDialogIcon(),
          SizedBox(width: 12),
          Expanded(child: Text('Log Out')),
        ],
      ),
      content: const Text(
        'Are you sure you want to log out of Studexa? You will return to role selection and can sign in again at any time.',
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.error,
            foregroundColor: AppTheme.onPrimary,
          ),
          onPressed: () => Navigator.pop(dialogContext, true),
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: const Text('Log Out'),
        ),
      ],
    ),
  );

  return confirmed ?? false;
}

class _LogoutDialogIcon extends StatelessWidget {
  const _LogoutDialogIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: const BoxDecoration(
        color: AppTheme.errorContainer,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.logout_rounded, color: AppTheme.error, size: 21),
    );
  }
}
