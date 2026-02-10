import 'package:flutter/foundation.dart';
import 'package:tripthread/models/user.dart';
import 'package:tripthread/services/api_service.dart';
import 'package:tripthread/services/storage_service.dart';

/// Result of Google sign-in: success (logged in), email not found (go to signup), or failure.
sealed class GoogleSignInResult {}

class GoogleSignInSuccess extends GoogleSignInResult {}

class GoogleSignInEmailNotFound extends GoogleSignInResult {
  final String? email;
  GoogleSignInEmailNotFound([this.email]);
}

class GoogleSignInFailure extends GoogleSignInResult {
  final String message;
  GoogleSignInFailure(this.message);
}

class AuthProvider extends ChangeNotifier {
  final ApiService _apiService;
  final StorageService _storageService;

  User? _currentUser;
  bool _isLoading = true;
  String? _error;
  bool _hasShownError = false;
  bool _isInitializing = false;

  // Notifier dedicated for UI-only updates (e.g., error banner)
  final ChangeNotifier uiNotifier = ChangeNotifier();
  // Notifier dedicated for routing-related changes only (auth/loading)
  final ChangeNotifier routingNotifier = ChangeNotifier();

  AuthProvider({
    required ApiService apiService,
    required StorageService storageService,
  })  : _apiService = apiService,
        _storageService = storageService {
    _apiService.setStorageService(_storageService);
    _initializeAuth();
  }

  // Getters
  User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _currentUser != null;
  String? get error => _error;
  /// True when user is authenticated but must complete profile (username + password) before full access.
  bool get requiresProfileCompletion =>
      _currentUser != null && (_currentUser!.profileComplete == false);

  Future<void> _initializeAuth() async {
    // Skip initialization if already in progress or user is already authenticated
    if (_isInitializing) {
      debugPrint('AuthProvider: Initialization already in progress, skipping');
      return;
    }

    // If user is already authenticated (e.g., after signup/login), skip initialization
    if (_currentUser != null) {
      debugPrint('AuthProvider: User already authenticated, skipping initialization');
      _setLoadingState(false);
      return;
    }

    debugPrint('AuthProvider: Starting initialization');
    _isInitializing = true;
    _setLoadingState(true);
    try {
      debugPrint('AuthProvider: Checking tokens...');
      final hasTokens = await _storageService
          .hasValidTokens()
          .timeout(const Duration(seconds: 5), onTimeout: () {
        debugPrint('AuthProvider: hasValidTokens() timed out!');
        throw Exception('hasValidTokens() timed out');
      });
      debugPrint('AuthProvider: hasTokens = $hasTokens');
      
      // Double-check if user was authenticated during token check (race condition protection)
      if (_currentUser != null) {
        debugPrint('AuthProvider: User authenticated during token check, skipping getCurrentUser');
        return;
      }

      if (hasTokens) {
        debugPrint('AuthProvider: Getting userId...');
        final userId = await _storageService
            .getUserId()
            .timeout(const Duration(seconds: 5), onTimeout: () {
          debugPrint('AuthProvider: getUserId() timed out!');
          throw Exception('getUserId() timed out');
        });
        debugPrint('AuthProvider: userId = $userId');
        
        // Double-check again if user was authenticated during userId fetch
        if (_currentUser != null) {
          debugPrint('AuthProvider: User authenticated during userId fetch, skipping getCurrentUser');
          return;
        }

        if (userId != null) {
          debugPrint('AuthProvider: Calling getCurrentUser...');
          final response = await _apiService
              .getCurrentUser()
              .timeout(const Duration(seconds: 5), onTimeout: () {
            debugPrint('AuthProvider: getCurrentUser() timed out!');
            throw Exception('getCurrentUser() timed out');
          });
          debugPrint(
              'AuthProvider: getUser response = ${response.success} | ${response.data} | ${response.error}');
          
          // Final check: if user was authenticated during API call (e.g., from signup/login)
          if (_currentUser != null) {
            debugPrint('AuthProvider: User authenticated during getCurrentUser, preserving existing state');
            return;
          }

          if (response.success && response.data != null) {
            _currentUser = response.data;
            routingNotifier.notifyListeners();
            notifyListeners();
          } else {
            debugPrint('AuthProvider: Invalid tokens, clearing');
            await _storageService.clearTokens();
          }
        }
      }
    } catch (e, stack) {
      // Only clear tokens and set error if user is not already authenticated
      // This prevents clearing tokens that were just set by signup/login
      if (_currentUser == null) {
        _error = 'Failed to initialize authentication';
        uiNotifier.notifyListeners();
        debugPrint('AuthProvider: Exception in _initializeAuth: $e\n$stack');
        await _storageService.clearTokens();
      } else {
        debugPrint('AuthProvider: Exception in _initializeAuth but user is authenticated, ignoring: $e');
      }
    } finally {
      _isInitializing = false;
      _setLoadingState(false);
    }
  }

