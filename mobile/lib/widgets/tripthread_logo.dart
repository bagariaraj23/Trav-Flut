import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Reusable TripThread logo widget that renders the branded SVG icon.
///
/// Use [size] to control the icon dimensions.
/// Set [showText] to display the "TripThread" wordmark beside the icon.
/// Set [useDarkVariant] when placing the logo on a dark background
/// (uses the white-on-gradient icon variant).
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
    if (showText) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            'assets/images/tripthread-icon.svg',
            width: size,
            height: size,
          ),
          const SizedBox(width: 10),
          RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: size * 0.5,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
              children: [
                TextSpan(
                  text: 'Trip',
                  style: TextStyle(
                    color: useDarkVariant
                        ? Colors.white
                        : const Color(0xFF1E293B),
                  ),
                ),
                const TextSpan(
                  text: 'Thread',
                  style: TextStyle(color: Color(0xFF0EA5E9)),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Icon-only mode: use the app icon (gradient bg + white icon) on dark.
    if (useDarkVariant) {
      return SvgPicture.asset(
        'assets/images/tripthread-icon.svg',
        width: size,
        height: size,
      );
    }

    // Light mode — Container with gradient background + white SVG on top
    // to match the app icon style.
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.25),
        gradient: const LinearGradient(
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
          colors: [
            Color(0xFF0284C7), // sky-700
            Color(0xFF0D9488), // teal-600
            Color(0xFF14B8A6), // teal-500
          ],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(size * 0.15),
        child: SvgPicture.asset(
          'assets/images/tripthread-icon-mono.svg',
          colorFilter: const ColorFilter.mode(
            Colors.white,
            BlendMode.srcIn,
          ),
        ),
      ),
    );
  }
}
