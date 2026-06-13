import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:another_flushbar/flushbar.dart';
import 'package:tripthread/config/app_config.dart';
import 'package:tripthread/models/place.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/providers/place_provider.dart';
import 'package:tripthread/providers/final_post_provider.dart';
import 'package:tripthread/providers/user_provider.dart';
import 'package:tripthread/providers/trip_provider.dart';
import 'package:tripthread/providers/feed_provider.dart';
import 'package:tripthread/providers/engagement_provider.dart';
import 'package:tripthread/providers/comment_provider.dart';
import 'package:tripthread/providers/share_provider.dart';
import 'package:tripthread/services/like_service.dart';
import 'package:tripthread/services/comment_service.dart';
import 'package:tripthread/services/share_service.dart';
import 'package:tripthread/screens/trip/trip_map_screen.dart';
import 'package:tripthread/services/api_service.dart';
import 'package:tripthread/services/storage_service.dart';
import 'package:tripthread/services/metadata_cache_service.dart';
import 'package:tripthread/services/trip_service.dart';
import 'package:tripthread/services/connectivity_service.dart';
import 'package:tripthread/services/media_service.dart';
import 'package:tripthread/services/deep_link_service.dart';
import 'package:tripthread/services/google_sign_in_service.dart';
import 'package:tripthread/screens/splash_screen.dart';
import 'package:tripthread/screens/auth/login_screen.dart';
import 'package:tripthread/screens/auth/signup_screen.dart';
import 'package:tripthread/screens/auth/forgot_password_screen.dart';
import 'package:tripthread/screens/auth/reset_password_screen.dart';
import 'package:tripthread/screens/auth/reset_password_success_screen.dart';
import 'package:tripthread/screens/auth/complete_profile_screen.dart';
import 'package:tripthread/screens/home/home_screen.dart';
import 'package:tripthread/screens/profile/profile_screen.dart';
import 'package:tripthread/screens/profile/edit_profile_screen.dart';
import 'package:tripthread/screens/profile/followers_following_screen.dart';
import 'package:tripthread/screens/trip/create_trip_screen.dart';
import 'package:tripthread/screens/trip/trip_detail_screen.dart';
import 'package:tripthread/screens/trip/trip_thread_screen.dart';
import 'package:tripthread/screens/trip/trip_participants_screen.dart';
import 'package:tripthread/screens/trip/final_post_edit_screen.dart';
import 'package:tripthread/screens/profile/follow_requests_screen.dart';
import 'package:tripthread/screens/profile/trip_invitations_screen.dart';
import 'package:tripthread/screens/settings/settings_screen.dart';
import 'package:tripthread/screens/engagement/liked_by_screen.dart';
import 'package:tripthread/screens/notifications/notifications_screen.dart';
import 'package:tripthread/screens/post/post_detail_screen.dart';
import 'package:tripthread/screens/chat/conversation_list_screen.dart';
import 'package:tripthread/screens/chat/chat_screen.dart';
import 'package:tripthread/screens/chat/new_conversation_screen.dart';
import 'package:tripthread/providers/chat_provider.dart';
import 'package:tripthread/screens/share/share_link_screen.dart';
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
      rethrow;
    }

    debugPrint('[main] Creating ConnectivityService');
    final connectivityService = ConnectivityService();
    debugPrint('[main] Initializing ConnectivityService');
    try {
      await connectivityService.initialize();
      debugPrint('[main] ConnectivityService initialized');
    } catch (e) {
      debugPrint('[main] ConnectivityService initialization failed: $e');
      rethrow;
    }

    debugPrint('[main] Creating MetadataCacheService');
    final metadataCacheService = MetadataCacheService();
    try {
      await metadataCacheService.init();
      debugPrint('[main] MetadataCacheService initialized');
    } catch (e) {
      debugPrint('[main] MetadataCacheService initialization failed: $e');
      rethrow;
    }

    debugPrint('[main] Creating core services');
    final apiService = ApiService();
    final tripService = TripService();
    final mediaService = MediaService(apiService);
    final deepLinkService = DeepLinkService();
    final likeService = LikeService();
    final commentService = CommentService();
    final shareService = ShareService();
    debugPrint('[main] Core services created');

    debugPrint('[main] Setting up providers');
    runApp(
      MultiProvider(
        providers: [
          Provider<StorageService>.value(value: storageService),
          Provider<MetadataCacheService>.value(value: metadataCacheService),
          Provider<ApiService>.value(value: apiService),
          Provider<TripService>.value(value: tripService),
          Provider<MediaService>.value(value: mediaService),
          Provider<DeepLinkService>.value(value: deepLinkService),
          Provider<LikeService>.value(value: likeService),
          Provider<CommentService>.value(value: commentService),
          Provider<ShareService>.value(value: shareService),
          Provider<GoogleSignInService>.value(value: GoogleSignInService()),
          ChangeNotifierProvider<ConnectivityService>.value(
            value: connectivityService,
          ),
          ChangeNotifierProvider<AuthProvider>(
            create: (context) {
              debugPrint('[main] Creating AuthProvider');
              final authProvider = AuthProvider(
                apiService: apiService,
                storageService: storageService,
                googleSignInService: context.read<GoogleSignInService>(),
              );
              // Set up the unauthorized callback to trigger logout
              apiService.setUnauthorizedCallback(() {
                debugPrint(
                  '[main] Unauthorized callback triggered - forcing logout',
                );
                authProvider.forceLogout(
                  message: 'Session expired. Please log in again.',
                );
              });
              return authProvider;
            },
          ),
          ChangeNotifierProvider<UserProvider>(
            create: (context) {
              debugPrint('[main] Creating UserProvider');
              final apiService = context.read<ApiService>();
              final metadataCache = context.read<MetadataCacheService>();
              final authProvider = context.read<AuthProvider>();
              final userProvider = UserProvider(
                apiService: apiService,
                metadataCache: metadataCache,
              );
              authProvider.addListener(() {
                if (authProvider.isAuthenticated &&
                    authProvider.currentUser != null) {
                  userProvider.warmMetadataCacheIfNeeded(
                    authProvider.currentUser!.id,
                    currentUser: authProvider.currentUser,
                  );
                } else if (!authProvider.isAuthenticated) {
                  userProvider.clearCache();
                }
              });
              return userProvider;
            },
          ),
          ChangeNotifierProvider<TripProvider>(
            create: (context) {
              debugPrint('[main] Creating TripProvider');
              final authProvider = context.read<AuthProvider>();
              final provider = TripProvider(tripService: tripService);
              tripService.setStorageService(storageService);
              tripService.setUnauthorizedCallback(() {
                debugPrint(
                  '[main] TripService unauthorized — forcing logout',
                );
                authProvider.forceLogout(
                  message: 'Session expired. Please log in again.',
                );
              });
              authProvider.addListener(() {
                if (!authProvider.isAuthenticated) {
                  provider.clearData();
                }
              });
              return provider;
            },
          ),
          ChangeNotifierProvider<PlaceProvider>(
            create: (context) {
              debugPrint('[main] Creating PlaceProvider');
              return PlaceProvider(apiService: apiService);
            },
          ),
          ChangeNotifierProvider<EngagementProvider>(
            create: (context) {
              debugPrint('[main] Creating EngagementProvider');
              final authProvider = context.read<AuthProvider>();
              final provider = EngagementProvider(likeService: likeService);
              likeService.setStorageService(storageService);
              authProvider.addListener(() {
                if (!authProvider.isAuthenticated) {
                  provider.clear();
                }
              });
              return provider;
            },
          ),
          ChangeNotifierProxyProvider<EngagementProvider, FeedProvider>(
            create: (context) {
              debugPrint('[main] Creating FeedProvider');
              return FeedProvider(
                apiService: apiService,
                engagementProvider: context.read<EngagementProvider>(),
              );
            },
            update: (context, engagementProvider, feedProvider) {
              debugPrint(
                '[main] Updating FeedProvider with EngagementProvider',
              );
              // If feedProvider exists, return it (we don't need to recreate)
              // The provider already has the engagementProvider reference
              return feedProvider ??
                  FeedProvider(
                    apiService: apiService,
                    engagementProvider: engagementProvider,
                  );
            },
          ),
          ChangeNotifierProvider<CommentProvider>(
            create: (context) {
              debugPrint('[main] Creating CommentProvider');
              final provider = CommentProvider(commentService: commentService);
              commentService.setStorageService(storageService);
              return provider;
            },
          ),
          ChangeNotifierProvider<ShareProvider>(
            create: (context) {
              debugPrint('[main] Creating ShareProvider');
              final provider = ShareProvider(
                shareService: shareService,
              );
              shareService.setStorageService(storageService);
              return provider;
            },
          ),
          ChangeNotifierProvider<ChatProvider>(
            create: (context) {
              debugPrint('[main] Creating ChatProvider');
              final auth = context.read<AuthProvider>();
              final chat = ChatProvider(
                apiService: apiService,
                storageService: storageService,
              );
              var wasAuthenticated = auth.isAuthenticated;
              void syncChatSocket() {
                final authed = auth.isAuthenticated;
                if (authed && !wasAuthenticated) {
                  debugPrint('[main] Auth signed in — connecting chat WebSocket');
                  chat.onAuthSignedIn();
                } else if (!authed && wasAuthenticated) {
                  debugPrint('[main] Auth signed out — resetting chat WebSocket');
                  chat.onAuthSignedOut();
                }
                wasAuthenticated = authed;
              }

              auth.addListener(syncChatSocket);
              if (auth.isAuthenticated) {
                // Listener only runs on transitions; opening chat while already logged in must open the socket.
                chat.onAuthSignedIn();
              }
              return chat;
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
    runApp(
      MaterialApp(
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
      ),
    );
  }
}

/// Resolves GoRouter `extra` for `/trip/:tripId/map` into [MapPlace] list.
/// Supports thread jumps (`initialZoomLocation`), [PlaceOnTrip] visits from trip detail, and [MapPlace].
List<MapPlace>? mapPlacesFromTripMapExtra(Map<String, dynamic>? extra) {
  if (extra == null) return null;

  final zoom = extra['initialZoomLocation'];
  if (zoom is Place) {
    return [
      MapPlace(
        place: zoom,
        origin: MapPlaceOrigin.threadEntry,
      ),
    ];
  }

  final raw = extra['places'];
  if (raw == null) return null;
  if (raw is List<MapPlace>) return List<MapPlace>.from(raw);
  if (raw is List<PlaceOnTrip>) {
    return raw.map(MapPlace.fromPlaceOnTrip).toList();
  }
  if (raw is Iterable) {
    final out = <MapPlace>[];
    for (final e in raw) {
      if (e is MapPlace) {
        out.add(e);
      } else if (e is PlaceOnTrip) {
        out.add(MapPlace.fromPlaceOnTrip(e));
      }
    }
    return out.isEmpty ? null : out;
  }
  return null;
}

class TripThreadAppRouter extends StatefulWidget {
  const TripThreadAppRouter({super.key});

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
      icon: const Icon(Icons.wifi_off_rounded, size: 28.0, color: Colors.white),
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
    final deepLinkService = Provider.of<DeepLinkService>(
      context,
      listen: false,
    );

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
          authProvider.uiNotifier,
        ]),
        redirect: (context, state) {
          final authProvider = Provider.of<AuthProvider>(
            context,
            listen: false,
          );
          final isLoading = authProvider.isLoading;
          final isLoggedIn = authProvider.isAuthenticated;
          final location = state.uri.toString();

          if (location != TripThreadAppRouter._lastLocation) {
            debugPrint('[GoRouter] location changed to: $location');
            debugPrint(
              '[GoRouter] isLoading: $isLoading, isLoggedIn: $isLoggedIn',
            );
            TripThreadAppRouter._lastLocation = location;
          }

          // Don't redirect while loading
          if (isLoading) {
            debugPrint('[GoRouter] Still loading, no redirect');
            return null;
          }

          // Redirect to login if not authenticated and not on auth pages
          if (!isLoggedIn &&
              location != '/login' &&
              location != '/signup' &&
              location != '/forgot-password' &&
              !location.startsWith('/reset-password')) {
            debugPrint('[GoRouter] Not logged in, redirecting to /login');
            return '/login';
          }

          final requiresProfileCompletion =
              authProvider.requiresProfileCompletion;

          // Authenticated but profile incomplete: must complete profile before home
          if (isLoggedIn &&
              requiresProfileCompletion &&
              location != '/complete-profile') {
            debugPrint(
              '[GoRouter] Profile incomplete, redirecting to /complete-profile',
            );
            return '/complete-profile';
          }

          // On complete-profile but profile now complete: go home
          // (HomeScreen will handle ongoing trip redirect after tripProvider.initialize())
          if (isLoggedIn &&
              !requiresProfileCompletion &&
              location == '/complete-profile') {
            debugPrint('[GoRouter] Profile complete, redirecting to /home');
            return '/home';
          }

          // Redirect to home (or complete-profile) if authenticated and on auth pages
          // (HomeScreen will handle ongoing trip redirect after tripProvider.initialize())
          if (isLoggedIn &&
              (location == '/login' ||
                  location == '/signup' ||
                  location == '/forgot-password' ||
                  location.startsWith('/reset-password'))) {
            if (requiresProfileCompletion) {
              return '/complete-profile';
            }

            debugPrint('[GoRouter] Already logged in, redirecting to /home');
            return '/home';
          }

          debugPrint('[GoRouter] No redirect needed');
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
            path: '/complete-profile',
            builder: (context, state) => const CompleteProfileScreen(),
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
            path: '/profile/:userId/followers',
            builder: (context, state) {
              final userId = state.pathParameters['userId']!;
              debugPrint(
                '[GoRouter] Building FollowersFollowingScreen - followers for user: $userId',
              );
              return FollowersFollowingScreen(
                userId: userId,
                showFollowers: true,
              );
            },
          ),
          GoRoute(
            path: '/profile/:userId/following',
            builder: (context, state) {
              final userId = state.pathParameters['userId']!;
              debugPrint(
                '[GoRouter] Building FollowersFollowingScreen - following for user: $userId',
              );
              return FollowersFollowingScreen(
                userId: userId,
                showFollowers: false,
              );
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
              final extra = state.extra as Map<String, dynamic>?;
              final highlightEntryId = extra?['highlightEntryId'] as String?;
              return TripThreadScreen(
                tripId: tripId,
                highlightEntryId: highlightEntryId,
              );
            },
          ),
          GoRoute(
            path: '/trip/:tripId/map',
            builder: (context, state) {
              final tripId = state.pathParameters['tripId']!;
              final extra = state.extra as Map<String, dynamic>?;
              final tripTitle = extra?['tripTitle'] as String? ?? 'Trip Map';
              final places = mapPlacesFromTripMapExtra(extra);

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
            path: '/trip/:tripId/final-post',
            builder: (context, state) {
              final tripId = state.pathParameters['tripId']!;
              return ChangeNotifierProvider<FinalPostProvider>(
                create: (context) {
                  final provider = FinalPostProvider(
                    tripService: context.read<TripService>(),
                  );
                  provider.loadDraft(tripId);
                  return provider;
                },
                child: FinalPostEditScreen(tripId: tripId),
              );
            },
          ),
          GoRoute(
            path: '/notifications',
            builder: (context, state) {
              return const NotificationsScreen();
            },
          ),
          GoRoute(
            path: '/chat',
            builder: (context, state) {
              final tripId = state.uri.queryParameters['tripId'];
              return ConversationListScreen(tripId: tripId);
            },
          ),
          GoRoute(
            path: '/chat/new',
            builder: (context, state) => const NewConversationScreen(),
          ),
          GoRoute(
            path: '/chat/:conversationId',
            builder: (context, state) {
              final conversationId = state.pathParameters['conversationId']!;
              return ChatScreen(conversationId: conversationId);
            },
          ),
          GoRoute(
            path: '/post/:entityType/:entityId',
            builder: (context, state) {
              final entityType = state.pathParameters['entityType']!;
              final entityId = state.pathParameters['entityId']!;
              final extra = state.extra as Map<String, dynamic>?;
              final scrollToCommentId = extra?['scrollToCommentId'] as String?;
              return PostDetailScreen(
                entityType: entityType,
                entityId: entityId,
                scrollToCommentId: scrollToCommentId,
              );
            },
          ),
          GoRoute(
            path: '/share/:shareToken',
            builder: (context, state) {
              final shareToken = state.pathParameters['shareToken']!;
              return ShareLinkScreen(shareToken: shareToken);
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
          GoRoute(
            path: '/likes/:entityType/:entityId',
            builder: (context, state) {
              final entityType = state.pathParameters['entityType']!;
              final entityId = state.pathParameters['entityId']!;
              return LikedByScreen(entityType: entityType, entityId: entityId);
            },
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
                if (!context.read<AuthProvider>().isLoading) {
                  return const SizedBox.shrink();
                }
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