  Future<bool> signup({
    required String email,
    required String password,
    required String name,
    required String username,
  }) async {
    try {
      _setLoadingState(true);
      _clearError();

      final response = await _apiService.signup(
        email: email,
        password: password,
        name: name,
        username: username,
      );

      debugPrint(
          '[AuthProvider] signup response: success=${response.success}, error=${response.error}');

      if (response.success && response.data != null) {
        final authData = response.data!;
        
        // Save tokens first to ensure they're persisted before setting user
        // This prevents race condition with _initializeAuth()
        await _storageService.saveTokens(
          accessToken: authData.accessToken,
          refreshToken: authData.refreshToken,
          userId: authData.user.id,
        );

        // Set user after tokens are saved to prevent race condition
        _currentUser = authData.user;
        routingNotifier.notifyListeners();
        notifyListeners();

        _setLoadingState(false);
        return true;
      } else {
        _setError(response.error ?? 'Signup failed. Please try again.');
        debugPrint('[AuthProvider] signup error set: $_error');
        _setLoadingState(false);
        return false;
      }
    } catch (e) {
      debugPrint('[AuthProvider] signup catch error: $e');
      _setError('Network error. Please check your connection and try again.');
      _setLoadingState(false);
      debugPrint('Signup error: $e');
      return false;
    }
  }

  Future<bool> login({
    required String email,
    required String password,
  }) async {
    try {
      _setLoadingState(true);
      _clearError(); // Clear any previous error

      final response = await _apiService.login(
        email: email,
        password: password,
      );

      debugPrint(
          '[AuthProvider] login response: success=${response.success}, error=${response.error}, data=${response.data}');

      if (response.success && response.data != null) {
        final authData = response.data!;
        
        // Save tokens first to ensure they're persisted before setting user
        // This prevents race condition with _initializeAuth()
        await _storageService.saveTokens(
          accessToken: authData.accessToken,
          refreshToken: authData.refreshToken,
          userId: authData.user.id,
        );

        // Set user after tokens are saved to prevent race condition
        _currentUser = authData.user;
        routingNotifier.notifyListeners();
        notifyListeners();

        _setLoadingState(false);
        return true;
      } else {
        _setError(
            response.error ?? 'Login failed. Please check your credentials.');
        debugPrint('[AuthProvider] login error set: $_error');
        _setLoadingState(false);
        return false;
      }
    } catch (e) {
      debugPrint('[AuthProvider] login catch error: $e');
      _setError('Network error. Please check your connection and try again.');
      _setLoadingState(false);
      debugPrint('Login error: $e');
      return false;
    }
  }

