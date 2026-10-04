import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tripthread/utils/app_theme.dart';

/// Reusable TripThread logo widget that renders the branded SVG icon.
///
/// Use [size] to control the icon dimensions.
/// Set [showText] to display the "TripThread" wordmark beside the icon.
/// Set [useDarkVariant] when placing the logo on a dark background.
class TripThreadLogo extends StatelessWidget {
  final double size;
  final bool showText;
  final bool useDarkVariant;

  const TripThreadLogo({
    super.key,
    this.size = 64,
    this.showText = false,
    this.useDarkVariant = false,
  });

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: useDarkVariant ? AppTheme.darkText : AppTheme.ink,
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      padding: EdgeInsets.all(size * 0.18),
      child: SvgPicture.asset(
        'assets/images/tripthread-icon-mono.svg',
        colorFilter: ColorFilter.mode(
          useDarkVariant ? AppTheme.darkBackground : Colors.white,
          BlendMode.srcIn,
        ),
      ),
    );

    if (!showText) return mark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 10),
        Text(
          'TripThread',
          style: GoogleFonts.playfairDisplay(
            fontSize: size * 0.42,
            fontWeight: FontWeight.w600,
            color: useDarkVariant ? AppTheme.darkText : AppTheme.ink,
          ),
        ),
      ],
    );
  }
}
