import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:tripthread/providers/trip_provider.dart';

/// A floating bubble button that appears at the top center of the screen
/// when a user has an ongoing trip. Allows quick navigation between
/// the trip thread entry screen and home feed.
///
/// Features:
/// - Fully responsive sizing based on screen density
/// - Theme-aware colors for light/dark mode
/// - Proper safe area handling for all devices
/// - Smooth animations with Material 3 design
class FloatingTripNavButton extends StatefulWidget {
  const FloatingTripNavButton({super.key});

  @override
  State<FloatingTripNavButton> createState() => _FloatingTripNavButtonState();
}

class _FloatingTripNavButtonState extends State<FloatingTripNavButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _updateVisibility(bool shouldShow) {
    if (shouldShow) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TripProvider>(
      builder: (context, tripProvider, child) {
        final hasOngoingTrip = tripProvider.hasOngoingTrip;
        final currentTrip = tripProvider.currentTrip;

        // Update animation based on visibility
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _updateVisibility(hasOngoingTrip && currentTrip != null);
          }
        });

        if (!hasOngoingTrip || currentTrip == null) {
          return const SizedBox.shrink();
        }

        // Get current route to determine which icon to show
        final router = GoRouter.of(context);
        final currentLocation = router.routerDelegate.currentConfiguration.uri
            .toString();
        final isOnThreadScreen =
            currentLocation.contains('/trip/') &&
            currentLocation.contains('/thread');

        return FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: _buildButton(context, isOnThreadScreen, currentTrip.id),
          ),
        );
      },
    );
  }

  Widget _buildButton(
    BuildContext context,
    bool isOnThreadScreen,
    String tripId,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mediaQuery = MediaQuery.of(context);

    // Dynamic sizing based on screen density and device type
    // Base size follows Material Design touch target guidelines (48dp minimum)
    // Scale based on device pixel ratio for better appearance on high-DPI screens
    final double baseSize = 48.0;
    final double pixelRatio = mediaQuery.devicePixelRatio;
    final double sizeMultiplier = pixelRatio > 2.0
        ? 1.1
        : 1.0; // Slightly larger on high-DPI
    final double buttonSize = baseSize * sizeMultiplier;

    // Icon size scales proportionally (typically 60% of button size)
    final double iconSize = buttonSize * 0.5;

    // Dynamic spacing from top - accounts for safe area and provides consistent spacing
    // Uses theme spacing units for consistency
    final double topSpacing =
        mediaQuery.padding.top +
        (theme.useMaterial3 ? 8.0 : 12.0); // Material 3 uses tighter spacing

    // Border radius for circular button (half of size)
    final double borderRadius = buttonSize / 2;

    // Determine icon and navigation target
    final IconData icon;
    final String targetRoute;
    final String semanticLabel;

    if (isOnThreadScreen) {
      // On thread screen, show home icon to navigate to home
      icon = Icons.home_rounded;
      targetRoute = '/home';
      semanticLabel = 'Navigate to home feed';
    } else {
      // On home or other screens, show thread icon to navigate to thread
      icon = Icons.timeline_rounded;
      targetRoute = '/trip/$tripId/thread';
      semanticLabel = 'Navigate to trip thread entries';
    }

    // Theme-aware colors using Material 3 color scheme
    // Use primary color with proper opacity for better visibility
    final Color buttonColor = colorScheme.primary;
    final Color iconColor = colorScheme.onPrimary;

    // Dynamic shadow based on theme brightness
    // Dark mode needs stronger shadow, light mode needs subtle shadow
    final double shadowOpacity = theme.brightness == Brightness.dark
        ? 0.4
        : 0.15;
    final double shadowBlur = theme.brightness == Brightness.dark ? 16.0 : 12.0;
    final double shadowOffset = theme.brightness == Brightness.dark ? 6.0 : 4.0;

    return Positioned(
      top: topSpacing,
      left: 0,
      right: 0,
      child: Center(
        child: Semantics(
          label: semanticLabel,
          button: true,
          hint: 'Double tap to navigate',
          child: Material(
            color: Colors.transparent,
            elevation: 0, // We use custom shadow instead
            child: InkWell(
              onTap: () {
                // Haptic feedback for better UX on supported platforms
                if (Theme.of(context).platform == TargetPlatform.iOS ||
                    Theme.of(context).platform == TargetPlatform.android) {
                  HapticFeedback.lightImpact();
                }
                context.go(targetRoute);
              },
              borderRadius: BorderRadius.circular(borderRadius),
              child: Container(
                width: buttonSize,
                height: buttonSize,
                decoration: BoxDecoration(
                  color: buttonColor,
                  shape: BoxShape.circle,
                  // Material 3 elevation shadow
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: shadowOpacity),
                      blurRadius: shadowBlur,
                      offset: Offset(0, shadowOffset),
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: Icon(icon, color: iconColor, size: iconSize),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