  Future<bool> completeProfile({
    required String username,
    required String password,
    String? name,
  }) async {
    try {
      _setLoadingState(true);
      _clearError();
      final response = await _apiService.completeProfile(
        username: username,
        password: password,
        name: name,
      );
      if (response.success && response.data != null) {
        final authData = response.data!;
        await _storageService.saveTokens(
          accessToken: authData.accessToken,
          refreshToken: authData.refreshToken,
          userId: authData.user.id,
        );
        _currentUser = authData.user;
        routingNotifier.notifyListeners();
        notifyListeners();
        _setLoadingState(false);
        return true;
      } else if (response.error == 'Profile already complete') {
        // Backend says profile is complete; refresh user and redirect
        final userResponse = await _apiService.getCurrentUser();
        if (userResponse.success && userResponse.data != null) {
          _currentUser = userResponse.data!.copyWith(profileComplete: true);
          routingNotifier.notifyListeners();
          notifyListeners();
          _setLoadingState(false);
          return true;
        }
      }
      _setError(response.error ?? 'Failed to complete profile.');
      _setLoadingState(false);
      return false;
    } catch (e) {
      debugPrint('[AuthProvider] completeProfile catch error: $e');
      _setError('Network error. Please try again.');
      _setLoadingState(false);
      return false;
    }
  }

  Future<bool> deleteAccount() async {
    try {
      debugPrint('[AuthProvider] Delete account called');
      final response = await _apiService.deleteAccount();
      
      if (response.success) {
        // Clear local storage and state
        await _storageService.clearTokens();
        _currentUser = null;
        _error = null;
        _isLoading = false;
        notifyListeners();
        routingNotifier.notifyListeners();
        debugPrint('[AuthProvider] Account deleted successfully');
        return true;
      } else {
        _error = response.error ?? 'Failed to delete account';
        notifyListeners();
        debugPrint('[AuthProvider] Delete account error: $_error');
        return false;
      }
    } catch (e) {
      _error = 'An unexpected error occurred while deleting account';
      notifyListeners();
      debugPrint('Delete account error: $e');
      return false;
    }
  }

  Future<void> logout() async {
    try {
      final refreshToken = await _storageService.getRefreshToken();
      if (refreshToken != null) {
        await _apiService.logout();
      }
    } catch (e) {
      debugPrint('Logout error: $e');
    } finally {
      _currentUser = null;
      routingNotifier.notifyListeners();
      notifyListeners();
      await _storageService.clearTokens();
    }
  }

  Future<bool> forgotPassword({
    required String email,
  }) async {
    try {
      _setLoadingState(true);
      _clearError();

      final response = await _apiService.forgotPassword(email: email);

      debugPrint(
          '[AuthProvider] forgotPassword response: success=${response.success}, error=${response.error}');

      if (response.success) {
        _setLoadingState(false);
        return true;
      } else {
        _setError(
            response.error ?? 'Failed to send reset email. Please try again.');
        debugPrint('[AuthProvider] forgotPassword error set: $_error');
        _setLoadingState(false);
        return false;
      }
    } catch (e) {
      debugPrint('[AuthProvider] forgotPassword catch error: $e');
      _setError('Network error. Please check your connection and try again.');
      _setLoadingState(false);
      debugPrint('Forgot password error: $e');
      return false;
    }
  }

