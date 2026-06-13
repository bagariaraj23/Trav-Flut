import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:tripthread/models/chat_conversation.dart';
import 'package:tripthread/providers/chat_provider.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/services/media_service.dart';
import 'package:tripthread/utils/avatar_utils.dart';
import 'package:tripthread/widgets/chat/chat_avatar.dart';
import 'package:tripthread/services/api_service.dart';
import 'package:tripthread/utils/user_display_labels.dart';

class GroupSettingsScreen extends StatefulWidget {
  final String conversationId;

  const GroupSettingsScreen({super.key, required this.conversationId});

  @override
  State<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> {
  bool _uploadingAvatar = false;

  ChatConversationSummary? _currentConversation(ChatProvider chat) {
    for (final c in chat.conversations) {
      if (c.id == widget.conversationId) return c;
    }
    return null;
  }

  Future<void> _changeAvatar() async {
    try {
      final mediaService = context.read<MediaService>();
      final file = await mediaService.pickImage();
      if (file == null) return;

      setState(() => _uploadingAvatar = true);

      final media = await mediaService.uploadMediaToCloudinary(
        file: file,
        usage: 'group_avatar',
      );

      if (media != null && mounted) {
        final chat = context.read<ChatProvider>();
        final ok = await chat.updateGroupInfo(
          widget.conversationId,
          avatarUrl: media.url,
        );
        if (!ok && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(chat.error ?? 'Failed to update avatar')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting/uploading image: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _uploadingAvatar = false);
      }
    }
  }

  Future<void> _removeAvatar() async {
    try {
      setState(() => _uploadingAvatar = true);
      final chat = context.read<ChatProvider>();
      final ok = await chat.updateGroupInfo(
        widget.conversationId,
        avatarUrl: '',
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(chat.error ?? 'Failed to remove avatar')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _uploadingAvatar = false);
      }
    }
  }

