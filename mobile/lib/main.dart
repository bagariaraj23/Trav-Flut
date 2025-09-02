import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/providers/user_provider.dart';
import 'package:tripthread/providers/trip_provider.dart';
import 'package:tripthread/providers/feed_provider.dart';
import 'package:tripthread/services/api_service.dart';
import 'package:tripthread/services/storage_service.dart';
import 'package:tripthread/services/trip_service.dart';
import 'package:tripthread/services/connectivity_service.dart';
import 'package:tripthread/services/media_service.dart';
import 'package:tripthread/services/deep_link_service.dart';
import 'package:tripthread/screens/splash_screen.dart';
import 'package:tripthread/screens/auth/login_screen.dart';
import 'package:tripthread/screens/auth/signup_screen.dart';
import 'package:tripthread/screens/auth/forgot_password_screen.dart';
import 'package:tripthread/screens/auth/reset_password_screen.dart';
import 'package:tripthread/screens/home/home_screen.dart';
import 'package:tripthread/screens/profile/profile_screen.dart';
import 'package:tripthread/screens/profile/edit_profile_screen.dart';
import 'package:tripthread/screens/trip/create_trip_screen.dart';
import 'package:tripthread/screens/trip/trip_detail_screen.dart';
import 'package:tripthread/screens/trip/trip_thread_screen.dart';
import 'package:tripthread/screens/profile/follow_requests_screen.dart';
import 'package:tripthread/utils/app_theme.dart';
import 'package:tripthread/utils/error_handler.dart';

void main() async {
  debugPrint('[main] Starting TripThread app initialization');
  WidgetsFlutterBinding.ensureInitialized();

  try {
    debugPrint('[main] Initializing services');

    // Initialize services
    final storageService = StorageService();
    await storageService.init();
    debugPrint('[main] StorageService initialized');

    final connectivityService = ConnectivityService();
    await connectivityService.initialize();
    debugPrint('[main] ConnectivityService initialized');

    final apiService = ApiService();
    final tripService = TripService();
    final mediaService = MediaService();
    final deepLinkService = DeepLinkService();
    debugPrint('[main] Core services created');

    debugPrint('[main] Setting up providers');
    runApp(
      MultiProvider(
        providers: [
          Provider<StorageService>.value(value: storageService),
          Provider<ApiService>.value(value: apiService),
          Provider<TripService>.value(value: tripService),
          Provider<MediaService>.value(value: mediaService),
          Provider<DeepLinkService>.value(value: deepLinkService),
          ChangeNotifierProvider<ConnectivityService>.value(
              value: connectivityService),
          ChangeNotifierProvider<AuthProvider>(
            create: (context) {
              debugPrint('[main] Creating AuthProvider');
              return AuthProvider(
                apiService: apiService,
                storageService: storageService,
              );
            },
          ),
          ChangeNotifierProvider<UserProvider>(
            create: (context) {
              debugPrint('[main] Creating UserProvider');
              return UserProvider(apiService: apiService);
            },
          ),
          ChangeNotifierProvider<TripProvider>(
            create: (context) {
              debugPrint('[main] Creating TripProvider');
              final provider = TripProvider(tripService: tripService);
              tripService.setStorageService(storageService);
              return provider;
            },
          ),
          ChangeNotifierProvider<FeedProvider>(
            create: (context) {
              debugPrint('[main] Creating FeedProvider');
              return FeedProvider(apiService: apiService);
            },
          ),
        ],
        child: TripThreadAppRouter(),
      ),
    );
    debugPrint('[main] App started successfully');
  } catch (error) {
    debugPrint('[main] App initialization failed: $error');
    ErrorHandler.logError(error, context: 'App initialization');

    // Show error screen or fallback
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text('Failed to initialize app'),
              const SizedBox(height: 8),
              Text(error.toString()),
            ],
          ),
        ),
      ),
    ));
  }
}

