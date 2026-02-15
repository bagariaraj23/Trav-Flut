import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:form_field_validator/form_field_validator.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/services/google_sign_in_service.dart';
import 'package:tripthread/utils/validators.dart';
import 'package:tripthread/widgets/custom_text_field.dart';
import 'package:tripthread/widgets/loading_button.dart';
import 'package:flutter/services.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignup() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    final rawUsername = _usernameController.text.trim();
    final username = Validators.normalizeUsernameToAscii(rawUsername);
    final rawEmail = _emailController.text;
    final email = Validators.normalizeEmail(rawEmail);
    debugPrint('[SignupScreen] Submitting email: "$email" (raw length=${rawEmail.length}, normalized length=${email.length})');
    final success = await authProvider.signup(
      email: email,
      password: _passwordController.text,
      name: _nameController.text.trim(),
      username: username,
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
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        SystemNavigator.pop();
      },
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 40),

                  // Logo and Title
                  Column(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.travel_explore,
                          size: 32,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Create account',
                        style: Theme.of(context).textTheme.displaySmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Start documenting your travel adventures',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),

                  const SizedBox(height: 48),

                  // Name Field
                  CustomTextField(
                    controller: _nameController,
                    label: 'Full Name',
                    prefixIcon: Icons.person_outlined,
                    validator: MultiValidator([
                      RequiredValidator(errorText: 'Name is required'),
                      MinLengthValidator(
                        2,
                        errorText: 'Name must be at least 2 characters',
                      ),
                    ]).call,
                    onChanged: (_) {
                      final authProvider = context.read<AuthProvider>();
                      if (authProvider.error != null) {
                        authProvider.clearError();
                      }
                    },
                    textCapitalization: TextCapitalization.words,
                  ),

                  const SizedBox(height: 16),

                  // Username Field (validate after normalizing so Unicode lookalikes work)
                  CustomTextField(
                    controller: _usernameController,
                    label: 'Username',
                    prefixIcon: Icons.alternate_email,
                    validator: (value) {
                      final normalized =
                          Validators.normalizeUsernameToAscii(value?.trim() ?? '');
                      if (normalized.isEmpty) return 'Username is required';
                      if (normalized.length < 3) {
                        return 'Username must be at least 3 characters';
                      }
                      if (normalized.length > 30) {
                        return 'Username must be less than 30 characters';
                      }
                      if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(normalized)) {
                        return 'Username can only contain letters, numbers, and underscores';
                      }
                      return null;
                    },
                    onChanged: (_) {
                      final authProvider = context.read<AuthProvider>();
                      if (authProvider.error != null) {
                        authProvider.clearError();
                      }
                    },
                    maxLength: 30,
                  ),

                  const SizedBox(height: 16),

                  // Email Field (clear error on tap/focus so paste or new email doesn't show stale "email taken")
                  CustomTextField(
                    controller: _emailController,
                    label: 'Email',
                    keyboardType: TextInputType.emailAddress,
                    prefixIcon: Icons.email_outlined,
                    validator: MultiValidator([
                      RequiredValidator(errorText: 'Email is required'),
                      EmailValidator(errorText: 'Please enter a valid email'),
                    ]).call,
                    onTap: () {
                      final authProvider = context.read<AuthProvider>();
                      if (authProvider.error != null) {
                        authProvider.clearError();
                      }
                    },
                    onChanged: (_) {
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
                    validator: MultiValidator([
                      RequiredValidator(errorText: 'Password is required'),
                      MinLengthValidator(
                        8,
                        errorText: 'Password must be at least 8 characters',
                      ),
                    ]).call,
                    onChanged: (_) {
                      final authProvider = context.read<AuthProvider>();
                      if (authProvider.error != null) {
                        authProvider.clearError();
                      }
                    },
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'Must be at least 8 characters long',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),

                  const SizedBox(height: 24),

                  // Error Message
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
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
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

                  // Signup Button
                  Consumer<AuthProvider>(
                    builder: (context, authProvider, child) {
                      return LoadingButton(
                        onPressed: _handleSignup,
                        isLoading: authProvider.isLoading,
                        child: const Text('Create Account'),
                      );
                    },
                  ),

                  const SizedBox(height: 24),

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
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
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
                                        '[SignupScreen] Google Sign-In configuration error (SHA-1 not configured)',
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
                                        '[SignupScreen] Google Sign-In error: $message',
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

                  // Login Link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Already have an account? ',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      TextButton(
                        onPressed: () {
                          final authProvider = context.read<AuthProvider>();
                          if (authProvider.error != null) {
                            authProvider.clearError();
                          }
                          context.go('/login');
                        },
                        child: const Text('Sign In'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
