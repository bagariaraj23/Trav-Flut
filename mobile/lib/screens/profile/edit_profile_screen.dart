import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/providers/user_provider.dart';
import 'package:tripthread/services/media_service.dart';
import 'package:tripthread/widgets/custom_text_field.dart';
import 'package:tripthread/widgets/loading_button.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _bioController;
  bool? _isPrivate;
  bool _isUploadingPhoto = false;

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

  Future<void> _handlePhotoUpdate() async {
    final authProvider = context.read<AuthProvider>();
    final mediaService = context.read<MediaService>();
    final userProvider = context.read<UserProvider>();
    final currentUser = authProvider.currentUser;

    if (currentUser == null) return;

    setState(() {
      _isUploadingPhoto = true;
    });

    try {
      final file = await mediaService.pickImage();
      if (file == null) {
        setState(() {
          _isUploadingPhoto = false;
        });
        return;
      }

      final uploadedMedia = await mediaService.uploadMediaToCloudinary(
        file: file,
        usage: 'general',
      );

      if (uploadedMedia == null) {
        throw Exception('Failed to upload avatar');
      }

      final success = await userProvider.updateProfile(
        userId: currentUser.id,
        avatarUrl: uploadedMedia.url,
      );

      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update profile photo.'),
            backgroundColor: Colors.red,
          ),
        );
      } else if (success && mounted) {
        final updatedUser = userProvider.getUser(currentUser.id);
        if (updatedUser != null) {
          authProvider.updateUser(updatedUser);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile photo updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating profile photo: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingPhoto = false;
        });
      }
    }
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

      if (mounted) {
        context.go(from);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/home');
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Edit Profile'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/home');
              }
            },
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
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primary,
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
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: IconButton(
                            icon: _isUploadingPhoto
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Icon(
                                    Icons.camera_alt,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                            onPressed: _isUploadingPhoto
                                ? null
                                : _handlePhotoUpdate,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
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
                  textCapitalization: TextCapitalization.words,
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
      ),
    );
  }
}