class TripThreadAppRouter extends StatelessWidget {
  TripThreadAppRouter({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        final router = _createRouter(authProvider);
        
        // Set up deep link service with router
        final deepLinkService = Provider.of<DeepLinkService>(context, listen: false);
        deepLinkService.setRouter(router);
        deepLinkService.initialize();
        
        return MaterialApp.router(
          title: 'TripThread',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.system,
          routerConfig: router,
          debugShowCheckedModeBanner: false,
          builder: (context, child) {
            final authProvider = context.watch<AuthProvider>();
            final connectivity = context.watch<ConnectivityService>();
            return Stack(
              children: [
                child ?? const SizedBox.shrink(),
                // Splash overlay listens only to routingNotifier to avoid heavy rebuilds
                AnimatedBuilder(
                  animation: authProvider.routingNotifier,
                  builder: (context, _) {
                    if (!authProvider.isLoading) return const SizedBox.shrink();
                    debugPrint('Rendering SplashScreen');
                    return const IgnorePointer(
                      ignoring: false,
                      child: SplashScreen(),
                    );
                  },
                ),
                // Offline banner
                if (!connectivity.isConnected)
                  Positioned(
                    top: MediaQuery.of(context).padding.top,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      color: Colors.red,
                      child: const Text(
                        'No internet connection',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  static String? _lastLocation;

  GoRouter _createRouter(AuthProvider authProvider) {
    final router = GoRouter(
      initialLocation: '/login',
      errorBuilder: (context, state) => Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text('Page not found'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.go('/home'),
                child: const Text('Go Home'),
              ),
            ],
          ),
        ),
      ),
      refreshListenable: authProvider.routingNotifier,
      redirect: (context, state) {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final isLoading = authProvider.isLoading;
        final isLoggedIn = authProvider.isAuthenticated;
        final location = state.uri.toString();

        if (location != _lastLocation) {
          print('[GoRouter] location changed to: $location');
          _lastLocation = location;
        }

        if (isLoading) return null;

        if (!isLoggedIn && location != '/login' && location != '/signup' && location != '/forgot-password' && !location.startsWith('/reset-password')) {
          return '/login';
        }

        if (isLoggedIn && (location == '/login' || location == '/signup' || location == '/forgot-password' || location.startsWith('/reset-password'))) {
          return '/home';
        }

        return null;
      },
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: '/signup',
          builder: (context, state) => const SignupScreen(),
        ),
        GoRoute(
          path: '/forgot-password',
          builder: (context, state) => const ForgotPasswordScreen(),
        ),
        GoRoute(
          path: '/reset-password',
          builder: (context, state) {
            final token = state.uri.queryParameters['t'];
            return ResetPasswordScreen(token: token);
          },
        ),
        GoRoute(
          path: '/home',
          builder: (context, state) => const HomeScreen(),
        ),
        GoRoute(
          path: '/trips',
          builder: (context, state) => const HomeScreen(initialTab: 1),
        ),
        GoRoute(
          path: '/profile/:userId',
          builder: (context, state) {
            final userId = state.pathParameters['userId']!;
            return ProfileScreen(userId: userId);
          },
        ),
        GoRoute(
          path: '/edit-profile',
          builder: (context, state) => const EditProfileScreen(),
        ),
        GoRoute(
          path: '/create-trip',
          builder: (context, state) => const CreateTripScreen(),
        ),
        GoRoute(
          path: '/trip/:tripId',
          builder: (context, state) {
            final tripId = state.pathParameters['tripId']!;
            return TripDetailScreen(tripId: tripId);
          },
        ),
        GoRoute(
          path: '/trip/:tripId/thread',
          builder: (context, state) {
            final tripId = state.pathParameters['tripId']!;
            return TripThreadScreen(tripId: tripId);
          },
        ),
        // GoRoute(
        //   path: '/trip/:tripId/participants',
        //   builder: (context, state) {
        //     final tripId = state.pathParameters['tripId']!;
        //     return TripParticipantsScreen(tripId: tripId);
        //   },
        // ),        
        GoRoute(
          path: '/follow-requests',
          builder: (context, state) {
            debugPrint('[Router] Navigating to FollowRequestsScreen');
            return const FollowRequestsScreen();
          },
        ),
      ],
    );

    return router;
  }
}