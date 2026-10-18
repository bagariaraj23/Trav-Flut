import 'package:flutter/material.dart';
import 'package:tripthread/utils/app_theme.dart';

/// Snackbars and empty/error states aligned with global [ThemeData] / warm palette.
class AppFeedback {
  AppFeedback._();

  static void showSuccess(
    BuildContext context,
    String message, {
    Duration? duration,
  }) {
    _show(context, message, duration: duration);
  }

  static void showError(
    BuildContext context,
    String message, {
    Duration? duration,
  }) {
    _show(
      context,
      message,
      backgroundColor: Theme.of(context).colorScheme.error,
      duration: duration,
    );
  }

  /// Non-destructive notice (declined request, pending action). Amber, not failure red.
  static void showNotice(
    BuildContext context,
    String message, {
    Duration? duration,
  }) {
    _show(
      context,
      message,
      backgroundColor: AppTheme.upcoming,
      duration: duration,
    );
  }

  static void _show(
    BuildContext context,
    String message, {
    Color? backgroundColor,
    Duration? duration,
  }) {
    final bar = SnackBar(
      content: Text(message),
      backgroundColor: backgroundColor,
      duration: duration ?? const Duration(seconds: 4),
    );
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(bar);
  }

  static Widget empty({
    required BuildContext context,
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? action,
    bool expand = true,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final content = Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: scheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 20),
            action,
          ],
        ],
      ),
    );
    return expand ? Center(child: content) : content;
  }

  static Widget error({
    required BuildContext context,
    required String title,
    required String message,
    required VoidCallback onRetry,
    bool expand = true,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final content = Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 56, color: scheme.error),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
    return expand ? Center(child: content) : content;
  }
}
