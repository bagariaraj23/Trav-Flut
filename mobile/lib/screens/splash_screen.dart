import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:tripthread/utils/app_theme.dart';
import 'package:tripthread/widgets/tripthread_logo.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppTheme.darkBackground
          : AppTheme.ink,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // App Logo
            const TripThreadLogo(size: 80, useDarkVariant: true),

            const SizedBox(height: 24),

            // App Name
            Text(
              'TripThread',
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                color: AppTheme.cream,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            // Tagline
            Text(
              'Capture journeys. Share stories.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: AppTheme.cream.withValues(alpha: 0.8),
              ),
            ),

            const SizedBox(height: 48),

            // Loading Indicator (fixed overflow)
            const SizedBox(
              width: 60, // enough horizontal space for the three dots
              height: 24,
              child: SpinKitThreeBounce(color: AppTheme.accent, size: 16),
            ),
          ],
        ),
      ),
    );
  }
}
