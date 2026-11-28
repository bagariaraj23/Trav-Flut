import 'package:flutter/material.dart';
import 'package:tripthread/models/trip.dart';
import 'package:tripthread/utils/app_theme.dart';

/// Compact three-tile picker for final-post card layout (above Publish).
class FinalPostTemplatePicker extends StatelessWidget {
  final FinalPostTemplateChoice value;
  final ValueChanged<FinalPostTemplateChoice> onChanged;
  final bool enabled;

  const FinalPostTemplatePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final muted = AppTheme.feedMutedText(Theme.of(context).brightness);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CARD LAYOUT',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontSize: 11,
                letterSpacing: 1.0,
                color: muted,
              ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _Tile(
                label: 'Postcard',
                kind: _Kind.postcard,
                selected: value == FinalPostTemplateChoice.postcard,
                enabled: enabled,
                onTap: () => onChanged(FinalPostTemplateChoice.postcard),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Tile(
                label: 'Map',
                kind: _Kind.map,
                selected: value == FinalPostTemplateChoice.mapFirst,
                enabled: enabled,
                onTap: () => onChanged(FinalPostTemplateChoice.mapFirst),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Tile(
                label: 'Threads',
                kind: _Kind.threads,
                selected: value == FinalPostTemplateChoice.threadReel,
                enabled: enabled,
                onTap: () => onChanged(FinalPostTemplateChoice.threadReel),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final String label;
  final _Kind kind;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _Tile({
    required this.label,
    required this.kind,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final panel = AppTheme.feedPanel(brightness);
    final ink = AppTheme.feedPanelInk(brightness);
    final muted = AppTheme.feedMutedText(brightness);
    return Material(
      color: panel,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.all(selected ? 9 : 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? AppTheme.accent
                  : muted.withValues(alpha: 0.2),
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              SizedBox(
                height: 52,
                width: double.infinity,
                child: CustomPaint(
                  painter: _DiagramPainter(kind: kind, brightness: brightness),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: ink,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Kind { postcard, map, threads }

class _DiagramPainter extends CustomPainter {
  final _Kind kind;
  final Brightness brightness;

  _DiagramPainter({required this.kind, required this.brightness});

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = brightness == Brightness.dark
          ? AppTheme.darkCard
          : Colors.white;
    final stroke = Paint()
      ..color = AppTheme.feedMutedText(brightness).withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final mapFill = Paint()..color = AppTheme.feedMapWash(brightness).first;

    RRect box(double l, double t, double r, double b) =>
        RRect.fromLTRBR(l, t, r, b, const Radius.circular(3));

    void drawBox(RRect r, {Paint? paint}) {
      canvas.drawRRect(r, paint ?? fill);
      canvas.drawRRect(r, stroke);
    }

    switch (kind) {
      case _Kind.postcard:
        drawBox(box(size.width * 0.08, size.height * 0.08, size.width * 0.92,
            size.height * 0.56));
        drawBox(box(size.width * 0.08, size.height * 0.64, size.width * 0.8,
            size.height * 0.72));
        drawBox(box(size.width * 0.08, size.height * 0.78, size.width * 0.65,
            size.height * 0.86));
        break;
      case _Kind.map:
        drawBox(
          box(size.width * 0.06, size.height * 0.06, size.width * 0.94,
              size.height * 0.64),
          paint: mapFill,
        );
        final stripTop = size.height * 0.74;
        final stripH = size.height * 0.18;
        const gap = 2.0;
        final w = (size.width * 0.88 - gap * 2) / 3;
        for (var i = 0; i < 3; i++) {
          final left = size.width * 0.06 + i * (w + gap);
          drawBox(box(left, stripTop, left + w, stripTop + stripH));
        }
        break;
      case _Kind.threads:
        drawBox(box(size.width * 0.06, size.height * 0.1, size.width * 0.44,
            size.height * 0.9));
        drawBox(box(size.width * 0.5, size.height * 0.12, size.width * 0.94,
            size.height * 0.4));
        drawBox(box(size.width * 0.5, size.height * 0.48, size.width * 0.94,
            size.height * 0.76));
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _DiagramPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.brightness != brightness;
}
