import 'package:flutter/material.dart';

const skipStep = Duration(seconds: 5);

const playbackSpeeds = <double>[0.5, 1, 1.25, 1.5, 2];

Duration clampSeek(Duration position, Duration delta, Duration total) {
  final next = position + delta;
  if (next < Duration.zero) return Duration.zero;
  if (total > Duration.zero && next > total) return total;
  return next;
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$position',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
