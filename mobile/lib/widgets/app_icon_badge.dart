import 'package:flutter/material.dart';
import 'package:tripthread/utils/app_theme.dart';

/// Compact top-right count for app-bar / action icons. Shows `9+` above 9.
String formatIconBadgeCount(int count) {
  if (count <= 0) return '';
  if (count > 9) return '9+';
  return '$count';
}

/// Wraps [icon] with a minimized badge in the top-right corner when [count] > 0.
class AppIconBadge extends StatelessWidget {
  final Widget icon;
  final int count;
  final String? tooltip;
  final VoidCallback? onPressed;
  final Color? badgeColor;

  const AppIconBadge({
    super.key,
    required this.icon,
    required this.count,
    this.tooltip,
    this.onPressed,
    this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    final label = formatIconBadgeCount(count);
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: icon,
          tooltip: tooltip,
          onPressed: onPressed,
        ),
        if (label.isNotEmpty)
          Positioned(
            top: 6,
            right: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 14),
              decoration: BoxDecoration(
                color: badgeColor ?? AppTheme.likeRose,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 1,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}
