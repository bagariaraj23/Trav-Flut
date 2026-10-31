import 'package:flutter/material.dart';
import 'package:tripthread/utils/app_theme.dart';

class AvatarUtils {
  /// Warm, distinguishable fallbacks. Same key always maps to the same color.
  static List<Color> get _palette => AppTheme.avatarPalette;

  /// Initials rule:
  /// first letter of first word + (first letter of second word,
  /// or last letter of first word when second word is absent).
  static String initialsFromName(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return '?';
    final parts = text.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';

    final first = parts.first;
    final firstChar = first[0].toUpperCase();
    final secondChar = parts.length >= 2
        ? parts[1][0].toUpperCase()
        : first[first.length - 1].toUpperCase();
    return '$firstChar$secondChar';
  }

  /// Deterministic color from stable key (e.g. userId or conversationId).
  static Color colorForKey(String? key) {
    final normalized = (key ?? '').trim().toLowerCase();
    if (normalized.isEmpty) return AppTheme.mutedForeground;
    final hash = normalized.codeUnits.fold<int>(0, (acc, c) => (acc * 31 + c) & 0x7fffffff);
    return _palette[hash % _palette.length];
  }
}