  Future<bool> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    try {
      _setLoadingState(true);
      _clearError();

      final response = await _apiService.resetPassword(
        token: token,
        newPassword: newPassword,
      );

      debugPrint(
          '[AuthProvider] resetPassword response: success=${response.success}, error=${response.error}');

      if (response.success) {
        // After successful password reset, backend invalidates all refresh tokens
        // for security. We must log out the user immediately so they can log in
        // with their new password. This is a security best practice.
        debugPrint('[AuthProvider] Password reset successful, logging out user');
        await logout();
        _setLoadingState(false);
        return true;
      } else {
        _setError(
            response.error ?? 'Failed to reset password. Please try again.');
        debugPrint('[AuthProvider] resetPassword error set: $_error');
        _setLoadingState(false);
        return false;
      }
    } catch (e) {
      debugPrint('[AuthProvider] resetPassword catch error: $e');
      _setError('Network error. Please check your connection and try again.');
      _setLoadingState(false);
      debugPrint('Reset password error: $e');
      return false;
    }
  }

  /// Sign in with Google idToken. Returns [GoogleSignInSuccess], [GoogleSignInEmailNotFound] (navigate to signup), or [GoogleSignInFailure].
  Future<GoogleSignInResult> signInWithGoogle(String idToken) async {
    try {
      _setLoadingState(true);
      _clearError();
      final result = await _apiService.signInWithGoogle(idToken);
      final response = result.response;
      final emailFromError = result.emailFromError;

      if (response.success && response.data != null) {
        final authData = response.data!;
        await _storageService.saveTokens(
          accessToken: authData.accessToken,
          refreshToken: authData.refreshToken,
          userId: authData.user.id,
        );
        _currentUser = authData.user;
        routingNotifier.notifyListeners();
        notifyListeners();
        _setLoadingState(false);
        return GoogleSignInSuccess();
      }

      if (response.error == 'EMAIL_NOT_FOUND') {
        _setLoadingState(false);
        return GoogleSignInEmailNotFound(emailFromError);
      }

      _setError(response.error ?? 'Sign-in failed. Try again.');
      _setLoadingState(false);
      return GoogleSignInFailure(response.error ?? 'Sign-in failed. Try again.');
    } catch (e) {
      debugPrint('[AuthProvider] signInWithGoogle catch error: $e');
      _setError('Network error. Please check your connection and try again.');
      _setLoadingState(false);
      return GoogleSignInFailure('Network error. Please check your connection and try again.');
    }
  }

  Future<bool> linkGoogle(String idToken) async {
    try {
      _clearError();
      final response = await _apiService.linkGoogle(idToken);
      if (response.success) {
        final userResponse = await _apiService.getCurrentUser();
        if (userResponse.success && userResponse.data != null && _currentUser != null) {
          _currentUser = userResponse.data;
          notifyListeners();
        }
        return true;
      } else {
        _setError(response.error ?? 'Failed to link Google account.');
        return false;
      }
    } catch (e) {
      debugPrint('[AuthProvider] linkGoogle catch error: $e');
      _setError('Network error. Please try again.');
      return false;
    }
  }

  // Helper methods for cleaner state management
  void _setLoadingState(bool loading) {
    _isLoading = loading;
    routingNotifier.notifyListeners();
    notifyListeners();
  }

  void _setError(String error) {
    _error = error;
    _hasShownError = false;
    uiNotifier.notifyListeners();
  }

  void _clearError() {
    if (_error != null) {
      _error = null;
      _hasShownError = false;
      uiNotifier.notifyListeners();
    }
  }

  bool get shouldShowError => _error != null && !_hasShownError;

  void clearError() {
    debugPrint('[AuthProvider] clearError called by user');
    _clearError();
  }

  // Method to mark error as shown (for toast notifications)
  void markErrorAsShown() {
    _hasShownError = true;
    uiNotifier.notifyListeners();
  }

  void updateUser(User user) {
    _currentUser = user;
    notifyListeners();
  }

  // Called by ApiService when refresh fails or user is unauthorized
  Future<void> forceLogout({String? message}) async {
    debugPrint('[AuthProvider] forceLogout called with message: $message');

    _isLoading = false;
    _currentUser = null;
    await _storageService.clearTokens();

    // Set error message if provided
    if (message != null) {
      _error = message;
      _hasShownError = false;
      uiNotifier.notifyListeners();
    }

    // If desired, try to clear UserProvider cache (if context is available)
    // This block is safe in widget code, or can use an injected clearUserCache callback.
    // try {
    //   final userProvider = Provider.of<UserProvider>(navigatorKey.currentContext!, listen: false);
    //   userProvider.clearCache();
    // } catch (e) {
    //   debugPrint('[AuthProvider] Could not clear UserProvider cache: $e');
    // }
    // For now, leave as a comment unless you want to inject context/global key.

    routingNotifier.notifyListeners();
    notifyListeners();

    debugPrint(
        '[AuthProvider] forceLogout completed - isAuthenticated: $isAuthenticated');
  }
}
