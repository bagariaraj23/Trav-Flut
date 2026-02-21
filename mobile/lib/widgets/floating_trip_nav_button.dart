import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:tripthread/providers/trip_provider.dart';

/// Persists bubble position across screen navigations.
Offset? _savedBubblePosition;

/// A floating bubble button when user has an ongoing trip.
/// Draggable anywhere on screen; tap to navigate Home <-> Thread.
class FloatingTripNavButton extends StatefulWidget {
  const FloatingTripNavButton({super.key});

  /// Resets the persisted bubble position (call on logout/clear data).
  static void resetPosition() {
    _savedBubblePosition = null;
  }

  @override
  State<FloatingTripNavButton> createState() => _FloatingTripNavButtonState();
}

class _FloatingTripNavButtonState extends State<FloatingTripNavButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  Offset? _position;
  Offset? _currentDragPosition;

  static const double _buttonSize = 48.0;
  static const double _dragSpeedMultiplier = 1.0;

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

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _updateVisibility(hasOngoingTrip && currentTrip != null);
        });

        if (!hasOngoingTrip || currentTrip == null) {
          return const SizedBox.shrink();
        }

        final router = GoRouter.of(context);
        final location = router.routerDelegate.currentConfiguration.uri.toString();
        final isOnThreadScreen =
            location.contains('/trip/') && location.contains('/thread');

        // Use Align so we don't use Positioned (valid only as direct Stack child).
        return LayoutBuilder(
          builder: (context, constraints) {
            final mediaQuery = MediaQuery.of(context);
            final theme = Theme.of(context);
            final topSpacing =
                mediaQuery.padding.top + (theme.useMaterial3 ? 8.0 : 12.0);
            final maxTop = constraints.maxHeight -
                _buttonSize -
                mediaQuery.padding.bottom;
            final maxLeft = constraints.maxWidth - _buttonSize;

            final defaultPos = Offset(
              (constraints.maxWidth - _buttonSize) / 2,
              topSpacing,
            );
            final pos = _position ?? _savedBubblePosition ?? defaultPos;
            final clampedPos = Offset(
              pos.dx.clamp(0.0, maxLeft),
              pos.dy.clamp(topSpacing, maxTop),
            );

            // Alignment: -1,-1 = top-left, 1,1 = bottom-right
            final alignX = constraints.maxWidth > 0
                ? 2.0 * (clampedPos.dx + _buttonSize / 2) / constraints.maxWidth - 1.0
                : 0.0;
            final alignY = constraints.maxHeight > 0
                ? 2.0 * (clampedPos.dy + _buttonSize / 2) / constraints.maxHeight - 1.0
                : 0.0;

            return Align(
              alignment: Alignment(alignX.clamp(-1.0, 1.0), alignY.clamp(-1.0, 1.0)),
              child: GestureDetector(
                onPanStart: (_) {
                  _currentDragPosition = clampedPos;
                  _position = clampedPos;
                },
                onPanUpdate: (details) {
                  if (_currentDragPosition != null) {
                    setState(() {
                      final d = _dragSpeedMultiplier;
                      _position = Offset(
                        (_currentDragPosition!.dx + details.delta.dx * d)
                            .clamp(0.0, maxLeft),
                        (_currentDragPosition!.dy + details.delta.dy * d)
                            .clamp(topSpacing, maxTop),
                      );
                      _currentDragPosition = _position;
                    });
                  }
                },
                onPanEnd: (_) {
                  _savedBubblePosition = _position ?? clampedPos;
                },
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: _buildButtonContent(
                      context,
                      isOnThreadScreen,
                      currentTrip!.id,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildButtonContent(
    BuildContext context,
    bool isOnThreadScreen,
    String tripId,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final iconSize = _buttonSize * 0.5;
    final borderRadius = _buttonSize / 2;

    final IconData icon;
    final String targetRoute;
    final String semanticLabel;

    if (isOnThreadScreen) {
      icon = Icons.home_rounded;
      targetRoute = '/home';
      semanticLabel = 'Go to home. Drag to move.';
    } else {
      icon = Icons.timeline_rounded;
      targetRoute = '/trip/$tripId/thread';
      semanticLabel = 'Go to trip thread. Drag to move.';
    }

    final shadowOpacity =
        theme.brightness == Brightness.dark ? 0.4 : 0.15;
    final shadowBlur = theme.brightness == Brightness.dark ? 16.0 : 12.0;
    final shadowOffset = theme.brightness == Brightness.dark ? 6.0 : 4.0;

    return Semantics(
      label: semanticLabel,
      button: true,
      hint: 'Tap to navigate, drag to move',
      child: Material(
        color: Colors.transparent,
        elevation: 0,
        child: InkWell(
          onTap: () {
            if (Theme.of(context).platform == TargetPlatform.iOS ||
                Theme.of(context).platform == TargetPlatform.android) {
              HapticFeedback.lightImpact();
            }
            context.go(
              targetRoute,
              extra: targetRoute == '/home' ? {'explicitHome': true} : null,
            );
          },
          borderRadius: BorderRadius.circular(borderRadius),
          child: Container(
            width: _buttonSize,
            height: _buttonSize,
            decoration: BoxDecoration(
              color: colorScheme.primary,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: shadowOpacity),
                  blurRadius: shadowBlur,
                  offset: Offset(0, shadowOffset),
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Icon(icon, color: colorScheme.onPrimary, size: iconSize),
          ),
        ),
      ),
    );
  }
}
