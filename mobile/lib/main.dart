import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:another_flushbar/flushbar.dart';
import 'package:tripthread/config/app_config.dart';
import 'package:tripthread/models/place.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/providers/place_provider.dart';
import 'package:tripthread/providers/user_provider.dart';
import 'package:tripthread/providers/trip_provider.dart';
import 'package:tripthread/providers/feed_provider.dart';
import 'package:tripthread/screens/trip/trip_map_screen.dart';
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
import 'package:tripthread/screens/auth/reset_password_success_screen.dart';
import 'package:tripthread/screens/home/home_screen.dart';
import 'package:tripthread/screens/profile/profile_screen.dart';
import 'package:tripthread/screens/profile/edit_profile_screen.dart';
import 'package:tripthread/screens/trip/create_trip_screen.dart';
import 'package:tripthread/screens/trip/trip_detail_screen.dart';
import 'package:tripthread/screens/trip/trip_thread_screen.dart';
import 'package:tripthread/screens/trip/trip_participants_screen.dart';
import 'package:tripthread/screens/profile/follow_requests_screen.dart';
import 'package:tripthread/screens/profile/trip_invitations_screen.dart';
import 'package:tripthread/screens/settings/settings_screen.dart';
import 'package:tripthread/utils/app_theme.dart';
import 'package:tripthread/utils/error_handler.dart';
import 'package:tripthread/widgets/auth_gate.dart';

void main() async {
  debugPrint('[main] Starting TripThread app initialization');
  WidgetsFlutterBinding.ensureInitialized();

  try {
    debugPrint('[main] Initializing environment configuration');
    await AppConfig.initialize();
    debugPrint('[main] Environment configuration initialized');

    debugPrint('[main] Initializing services');

    // Initialize services
    debugPrint('[main] Creating StorageService');
    final storageService = StorageService();
    debugPrint('[main] Initializing StorageService');
    try {
      await storageService.init();
      debugPrint('[main] StorageService initialized');
    } catch (e) {
      debugPrint('[main] StorageService initialization failed: $e');
      throw e;
    }

    debugPrint('[main] Creating ConnectivityService');
    final connectivityService = ConnectivityService();
    debugPrint('[main] Initializing ConnectivityService');
    try {
      await connectivityService.initialize();
      debugPrint('[main] ConnectivityService initialized');
    } catch (e) {
      debugPrint('[main] ConnectivityService initialization failed: $e');
      throw e;
    }

    debugPrint('[main] Creating core services');
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
              final authProvider = AuthProvider(
                apiService: apiService,
                storageService: storageService,
              );
              // Set up the unauthorized callback to trigger logout
              apiService.setUnauthorizedCallback(() {
                debugPrint(
                    '[main] Unauthorized callback triggered - forcing logout');
                authProvider.forceLogout(
                    message: 'Session expired. Please log in again.');
              });
              return authProvider;
            },
          ),
          ChangeNotifierProvider<UserProvider>(
            create: (context) {
              debugPrint('[main] Creating UserProvider');
              final authProvider = context.read<AuthProvider>();
              final userProvider = UserProvider(apiService: apiService);
              // Listen to auth changes and clear UserProvider cache on logout
              authProvider.addListener(() {
                if (!authProvider.isAuthenticated) {
                  userProvider.clearCache();
                }
              });
              return userProvider;
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
          ChangeNotifierProvider<PlaceProvider>(create: (context) {
            debugPrint('[main] Creating PlaceProvider');
            return PlaceProvider(apiService: apiService);
          })
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

class TripThreadAppRouter extends StatefulWidget {
  TripThreadAppRouter({Key? key}) : super(key: key);

  static String? _lastLocation;

  @override
  State<TripThreadAppRouter> createState() => _TripThreadAppRouterState();
}

class ConnectivityToastHandler extends StatefulWidget {
  const ConnectivityToastHandler({super.key});

  @override
  State<ConnectivityToastHandler> createState() =>
      _ConnectivityToastHandlerState();
}

class _ConnectivityToastHandlerState extends State<ConnectivityToastHandler> {
  Flushbar? _flushbar;
  bool _wasConnected = true;

  @override
  Widget build(BuildContext context) {
    final connectivity = context.watch<ConnectivityService>();

    // Use a post-frame callback to safely show/hide the flushbar
    // after the build cycle is complete.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // Condition to show: network status changed from connected to disconnected
      if (_wasConnected && !connectivity.isConnected) {
        _flushbar?.dismiss(); // Dismiss any existing one first
        _flushbar = _createOfflineToast();
        _flushbar?.show(context);
      }
      // Condition to hide: network status changed from disconnected to connected
      else if (!_wasConnected && connectivity.isConnected) {
        _flushbar?.dismiss();
        _flushbar = null;
      }
    });

    // Update the state for the next rebuild
    _wasConnected = connectivity.isConnected;

    // This widget is purely for logic and doesn't render anything
    return const SizedBox.shrink();
  }

  Flushbar _createOfflineToast() {
    return Flushbar(
      title: 'No Internet Connection',
      message: 'You are offline. Some features may not be available.',
      icon: const Icon(
        Icons.wifi_off_rounded,
        size: 28.0,
        color: Colors.white,
      ),
      backgroundColor: Colors.red.shade700,
      // The toast will disappear after 8 seconds.
      // For a persistent toast that only disappears when connection is back
      // or when the user dismisses it, set `duration: null`.
      duration: const Duration(seconds: 8),
      isDismissible: true, // Allows the user to swipe it away
      flushbarPosition: FlushbarPosition.TOP,
      margin: const EdgeInsets.fromLTRB(8, kToolbarHeight + 8, 8, 0),
      borderRadius: BorderRadius.circular(8),
      onStatusChanged: (status) {
        // When dismissed, nullify the reference so a new one can be created
        if (status == FlushbarStatus.DISMISSED) {
          _flushbar = null;
        }
      },
    );
  }

  @override
  void dispose() {
    _flushbar?.dismiss();
    super.dispose();
  }
}

