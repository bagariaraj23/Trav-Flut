import 'package:flutter/material.dart';
import 'package:tripthread/utils/app_theme.dart';

/// Soft branded empty state when a trip has no cover (or the image fails).
class TripCoverPlaceholder extends StatelessWidget {
  final String? title;
  final String? destination;
  final double iconSize;
  final bool compact;

  const TripCoverPlaceholder({
    super.key,
    this.title,
    this.destination,
    this.iconSize = 40,
    this.compact = false,
  });

  String get _label {
    final dest = destination?.trim();
    if (dest != null && dest.isNotEmpty) return dest;
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    return 'Add a cover';
  }

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.95),
      fontSize: compact ? 11 : 14,
      fontWeight: FontWeight.w600,
      height: 1.2,
    );

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.accent,
            Color(0xFF8B4A1F),
            AppTheme.ink,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.photo_outlined,
                size: iconSize,
                color: Colors.white.withValues(alpha: 0.92),
              ),
              SizedBox(height: compact ? 4 : 8),
              Text(
                _label,
                style: labelStyle,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
