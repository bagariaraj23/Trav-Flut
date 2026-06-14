import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:tripthread/models/user.dart';
import 'package:tripthread/providers/chat_provider.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/services/api_service.dart';
import 'package:tripthread/utils/avatar_utils.dart';

/// Screen to start a new DM: pick a user (from following), create conversation, then open chat.
class NewConversationScreen extends StatefulWidget {
  const NewConversationScreen({super.key});

  @override
  State<NewConversationScreen> createState() => _NewConversationScreenState();
}

class _NewConversationScreenState extends State<NewConversationScreen> {
  List<User> _users = [];
  bool _loading = true;
  String? _error;
  String? _creatingForUserId;
  bool _groupMode = false;
  bool _creatingGroup = false;
  final Set<String> _selectedUserIds = <String>{};
  final TextEditingController _groupNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadUsers());
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    final auth = context.read<AuthProvider>();
    final currentUser = auth.currentUser;
    if (currentUser == null) {
      setState(() {
        _loading = false;
        _error = 'Please sign in';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<ApiService>();
    final res = await api.getFollowing(currentUser.id, limit: 100);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _users = res.data!.users;
        _error = res.error;
      } else {
        _error = res.error ?? 'Could not load users';
      }
    });
  }

  Future<void> _startChatWith(User user) async {
    final chat = context.read<ChatProvider>();
    setState(() => _creatingForUserId = user.id);
    final conv = await chat.createConversation(
      type: 'DM',
      participantIds: [user.id],
    );
    if (!mounted) return;
    setState(() => _creatingForUserId = null);
    if (conv != null) {
      context.pop();
      context.push('/chat/${conv.id}');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(chat.error ?? 'Failed to start conversation')),
      );
    }
  }

  void _toggleGroupMode() {
    setState(() {
      _groupMode = !_groupMode;
      _selectedUserIds.clear();
      _groupNameController.clear();
    });
  }

  void _toggleUserSelection(User user) {
    setState(() {
      if (_selectedUserIds.contains(user.id)) {
        _selectedUserIds.remove(user.id);
      } else {
        _selectedUserIds.add(user.id);
      }
    });
  }

  Future<void> _createGroupConversation() async {
    if (_selectedUserIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least 1 user to create a group')),
      );
      return;
    }

    final chat = context.read<ChatProvider>();
    setState(() => _creatingGroup = true);
    final conv = await chat.createConversation(
      type: 'GROUP',
      participantIds: _selectedUserIds.toList(),
      name: _groupNameController.text.trim().isEmpty
          ? null
          : _groupNameController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _creatingGroup = false);
    if (conv != null) {
      context.pop();
      context.push('/chat/${conv.id}');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(chat.error ?? 'Failed to create group conversation')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_groupMode ? 'New group' : 'New chat'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(_groupMode ? Icons.person : Icons.group_add),
            tooltip: _groupMode ? 'Switch to DM' : 'Create group',
            onPressed: _creatingGroup ? null : _toggleGroupMode,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _users.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: _loadUsers,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _users.isEmpty
                  ? const Center(
                      child: Text(
                        'Follow someone to start a chat.\nThey will appear here.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : Column(
                      children: [
                        if (_groupMode)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                            child: Column(
                              children: [
                                TextField(
                                  controller: _groupNameController,
                                  decoration: const InputDecoration(
                                    labelText: 'Group name (optional)',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Selected: ${_selectedUserIds.length} (min 1)',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _users.length,
                            itemBuilder: (context, index) {
                              final user = _users[index];
                              final displayName =
                                  user.name ?? user.username ?? user.email;
                              final avatarInitial = AvatarUtils.initialsFromName(
                                user.name ?? user.username ?? '',
                              );
                              final avatarColor = AvatarUtils.colorForKey(user.id);
                              final creating = _creatingForUserId == user.id;
                              final selected = _selectedUserIds.contains(user.id);
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: avatarColor,
                                  backgroundImage: user.avatarUrl != null
                                      ? CachedNetworkImageProvider(user.avatarUrl!)
                                      : null,
                                  child: user.avatarUrl == null
                                      ? Text(
                                          avatarInitial,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        )
                                      : null,
                                ),
                                title: Text(displayName),
                                subtitle: user.username != null
                                    ? Text('@${user.username}')
                                    : null,
                                trailing: _groupMode
                                    ? Checkbox(
                                        value: selected,
                                        onChanged: _creatingGroup
                                            ? null
                                            : (_) => _toggleUserSelection(user),
                                      )
                                    : creating
                                        ? const SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          )
                                        : null,
                                onTap: _groupMode
                                    ? (_creatingGroup
                                        ? null
                                        : () => _toggleUserSelection(user))
                                    : (creating ? null : () => _startChatWith(user)),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
      floatingActionButton: _groupMode
          ? FloatingActionButton.extended(
              onPressed: _creatingGroup ? null : _createGroupConversation,
              label: _creatingGroup
                  ? const Text('Creating...')
                  : Text('Create group (${_selectedUserIds.length})'),
              icon: _creatingGroup
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.group_add),
            )
          : null,
    );
  }
}
