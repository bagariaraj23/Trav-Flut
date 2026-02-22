import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:tripthread/providers/auth_provider.dart';

/// Shows a logout confirmation dialog with options for single-device
/// or all-device logout. Used in both HomeScreen and SettingsScreen.
Future<void> showLogoutDialog(BuildContext context) {
  return showDialog(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('Logout'),
        content: const Text('Choose how you want to logout:'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              final authProvider = context.read<AuthProvider>();
              await authProvider.logout(logoutAll: false);
              if (context.mounted) {
                context.go('/login');
              }
            },
            child: const Text('Logout'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              final authProvider = context.read<AuthProvider>();
              await authProvider.logout(logoutAll: true);
              if (context.mounted) {
                context.go('/login');
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Logout from all devices'),
          ),
        ],
      );
    },
  );
}
