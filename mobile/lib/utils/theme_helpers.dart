import 'package:flutter/material.dart';

/// Central theme helper utilities for consistent dark/light mode support
class ThemeHelpers {
  /// Get a theme-aware surface color (light background tint)
  /// Use for cards, containers, input fills that need subtle background
  static Color surfaceTint(BuildContext context, {double lightAlpha = 0.04, double darkAlpha = 0.08}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return theme.colorScheme.onSurface.withValues(alpha: isDark ? darkAlpha : lightAlpha);
  }

  /// Get a theme-aware border color
  static Color borderColor(BuildContext context, {double lightAlpha = 0.10, double darkAlpha = 0.18}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return theme.colorScheme.onSurface.withValues(alpha: isDark ? darkAlpha : lightAlpha);
  }

  /// Get a theme-aware icon color (for secondary icons)
  static Color iconColor(BuildContext context) {
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }

  /// Get a theme-aware secondary text color
  static Color secondaryTextColor(BuildContext context) {
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }

  /// Get a theme-aware disabled/placeholder color
  static Color disabledColor(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return theme.colorScheme.onSurfaceVariant.withValues(
      alpha: isDark ? 0.5 : 0.4,
    );
  }

  /// Get a theme-aware divider/handle color (for drag handles, dividers)
  static Color dividerColor(BuildContext context, {double lightAlpha = 0.14, double darkAlpha = 0.20}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return theme.colorScheme.onSurface.withValues(alpha: isDark ? darkAlpha : lightAlpha);
  }

  /// Replace Colors.grey[400] with theme-aware variant
  static Color grey400(BuildContext context) {
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }

  /// Replace Colors.grey[600] with theme-aware variant
  static Color grey600(BuildContext context) {
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }

  /// Replace Colors.grey[700] with theme-aware variant
  static Color grey700(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return theme.colorScheme.onSurfaceVariant.withValues(alpha: isDark ? 0.9 : 0.7);
  }

  /// Replace Colors.grey[800] with theme-aware variant
  static Color grey800(BuildContext context) {
    return Theme.of(context).colorScheme.onSurface;
  }

  /// Replace Colors.grey[900] with theme-aware variant
  static Color grey900(BuildContext context) {
    return Theme.of(context).colorScheme.onSurface;
  }

  /// Get theme-aware shadow color for box shadows
  static Color shadowColor(BuildContext context, {double lightAlpha = 0.08, double darkAlpha = 0.25}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Colors.black.withValues(alpha: isDark ? darkAlpha : lightAlpha);
  }
}
