import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:form_field_validator/form_field_validator.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/services/google_sign_in_service.dart';
import 'package:tripthread/utils/validators.dart';
import 'package:tripthread/widgets/custom_text_field.dart';
import 'package:tripthread/widgets/loading_button.dart';
import 'package:tripthread/widgets/tripthread_logo.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    final input = _emailController.text.trim();
    // Only normalize email on client side.
    // Username normalization is handled server-side to keep implementations in sync.
    final emailOrUsername = input.contains('@')
        ? Validators.normalizeEmail(input)
        : input;

    final success = await authProvider.login(
      email: emailOrUsername,
      password: _passwordController.text,
    );
    debugPrint(
      'LoginScreen: login success = $success, isAuthenticated = ${authProvider.isAuthenticated}',
    );
    if (success && mounted) {
      context.go('/home');
    } else if (mounted) {
      // Persist inline error; do not auto-dismiss via SnackBar
      authProvider.markErrorAsShown();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 60),

                // Logo and Title
                Column(
                  children: [
                    const TripThreadLogo(size: 64),
                    const SizedBox(height: 24),
                    Text(
                      'Welcome back',
                      style: Theme.of(context).textTheme.displaySmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Sign in to continue your travel journey',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),

                const SizedBox(height: 48),

                // Email or Username Field
                CustomTextField(
                  controller: _emailController,
                  label: 'Email or Username',
                  keyboardType: TextInputType.text,
                  prefixIcon: Icons.person_outlined,
                  validator: Validators.validateEmailOrUsername,
                  onChanged: (_) {
                    // Clear error when user starts typing after an error
                    final authProvider = context.read<AuthProvider>();
                    if (authProvider.error != null) {
                      authProvider.clearError();
                    }
                  },
                ),

                const SizedBox(height: 16),

                // Password Field
                CustomTextField(
                  controller: _passwordController,
                  label: 'Password',
                  obscureText: _obscurePassword,
                  prefixIcon: Icons.lock_outlined,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                  validator: RequiredValidator(
                    errorText: 'Password is required',
                  ).call,
                  onChanged: (_) {
                    // Clear error when user starts typing after an error
                    final authProvider = context.read<AuthProvider>();
                    if (authProvider.error != null) {
                      authProvider.clearError();
                    }
                  },
                ),

                const SizedBox(height: 24),

                // Persistent Error Message
                Consumer<AuthProvider>(
                  builder: (context, authProvider, child) {
                    return AnimatedBuilder(
                      animation: authProvider.uiNotifier,
                      builder: (context, _) {
                        if (authProvider.error == null) {
                          return const SizedBox.shrink();
                        }
                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).colorScheme.error.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: Theme.of(context).colorScheme.error,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  authProvider.error!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.close,
                                  color: Theme.of(context).colorScheme.error,
                                  size: 18,
                                ),
                                onPressed: () {
                                  authProvider.clearError();
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),

                // Retry session restore (tokens on device but /users/me failed transiently)
                Consumer<AuthProvider>(
                  builder: (context, authProvider, child) {
                    if (!authProvider.canRetrySessionRestore) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: authProvider.isLoading
                              ? null
                              : () async {
                                  await authProvider.retrySessionRestore();
                                  if (!context.mounted) return;
                                  final a = context.read<AuthProvider>();
                                  if (a.isAuthenticated) {
                                    if (a.requiresProfileCompletion) {
                                      context.go('/complete-profile');
                                    } else {
                                      context.go('/home');
                                    }
                                  }
                                },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry restoring session'),
                        ),
                      ),
                    );
                  },
                ),

                // Login Button
                Consumer<AuthProvider>(
                  builder: (context, authProvider, child) {
                    return LoadingButton(
                      onPressed: _handleLogin,
                      isLoading: authProvider.isLoading,
                      child: const Text('Sign In'),
                    );
                  },
                ),

                const SizedBox(height: 24),

                // Or continue with
                Row(
                  children: [
                    Expanded(
                      child: Divider(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Or continue with',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Divider(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Google Sign In
                Consumer<AuthProvider>(
                  builder: (context, authProvider, _) {
                    return SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: authProvider.isLoading
                            ? null
                            : () async {
                                final googleSignIn = context
                                    .read<GoogleSignInService>();
                                final nativeResult = await googleSignIn
                                    .signInWithAccountPicker();
                                if (!mounted) return;
                                String? idTokenToUse;
                                switch (nativeResult) {
                                  case GoogleSignInNativeSuccess(
                                    :final idToken,
                                  ):
                                    idTokenToUse = idToken;
                                    break;
                                  case GoogleSignInNativeCancelled():
                                    return;
                                  case GoogleSignInNativeDeveloperError():
                                    // Log technical details for developers, show user-friendly message
                                    debugPrint(
                                      '[LoginScreen] Google Sign-In configuration error (SHA-1 not configured)',
                                    );
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Google Sign-In is not properly configured. Please contact support or try again later.',
                                          ),
                                          duration: Duration(seconds: 5),
                                        ),
                                      );
                                    }
                                    return;
                                  case GoogleSignInNativeFailure(
                                    :final message,
                                  ):
                                    // Log technical details, show generic message to user
                                    debugPrint(
                                      '[LoginScreen] Google Sign-In error: $message',
                                    );
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Google sign-in is currently unavailable. Please try again later.',
                                          ),
                                        ),
                                      );
                                    }
                                    return;
                                }
                                final result = await authProvider
                                    .signInWithGoogle(idTokenToUse);
                                if (!mounted) return;
                                switch (result) {
                                  case GoogleSignInSuccess():
                                    if (authProvider
                                        .requiresProfileCompletion) {
                                      context.go('/complete-profile');
                                    } else {
                                      context.go('/home');
                                    }
                                    break;
                                  case GoogleSignInFailure():
                                    authProvider.markErrorAsShown();
                                }
                              },
                        icon: Image.asset(
                          'assets/images/google_logo.png',
                          width: 20,
                          height: 20,
                          errorBuilder: (context, error, stackTrace) {
                            // Fallback to icon if image not found
                            return const Icon(Icons.login, size: 20);
                          },
                        ),
                        label: const Text('Continue with Google'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 16,
                          ),
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 24),

                // Forgot Password Link
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      final authProvider = context.read<AuthProvider>();
                      if (authProvider.error != null) {
                        authProvider.clearError();
                      }
                      context.go('/forgot-password');
                    },
                    child: const Text('Forgot Password?'),
                  ),
                ),

                const SizedBox(height: 24),

                // Sign Up Link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Don't have an account? ",
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    TextButton(
                      onPressed: () {
                        final authProvider = context.read<AuthProvider>();
                        if (authProvider.error != null) {
                          authProvider.clearError();
                        }
                        context.go('/signup');
                      },
                      child: const Text('Sign Up'),
                    ),
                  ],
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
    // );
  }
}
