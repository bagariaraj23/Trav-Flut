import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:tripthread/models/chat_conversation.dart';
import 'package:tripthread/providers/chat_provider.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/utils/avatar_utils.dart';
import 'package:tripthread/widgets/chat/chat_avatar.dart';

class ConversationListScreen extends StatefulWidget {
  final String? tripId;

  const ConversationListScreen({super.key, this.tripId});

  @override
  State<ConversationListScreen> createState() => _ConversationListScreenState();
}

class _ConversationListScreenState extends State<ConversationListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final chat = context.read<ChatProvider>();
      await chat.loadConversations(tripId: widget.tripId);
      if (!mounted || widget.tripId == null) return;
      // For trip-scoped views, skip the list and go directly to the chat screen
      // (the TRIP conversation was created/fetched above). Use pushReplacement so
      // the back button from the chat screen returns to the trip detail, not here.
      final tripConvs = chat.getConversationsForTrip(widget.tripId!);
      if (tripConvs.length == 1) {
        context.pushReplacement('/chat/${tripConvs.first.id}');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.tripId == null ? 'Messages' : 'Trip chat'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: widget.tripId == null
            ? [
                IconButton(
                  icon: const Icon(Icons.add_comment),
                  tooltip: 'New chat',
                  onPressed: () => context.push('/chat/new'),
                ),
              ]
            : null,
      ),
      body: Consumer<ChatProvider>(
        builder: (context, chat, _) {
          // Use trip-filtered list when scoped to a trip; full list otherwise.
          final list = widget.tripId != null
              ? chat.getConversationsForTrip(widget.tripId!)
              : chat.conversations;

          if (chat.loadingConversations && list.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (chat.error != null && list.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(chat.error!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => chat.loadConversations(tripId: widget.tripId),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          if (list.isEmpty) {
            return const Center(
              child: Text('No conversations yet.\nStart a trip or message a friend.'),
            );
          }
          return RefreshIndicator(
            onRefresh: () => chat.loadConversations(tripId: widget.tripId),
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, index) {
                final c = list[index];
                return _ConversationTile(
                  conversation: c,
                  currentUserId: context.read<AuthProvider>().currentUser?.id ?? '',
                  onTap: () => context.push('/chat/${c.id}'),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final ChatConversationSummary conversation;
  final String currentUserId;
  final VoidCallback onTap;

  const _ConversationTile({
    required this.conversation,
    required this.currentUserId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final other = conversation.participants
        .where((p) => p.userId != currentUserId)
        .toList();
    final title = conversation.name ??
        (conversation.type == 'DM' && other.isNotEmpty
            ? (other.first.name ?? other.first.username ?? 'User')
            : 'Conversation');
    final subtitle = conversation.lastMessage?.content ?? '';
    final time = conversation.lastMessage?.createdAt != null
        ? _formatTime(conversation.lastMessage!.createdAt)
        : '';
    final unread = conversation.unreadCount > 0;
    final isGroup = conversation.type == 'GROUP';
    final isTrip = conversation.type == 'TRIP';
    final otherDisplayName = other.isNotEmpty
        ? (other.first.name ?? other.first.username ?? '')
        : '';
    final avatarLabel = isGroup
        ? (conversation.name ?? 'Group')
        : isTrip
            ? 'Trip'
            : otherDisplayName;
    final avatarInitial = AvatarUtils.initialsFromName(avatarLabel);
    final avatarColor = AvatarUtils.colorForKey(
      isGroup || isTrip ? conversation.id : (other.isNotEmpty ? other.first.userId : ''),
    );

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: avatarColor,
        backgroundImage: (isGroup || isTrip)
            ? (conversation.avatarUrl != null && conversation.avatarUrl!.isNotEmpty
                ? CachedNetworkImageProvider(conversation.avatarUrl!)
                : null)
            : (other.isNotEmpty && other.first.avatarUrl != null
                ? CachedNetworkImageProvider(other.first.avatarUrl!)
                : null),
        child: (isGroup || isTrip)
            ? (conversation.avatarUrl == null || conversation.avatarUrl!.isEmpty
                ? Text(
                    avatarInitial,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  )
                : null)
            : (other.isEmpty || other.first.avatarUrl == null
                ? Text(
                    avatarInitial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : null),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: unread ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          if (isGroup || isTrip)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                isGroup ? 'GROUP' : 'TRIP',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
        ],
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: unread ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (time.isNotEmpty) Text(time, style: Theme.of(context).textTheme.bodySmall),
          if (unread)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${conversation.unreadCount}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
        ],
      ),
      onTap: onTap,
    );
  }

  String _formatTime(String iso) {
    try {
      final d = DateTime.parse(iso);
      final n = DateTime.now();
      if (d.year == n.year && d.month == n.month && d.day == n.day) {
        return DateFormat.Hm().format(d);
      }
      if (d.year == n.year && d.month == n.month && d.day == n.day - 1) {
        return 'Yesterday';
      }
      return DateFormat.Md().format(d);
    } catch (_) {
      return '';
    }
  }
}