class _TripThreadAppRouterState extends State<TripThreadAppRouter> {
  GoRouter? _router;
  AuthProvider? _lastAuthProvider;
  DeepLinkService? _deepLinkService;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final deepLinkService =
        Provider.of<DeepLinkService>(context, listen: false);

    // Create or recreate router only when the AuthProvider instance changes
    if (_router == null || authProvider != _lastAuthProvider) {
      _lastAuthProvider = authProvider;
      _deepLinkService = deepLinkService;

      _router = GoRouter(
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
        refreshListenable: Listenable.merge([
          authProvider,
          authProvider.routingNotifier,
          authProvider.uiNotifier
        ]),
        redirect: (context, state) {
          final authProvider =
              Provider.of<AuthProvider>(context, listen: false);
          final isLoading = authProvider.isLoading;
          final isLoggedIn = authProvider.isAuthenticated;
          final location = state.uri.toString();

          if (location != TripThreadAppRouter._lastLocation) {
            print('[GoRouter] location changed to: $location');
            print('[GoRouter] isLoading: $isLoading, isLoggedIn: $isLoggedIn');
            TripThreadAppRouter._lastLocation = location;
          }

          // Don't redirect while loading
          if (isLoading) {
            print('[GoRouter] Still loading, no redirect');
            return null;
          }

          // Redirect to login if not authenticated and not on auth pages
          if (!isLoggedIn &&
              location != '/login' &&
              location != '/signup' &&
              location != '/forgot-password' &&
              !location.startsWith('/reset-password')) {
            print('[GoRouter] Not logged in, redirecting to /login');
            return '/login';
          }

          // Redirect to home if authenticated and on auth pages
          if (isLoggedIn &&
              (location == '/login' ||
                  location == '/signup' ||
                  location == '/forgot-password' ||
                  location.startsWith('/reset-password'))) {
            print('[GoRouter] Already logged in, redirecting to /home');
            return '/home';
          }

          print('[GoRouter] No redirect needed');
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
            path: '/reset-success',
            builder: (context, state) => const ResetPasswordSuccessScreen(),
          ),
          GoRoute(
            path: '/home',
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
              path: '/trips',
              builder: (context, state) => const HomeScreen(initialTab: 1)),
          GoRoute(
            path: '/profile/:userId',
            builder: (context, state) {
              final userId = state.pathParameters['userId']!;
              return ProfileScreen(userId: userId);
            },
          ),
          GoRoute(
              path: '/edit-profile',
              builder: (context, state) => const EditProfileScreen()),
          GoRoute(
              path: '/create-trip',
              builder: (context, state) => const CreateTripScreen()),
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
          GoRoute(
            path: '/trip/:tripId/map',
            builder: (context, state) {
              final tripId = state.pathParameters['tripId']!;
              final extra = state.extra as Map<String, dynamic>?;
              final tripTitle = extra?['tripTitle'] as String? ?? 'Trip Map';
              final places = extra?['places'] as List<MapPlace>?;

              return TripMapScreen(
                tripId: tripId,
                tripTitle: tripTitle,
                initialPlaces: places,
              );
            },
          ),
          GoRoute(
            path: '/trip/:tripId/participants',
            builder: (context, state) {
              final tripId = state.pathParameters['tripId']!;
              return TripParticipantsScreen(tripId: tripId);
            },
          ),
          GoRoute(
            path: '/follow-requests',
            builder: (context, state) {
              debugPrint('[Router] Navigating to FollowRequestsScreen');
              return const FollowRequestsScreen();
            },
          ),
          GoRoute(
            path: '/trip-invites',
            builder: (context, state) {
              debugPrint('[Router] Navigating to TripInvitationsScreen');
              return const TripInvitationsScreen();
            },
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      );

      // Initialize deep linking after router is created
      deepLinkService.setRouter(_router!);
      deepLinkService.initialize();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use the existing router instance; it must be non-null after didChangeDependencies
    final router = _router!;
    _deepLinkService?.setRouter(router);
    _deepLinkService?.initialize();

    return MaterialApp.router(
      title: 'TripThread',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return Stack(
          children: [
            AuthGate(child: child ?? const SizedBox.shrink()),
            // Splash overlay listens only to routingNotifier to avoid heavy rebuilds
            AnimatedBuilder(
              animation: context.watch<AuthProvider>().routingNotifier,
              builder: (context, _) {
                if (!context.read<AuthProvider>().isLoading)
                  return const SizedBox.shrink();
                debugPrint('Rendering SplashScreen');
                return const IgnorePointer(
                  ignoring: false,
                  child: SplashScreen(),
                );
              },
            ),
            // Offline banner
            // if (!connectivity.isConnected)
            //   Positioned(
            //     top: MediaQuery.of(context).padding.top,
            //     left: 0,
            //     right: 0,
            //     child: Container(
            //       padding: const EdgeInsets.all(8),
            //       color: Colors.red,
            //       child: const Text(
            //         'No internet connection',
            //         textAlign: TextAlign.center,
            //         style: TextStyle(color: Colors.white),
            //       ),
            //     ),
            //   ),
            // NEW: intelligent toast handler
            const ConnectivityToastHandler(),
          ],
        );
      },
    );
  }
}
