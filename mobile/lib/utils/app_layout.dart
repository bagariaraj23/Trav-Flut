import 'package:flutter/material.dart';

/// Width constraints shared by reading screens so tablets and landscape
/// do not stretch lines edge to edge.
class AppLayout {
  static const double wideBreakpoint = 600;
  static const double readingMaxWidth = 720;

  /// Vertical spacing for auth screens; shrinks on short phones (e.g. RMX3461).
  static AuthSpacing authSpacing(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    final short = h < 780;
    final compact = h < 700;
    return AuthSpacing(
      top: compact ? 12 : (short ? 20 : 40),
      logo: compact ? 48 : (short ? 56 : 64),
      afterLogo: compact ? 12 : (short ? 16 : 24),
      beforeFields: compact ? 20 : (short ? 28 : 40),
      section: compact ? 12 : (short ? 16 : 24),
      bottom: compact ? 16 : 24,
      pagePadding: compact ? 16 : 24,
    );
  }

  static bool isWide(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.shortestSide >= wideBreakpoint ||
        (size.width > size.height && size.width >= wideBreakpoint);
  }

  static bool showThreadRail(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= 360;
  }

  static Widget reading({
    required BuildContext context,
    required Widget child,
    EdgeInsetsGeometry? padding,
  }) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isWide(context) ? readingMaxWidth : double.infinity,
        ),
        child: padding == null
            ? child
            : Padding(padding: padding, child: child),
      ),
    );
  }
}

class AuthSpacing {
  final double top;
  final double logo;
  final double afterLogo;
  final double beforeFields;
  final double section;
  final double bottom;
  final double pagePadding;

  const AuthSpacing({
    required this.top,
    required this.logo,
    required this.afterLogo,
    required this.beforeFields,
    required this.section,
    required this.bottom,
    required this.pagePadding,
  });
}