  Future<void> _showEditNameDialog(String currentName) async {
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Group Name'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter group name',
          ),
          maxLength: 100,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty && newName != currentName && mounted) {
      final chat = context.read<ChatProvider>();
      final ok = await chat.updateGroupInfo(widget.conversationId, name: newName);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(chat.error ?? 'Failed to update group name')),
        );
      }
    }
  }

  Future<void> _promoteMember(ChatParticipant participant) async {
    final chat = context.read<ChatProvider>();
    final ok = await chat.promoteAdmin(widget.conversationId, participant.userId);
    if (mounted) {
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${participant.name ?? participant.username} promoted to Admin')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(chat.error ?? 'Failed to promote member')),
        );
      }
    }
  }

  Future<void> _removeMember(ChatParticipant participant) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text('Are you sure you want to remove ${participant.name ?? participant.username} from this group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final chat = context.read<ChatProvider>();
      final ok = await chat.removeParticipant(widget.conversationId, participant.userId);
      if (mounted) {
        if (ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${participant.name ?? participant.username} removed')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(chat.error ?? 'Failed to remove member')),
          );
        }
      }
    }
  }

  void _showAddParticipantDialog(ChatConversationSummary conversation) {
    showDialog(
      context: context,
      builder: (context) => AddParticipantDialog(
        conversationId: widget.conversationId,
        currentParticipants: conversation.participants,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.watch<AuthProvider>().currentUser?.id ?? '';
    final chat = context.watch<ChatProvider>();
    final conversation = _currentConversation(chat);

    if (conversation == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Group Settings'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final other = conversation.participants
        .where((p) => p.userId != currentUserId)
        .toList();
    final name = conversation.name ?? 'Group Chat';
    final hasImage = conversation.avatarUrl != null && conversation.avatarUrl!.isNotEmpty;

    final currentUserParticipant = conversation.participants.firstWhere(
      (p) => p.userId == currentUserId,
      orElse: () => const ChatParticipant(id: '', userId: '', role: 'MEMBER'),
    );
    final isViewerAdmin = currentUserParticipant.role == 'ADMIN';

    final avatarLabel = name;
    final avatarInitial = AvatarUtils.initialsFromName(avatarLabel);
    final avatarColor = AvatarUtils.colorForKey(conversation.id);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Details'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 24),
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: avatarColor,
                    backgroundImage: hasImage
                        ? CachedNetworkImageProvider(conversation.avatarUrl!)
                        : null,
                    child: !hasImage
                        ? Text(
                            avatarInitial,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  if (isViewerAdmin)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: CircleAvatar(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        child: _uploadingAvatar
                            ? const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : PopupMenuButton<String>(
                                icon: const Icon(Icons.edit, color: Colors.white),
                                onSelected: (val) {
                                  if (val == 'change') {
                                    _changeAvatar();
                                  } else if (val == 'remove') {
                                    _removeAvatar();
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'change',
                                    child: Text('Change Group Photo'),
                                  ),
                                  if (hasImage)
                                    const PopupMenuItem(
                                      value: 'remove',
                                      child: Text('Remove Photo'),
                                    ),
                                ],
                              ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      name,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isViewerAdmin) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _showEditNameDialog(name),
                      tooltip: 'Edit name',
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${conversation.participants.length} members',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Members',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  if (isViewerAdmin)
                    TextButton.icon(
                      onPressed: () => _showAddParticipantDialog(conversation),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Member'),
                    ),
                ],
              ),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: conversation.participants.length,
              itemBuilder: (context, index) {
                final participant = conversation.participants[index];
                final pDisplayName = participant.name ?? participant.username ?? 'Unknown';
                final isMe = participant.userId == currentUserId;
                final isParticipantAdmin = participant.role == 'ADMIN';

                final pInitials = AvatarUtils.initialsFromName(pDisplayName);
                final pColor = AvatarUtils.colorForKey(participant.userId);

                return ListTile(
                  onTap: () => context.push('/profile/${participant.userId}'),
                  leading: CircleAvatar(
                    backgroundColor: pColor,
                    backgroundImage: participant.avatarUrl != null && participant.avatarUrl!.isNotEmpty
                        ? CachedNetworkImageProvider(participant.avatarUrl!)
                        : null,
                    child: participant.avatarUrl == null || participant.avatarUrl!.isEmpty
                        ? Text(
                            pInitials,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                          )
                        : null,
                  ),
                  title: Text(
                    isMe ? 'You' : pDisplayName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '@${participant.username}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isParticipantAdmin)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Admin',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (isViewerAdmin && !isMe)
                        PopupMenuButton<String>(
                          onSelected: (val) {
                            if (val == 'promote') {
                              _promoteMember(participant);
                            } else if (val == 'remove') {
                              _removeMember(participant);
                            }
                          },
                          itemBuilder: (context) => [
                            if (!isParticipantAdmin)
                              const PopupMenuItem(
                                value: 'promote',
                                child: Text('Promote to Admin'),
                              ),
                            const PopupMenuItem(
                              value: 'remove',
                              child: Text('Remove from Group'),
                            ),
                          ],
                        ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class AddParticipantDialog extends StatefulWidget {
  final String conversationId;
  final List<ChatParticipant> currentParticipants;

  const AddParticipantDialog({
    super.key,
    required this.conversationId,
    required this.currentParticipants,
  });

  @override
  State<AddParticipantDialog> createState() => _AddParticipantDialogState();
}

class _AddParticipantDialogState extends State<AddParticipantDialog> {
  final _searchController = TextEditingController();
  Timer? _debounceTimer;
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    _debounceTimer?.cancel();
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _isSearching = true;
      _error = null;
    });
    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      try {
        final apiService = context.read<ApiService>();
        final response = await apiService.searchUsers(search: query, limit: 10);
        if (!mounted) return;
        if (response.success && response.data != null) {
          setState(() {
            _searchResults = response.data!;
            _isSearching = false;
          });
        } else {
          setState(() {
            _searchResults = [];
            _isSearching = false;
            _error = response.error ?? 'Failed to search users';
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _searchResults = [];
            _isSearching = false;
            _error = 'Error searching: $e';
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _addMember(String userId, String username) async {
    final chat = context.read<ChatProvider>();
    final ok = await chat.addParticipant(widget.conversationId, userId);
    if (mounted) {
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$username added to group')),
        );
        Navigator.pop(context); // Close dialog
      } else {
        setState(() {
          _error = chat.error ?? 'Failed to add member';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Member'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search by name or username...',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            if (_isSearching)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: CircularProgressIndicator(),
                ),
              ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (!_isSearching && _searchResults.isEmpty && _searchController.text.isNotEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No users found'),
              ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _searchResults.length,
                itemBuilder: (context, index) {
                  final user = _searchResults[index];
                  final userId = user['id'] as String;
                  final username = user['username'] as String? ?? '';
                  final name = user['name'] as String? ?? '';
                  final avatarUrl = user['avatarUrl'] as String?;

                  final isAlreadyMember = widget.currentParticipants.any((p) => p.userId == userId);

                  final initials = AvatarUtils.initialsFromName(name.isNotEmpty ? name : username);
                  final color = AvatarUtils.colorForKey(userId);

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: color,
                      backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                          ? CachedNetworkImageProvider(avatarUrl)
                          : null,
                      child: avatarUrl == null || avatarUrl.isEmpty
                          ? Text(
                              initials,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                            )
                          : null,
                    ),
                    title: Text(name.isNotEmpty ? name : username),
                    subtitle: Text('@$username'),
                    trailing: isAlreadyMember
                        ? const Text('Member', style: TextStyle(color: Colors.grey))
                        : IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () => _addMember(userId, username),
                          ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
