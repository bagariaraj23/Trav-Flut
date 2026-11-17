import 'package:flutter/material.dart';

const skipStep = Duration(seconds: 5);

const playbackSpeeds = <double>[0.5, 1, 1.25, 1.5, 2];

Duration clampSeek(Duration position, Duration delta, Duration total) {
  final next = position + delta;
  if (next < Duration.zero) return Duration.zero;
  if (total > Duration.zero && next > total) return total;
  return next;
}

/// Three columns on a phone, more as the window widens.
int mediaGridColumns(double width) {
  if (width >= 1100) return 6;
  if (width >= 800) return 5;
  if (width >= 600) return 4;
  return 3;
}

double nextPlaybackSpeed(double current) {
  final index = playbackSpeeds.indexWhere((speed) => (speed - current).abs() < 0.01);
  if (index < 0) return 1;
  return playbackSpeeds[(index + 1) % playbackSpeeds.length];
}

/// Left half skips back, right half skips forward.
class GallerySkipLayer extends StatelessWidget {
  const GallerySkipLayer({
    super.key,
    required this.onSkip,
    required this.child,
  });

  final ValueChanged<Duration> onSkip;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTapDown: (details) {
        final width = context.size?.width ?? 0;
        final delta = details.localPosition.dx < width / 2
            ? -skipStep
            : skipStep;
        onSkip(delta);
      },
      onDoubleTap: () {},
      child: child,
    );
  }
}

class PhotoOrderBadge extends StatelessWidget {
  const PhotoOrderBadge({super.key, required this.position});

  final int position;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$position',
        style: TextStyle(
          color: scheme.onPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
