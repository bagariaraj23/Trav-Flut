import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/providers/user_provider.dart';
import 'package:tripthread/widgets/custom_text_field.dart';
import 'package:tripthread/widgets/loading_button.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({Key? key}) : super(key: key);

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _bioController;
  bool? _isPrivate;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().currentUser;
    _nameController = TextEditingController(text: user?.name ?? '');
    _usernameController = TextEditingController(text: user?.username ?? '');
    _bioController = TextEditingController(text: user?.bio ?? '');
    _isPrivate = user?.isPrivate ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    final userProvider = context.read<UserProvider>();
    final currentUser = authProvider.currentUser;

    if (currentUser == null) return;

    final success = await userProvider.updateProfile(
      userId: currentUser.id,
      name: _nameController.text.trim(),
      username: _usernameController.text.trim().isEmpty
          ? null
          : _usernameController.text.trim(),
      bio: _bioController.text.trim().isEmpty
          ? null
          : _bioController.text.trim(),
      isPrivate: _isPrivate,
    );

    if (success && mounted) {
      // Update auth provider with new user data
      final updatedUser = userProvider.getUser(currentUser.id);
      if (updatedUser != null) {
        authProvider.updateUser(updatedUser);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully')),
      );

      // Use the same explicit navigation pattern
      final extra = GoRouterState.of(context).extra;
      final from = (extra is Map && extra['from'] != null)
          ? extra['from'] as String
          : '/home';

      context.go(from);
    }
  }

  @override
  Widget build(BuildContext context) {
    final extra = GoRouterState.of(context).extra;
    final authProvider = context.read<AuthProvider>();
    final from = (extra is Map && extra['from'] != null)
        ? extra['from'] as String
        : '/profile/${authProvider.currentUser?.id}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          Consumer<UserProvider>(
            builder: (context, userProvider, child) {
              return LoadingButton(
                onPressed: _handleSave,
                isLoading: userProvider.isLoading,
                style: TextButton.styleFrom(),
                child: const Text('Save'),
              );
            },
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Profile Picture Section
              Center(
                child: Stack(
                  children: [
                    Consumer<AuthProvider>(
                      builder: (context, authProvider, child) {
                        final user = authProvider.currentUser;
                        return CircleAvatar(
                          radius: 50,
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          backgroundImage: user?.avatarUrl != null
                              ? NetworkImage(user!.avatarUrl!)
                              : null,
                          child: user?.avatarUrl == null
                              ? Text(
                                  user?.name?.substring(0, 1).toUpperCase() ??
                                      'U',
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                )
                              : null,
                        );
                      },
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 20,
                          ),
                          onPressed: () {
                            // TODO: Implement image picker
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Image upload coming soon'),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Name Field
              CustomTextField(
                controller: _nameController,
                label: 'Full Name',
                prefixIcon: Icons.person_outlined,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Name is required';
                  }
                  if (value.trim().length < 2) {
                    return 'Name must be at least 2 characters';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Username Field
              CustomTextField(
                controller: _usernameController,
                label: 'Username',
                prefixIcon: Icons.alternate_email,
                validator: (value) {
                  if (value != null && value.isNotEmpty && value.length < 3) {
                    return 'Username must be at least 3 characters';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Bio Field
              CustomTextField(
                controller: _bioController,
                label: 'Bio',
                prefixIcon: Icons.info_outlined,
                maxLines: 3,
                maxLength: 500,
                validator: (value) {
                  if (value != null && value.length > 500) {
                    return 'Bio must be less than 500 characters';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 24),

              // Error Message
              Consumer<UserProvider>(
                builder: (context, userProvider, child) {
                  if (userProvider.error != null) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .error
                            .withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .error
                              .withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        userProvider.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 14,
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),

              // Privacy Toggle
              Card(
                child: ListTile(
                  leading: Icon(
                    _isPrivate == true
                        ? Icons.lock_outlined
                        : Icons.public_outlined,
                  ),
                  title: const Text('Private Account'),
                  subtitle: Text(
                    _isPrivate == true
                        ? 'Only followers can see your trips'
                        : 'Anyone can see your trips',
                  ),
                  trailing: Switch(
                    value: _isPrivate ?? false,
                    onChanged: (value) {
                      setState(() {
                        _isPrivate = value;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            value
                                ? 'Profile set to private'
                                : 'Profile set to public',
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
