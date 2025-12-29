import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // App Logo
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.travel_explore,
                size: 40,
                color: Color(0xFF6366F1),
              ),
            ),

            const SizedBox(height: 24),

            // App Name
            Text(
              'TripThread',
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            // Tagline
            Text(
              'Document your journey',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),

            const SizedBox(height: 48),

            // Loading Indicator (fixed overflow)
            const SizedBox(
              width: 60, // enough horizontal space for the three dots
              height: 24,
              child: SpinKitThreeBounce(color: Colors.white, size: 16),
            ),
          ],
        ),
      ),
    );
  }
}
