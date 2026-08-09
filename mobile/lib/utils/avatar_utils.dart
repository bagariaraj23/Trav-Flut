import 'package:flutter/material.dart';

class AvatarUtils {
  static const List<Color> _palette = [
    Color(0xFFEF5350),
    Color(0xFFAB47BC),
    Color(0xFF5C6BC0),
    Color(0xFF29B6F6),
    Color(0xFF26A69A),
    Color(0xFF66BB6A),
    Color(0xFFFFCA28),
    Color(0xFFFF7043),
  ];

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
    if (normalized.isEmpty) return Colors.blueGrey;
    final hash = normalized.codeUnits.fold<int>(0, (acc, c) => (acc * 31 + c) & 0x7fffffff);
    return _palette[hash % _palette.length];
  }
}

