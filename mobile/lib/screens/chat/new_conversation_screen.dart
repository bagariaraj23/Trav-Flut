import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:tripthread/models/user.dart';
import 'package:tripthread/providers/chat_provider.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/services/api_service.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadUsers());
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New chat'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
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
                  : ListView.builder(
                      itemCount: _users.length,
                      itemBuilder: (context, index) {
                        final user = _users[index];
                        final displayName =
                            user.name ?? user.username ?? user.email;
                        final creating = _creatingForUserId == user.id;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.grey[300],
                            backgroundImage: user.avatarUrl != null
                                ? CachedNetworkImageProvider(user.avatarUrl!)
                                : null,
                            child: user.avatarUrl == null
                                ? Text(
                                    (displayName.isNotEmpty
                                            ? displayName[0]
                                            : '?')
                                        .toUpperCase(),
                                  )
                                : null,
                          ),
                          title: Text(displayName),
                          subtitle:
                              user.username != null ? Text('@${user.username}') : null,
                          trailing: creating
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : null,
                          onTap: creating ? null : () => _startChatWith(user),
                        );
                      },
                    ),
    );
  }
}
