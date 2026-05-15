import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/utils/validators.dart';
import 'package:tripthread/widgets/custom_text_field.dart';
import 'package:tripthread/widgets/loading_button.dart';

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _confirmPasswordController;
  late final TextEditingController _nameController;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().currentUser;
    _usernameController = TextEditingController(text: user?.username ?? '');
    _passwordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
    _nameController = TextEditingController(text: user?.name ?? '');
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    final authProvider = context.read<AuthProvider>();
    var rawUsername = _usernameController.text.trim();
    while (rawUsername.startsWith('@')) {
      rawUsername = rawUsername.substring(1).trim();
    }
    final username = Validators.normalizeUsernameToAscii(rawUsername);
    final success = await authProvider.completeProfile(
      username: username,
      password: _passwordController.text,
      name: _nameController.text.trim().isEmpty
          ? null
          : _nameController.text.trim(),
    );
    if (success && mounted) {
      context.go('/home');
    } else if (mounted) {
      authProvider.markErrorAsShown();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Complete your profile'),
            content: const Text(
              'You must set a username and password to continue. You can sign in with Google or email later.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Stay'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Exit app'),
              ),
            ],
          ),
        );
        if (leave == true && mounted) {
          context.read<AuthProvider>().forceLogout(
              message: 'Please complete your profile to use the app.');
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Complete your profile'),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  Text(
                    'Set a username and password so you can also sign in with email later.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  CustomTextField(
                    controller: _usernameController,
                    label: 'Username',
                    prefixIcon: Icons.alternate_email,
                    validator: (value) {
                      var t = value?.trim() ?? '';
                      while (t.startsWith('@')) {
                        t = t.substring(1).trim();
                      }
                      final normalized = Validators.normalizeUsernameToAscii(t);
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
                    maxLength: 30,
                    errorMaxLines: 2,
                  ),
                  const SizedBox(height: 16),
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
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    validator: (value) {
                      final v = value ?? '';
                      if (v.isEmpty) return 'Password is required';
                      if (v.length < 8) {
                        return 'Password must be at least 8 characters';
                      }
                      if (!RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).*$')
                          .hasMatch(v)) {
                        return 'Password must contain lowercase, uppercase, and a number';
                      }
                      return null;
                    },
                    errorMaxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  CustomTextField(
                    controller: _confirmPasswordController,
                    label: 'Confirm password',
                    obscureText: _obscureConfirm,
                    prefixIcon: Icons.lock_outlined,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please confirm your password';
                      }
                      if (value != _passwordController.text) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                    errorMaxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  CustomTextField(
                    controller: _nameController,
                    label: 'Name (optional)',
                    prefixIcon: Icons.person_outlined,
                    textCapitalization: TextCapitalization.words,
                    validator: (value) {
                      if (value == null || value.isEmpty) return null;
                      if (value.trim().length < 2) {
                        return 'Name must be at least 2 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  Consumer<AuthProvider>(
                    builder: (context, authProvider, _) {
                      return AnimatedBuilder(
                        animation: authProvider.uiNotifier,
                        builder: (context, __) {
                          if (authProvider.error == null) {
                            return const SizedBox.shrink();
                          }
                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .error
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .error
                                    .withValues(alpha: 0.3),
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
                                      color:
                                          Theme.of(context).colorScheme.error,
                                      fontSize: 14,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.visible,
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.close,
                                    color: Theme.of(context).colorScheme.error,
                                    size: 18,
                                  ),
                                  onPressed: () => authProvider.clearError(),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                  Consumer<AuthProvider>(
                    builder: (context, authProvider, _) => LoadingButton(
                      onPressed: _handleSubmit,
                      isLoading: authProvider.isLoading,
                      child: const Text('Complete profile'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
