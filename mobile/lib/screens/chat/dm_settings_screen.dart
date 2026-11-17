import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/models/chat_conversation.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/providers/chat_provider.dart';
import 'package:tripthread/services/api_service.dart';
import 'package:tripthread/utils/app_layout.dart';
import 'package:tripthread/utils/chat_navigation.dart';
import 'package:tripthread/widgets/chat/chat_avatar.dart';
import 'package:tripthread/screens/chat/group_settings_screen.dart';
import 'package:tripthread/widgets/chat/conversation_media_strip.dart';
import 'package:tripthread/screens/settings/help_faq_screen.dart';
import 'package:tripthread/widgets/safety/safety_actions.dart';

class DmSettingsScreen extends StatefulWidget {
  const DmSettingsScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  State<DmSettingsScreen> createState() => _DmSettingsScreenState();
}

class _DmSettingsScreenState extends State<DmSettingsScreen> {
  String? _outgoing;
  String? _incoming;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await context.read<ChatProvider>().ensureConversationLoaded(
            widget.conversationId,
          );
      await _loadPair();
    });
  }

  ChatParticipant? _other(ChatConversationSummary conversation, String myId) {
    for (final person in conversation.participants) {
      if (person.userId != myId) return person;
    }
    return null;
  }

  Future<void> _loadPair() async {
    final chat = context.read<ChatProvider>();
    final myId = context.read<AuthProvider>().currentUser?.id ?? '';
    ChatConversationSummary? conversation;
    for (final item in chat.conversations) {
      if (item.id == widget.conversationId) conversation = item;
    }
    final other = conversation == null ? null : _other(conversation, myId);
    if (other == null) return;
    final response = await context.read<ApiService>().getSafetyPair(other.userId);
    if (!mounted || response.data == null) return;
    setState(() {
      _outgoing = response.data!['outgoing'] as String?;
      _incoming = response.data!['incoming'] as String?;
    });
  }

  Future<void> _set(String userId, String action) async {
    setState(() => _busy = true);
    final response = await context.read<ApiService>().setSafety(userId, action);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!response.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(response.error ?? 'Could not update')),
      );
      return;
    }
    await _loadPair();
  }

  Future<void> _clear(String userId) async {
    setState(() => _busy = true);
    final response = await context.read<ApiService>().clearSafety(userId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!response.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(response.error ?? 'Could not update')),
      );
      return;
    }
    await _loadPair();
  }

  @override
  Widget build(BuildContext context) {
    final myId = context.watch<AuthProvider>().currentUser?.id ?? '';
    final chat = context.watch<ChatProvider>();
    ChatConversationSummary? conversation;
    for (final item in chat.conversations) {
      if (item.id == widget.conversationId) conversation = item;
    }
    final other = conversation == null ? null : _other(conversation, myId);
    final name = other?.name?.trim().isNotEmpty == true
        ? other!.name!
        : (other?.username ?? 'Chat');
    final theyClosed = _incoming == 'BLOCK' || _incoming == 'RESTRICT';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        leaveChatSettings(context, widget.conversationId);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Chat details'),
          actions: [
            IconButton(
              tooltip: 'What Restrict and Block do',
              onPressed: () => showSafetyInfo(context),
              icon: const Icon(Icons.info_outline),
            ),
          ],
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => leaveChatSettings(context, widget.conversationId),
          ),
        ),
        body: other == null
            ? const Center(child: CircularProgressIndicator())
            : AppLayout.reading(
                context: context,
                child: ListView(
                  children: [
                    const SizedBox(height: 24),
                    Center(
                      child: ChatAvatar(
                        radius: 48,
                        avatarUrl: other.avatarUrl,
                        name: name,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        name,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    if (_incoming != 'BLOCK')
                      ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: const Text('View profile'),
                        onTap: () => context.push('/profile/${other.userId}'),
                      ),
                    if (theyClosed)
                      ListTile(
                        title: Text(
                          "You can't message this person.",
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                      ),
                    SafetyChoiceList(
                      choices: safetyChoices(_outgoing),
                      enabled: !_busy,
                      onSelected: (choice) {
                        if (choice.clears) {
                          _clear(other.userId);
                        } else {
                          _set(other.userId, choice.action!);
                        }
                      },
                    ),
                    ConversationMediaStrip(conversationId: widget.conversationId),
                  ],
                ),
              ),
      ),
    );
  }
}

class ChatSettingsScreen extends StatefulWidget {
  const ChatSettingsScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  State<ChatSettingsScreen> createState() => _ChatSettingsScreenState();
}

class _ChatSettingsScreenState extends State<ChatSettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ChatProvider>().ensureConversationLoaded(widget.conversationId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    ChatConversationSummary? conversation;
    for (final item in chat.conversations) {
      if (item.id == widget.conversationId) conversation = item;
    }
    if (conversation == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (conversation.type == 'DM') {
      return DmSettingsScreen(conversationId: widget.conversationId);
    }
    return GroupSettingsScreen(conversationId: widget.conversationId);
  }
}
