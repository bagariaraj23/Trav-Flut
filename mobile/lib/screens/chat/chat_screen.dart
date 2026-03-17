import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:tripthread/models/chat_message.dart';
import 'package:tripthread/providers/chat_provider.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/services/media_service.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;

  const ChatScreen({super.key, required this.conversationId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _loadingMore = false;
  ChatMessageModel? _replyingTo;
  List<File> _selectedMedia = [];
  bool _uploadingMedia = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final chat = context.read<ChatProvider>();
      await chat.loadMessages(widget.conversationId);
      chat.markRead(widget.conversationId);
      _scrollController.addListener(_onScroll);
    });
  }

  void _onScroll() {
    if (_loadingMore) return;
    final chat = context.read<ChatProvider>();
    if (!chat.hasMoreMessages(widget.conversationId)) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadingMore = true;
      chat.loadMessages(widget.conversationId, loadMore: true).then((_) {
        if (mounted) _loadingMore = false;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _cancelReply() {
    setState(() {
      _replyingTo = null;
    });
  }

  void _startReply(ChatMessageModel msg) {
    setState(() {
      _replyingTo = msg;
    });
  }

  void _cancelMedia(int index) {
    setState(() {
      _selectedMedia.removeAt(index);
    });
  }

  Future<void> _pickMedia() async {
    try {
      final mediaService = Provider.of<MediaService>(context, listen: false);
      final file = await mediaService.pickFile();
      if (file != null) {
        setState(() {
          _selectedMedia.add(file);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick media: $e')),
        );
      }
    }
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty && _selectedMedia.isEmpty) return;

    setState(() {
      _uploadingMedia = true;
    });

    try {
      final chat = context.read<ChatProvider>();
      final mediaService = Provider.of<MediaService>(context, listen: false);
      List<String>? attachmentMediaIds;

      // Upload media if any selected
      if (_selectedMedia.isNotEmpty) {
        attachmentMediaIds = [];
        for (final file in _selectedMedia) {
          try {
            final media = await mediaService.uploadMediaToCloudinary(
              file: file,
              usage: 'chat',
            );
            if (media != null) {
              attachmentMediaIds.add(media.id);
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to upload media: $e')),
              );
            }
          }
        }
      }

      // If uploads failed and there's no text, do not attempt to send an empty message.
      final hasAttachments = attachmentMediaIds != null && attachmentMediaIds.isNotEmpty;
      if (!hasAttachments && text.isEmpty) {
        setState(() {
          _uploadingMedia = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not upload media. Message not sent.')),
          );
        }
        return;
      }

      // Send message with reply and attachments
      await chat.sendMessage(
        widget.conversationId,
        text,
        replyToMessageId: _replyingTo?.id,
        attachmentMediaIds: attachmentMediaIds?.isNotEmpty == true
            ? attachmentMediaIds
            : null,
      );

      // Clear input
      _textController.clear();
      setState(() {
        _replyingTo = null;
        _selectedMedia.clear();
        _uploadingMedia = false;
      });
    } catch (e) {
      setState(() {
        _uploadingMedia = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.watch<AuthProvider>().currentUser?.id ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Consumer<ChatProvider>(
              builder: (context, chat, _) {
                final messages = chat.getMessages(widget.conversationId);
                final typingUsers = chat.getTypingUsers(widget.conversationId);
                if (messages.isEmpty && chat.isLoadingMessages(widget.conversationId)) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (messages.isEmpty) {
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('No messages yet. Say hello!'),
                      if (typingUsers.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const _TypingIndicator(),
                      ],
                    ],
                  );
                }
                return Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        itemCount: messages.length +
                            (chat.hasMoreMessages(widget.conversationId) ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == messages.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                  child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )),
                            );
                          }
                          final msg = messages[index];
                          return Dismissible(
                            key: ValueKey('chat_msg_${msg.id}'),
                            direction: DismissDirection.endToStart, // swipe left
                            confirmDismiss: (_) async {
                              _startReply(msg);
                              return false; // don't actually dismiss
                            },
                            background: const SizedBox.shrink(),
                            secondaryBackground: Align(
                              alignment: Alignment.centerRight,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 24),
                                child: Icon(
                                  Icons.reply,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            child: _MessageBubble(
                              message: msg,
                              isMe: msg.senderId == currentUserId,
                            ),
                          );
                        },
                      ),
                    ),
                    if (typingUsers.isNotEmpty) const _TypingIndicator(),
                  ],
                );
              },
            ),
          ),
          // Reply preview bar
          if (_replyingTo != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _replyingTo!.sender.name ?? _replyingTo!.sender.username ?? 'Unknown',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _replyingTo!.content.isNotEmpty
                              ? _replyingTo!.content
                              : _replyingTo!.attachments.isNotEmpty
                                  ? '[${_replyingTo!.attachments.first.type}]'
                                  : 'Media',
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: _cancelReply,
                    tooltip: 'Cancel reply',
                  ),
                ],
              ),
            ),
          // Media preview
          if (_selectedMedia.isNotEmpty)
            Container(
              height: 100,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 1,
                  ),
                ),
              ),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _selectedMedia.length,
                itemBuilder: (context, index) {
                  final file = _selectedMedia[index];
                  return Container(
                    width: 90,
                    margin: const EdgeInsets.only(right: 8),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            file,
                            fit: BoxFit.cover,
                            width: 90,
                            height: 90,
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: CircleAvatar(
                            radius: 12,
                            backgroundColor: Colors.black54,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              iconSize: 16,
                              icon: const Icon(Icons.close, color: Colors.white),
                              onPressed: () => _cancelMedia(index),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          // Input area
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  onPressed: _uploadingMedia ? null : _pickMedia,
                  tooltip: 'Attach media',
                ),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    enabled: !_uploadingMedia,
                    decoration: const InputDecoration(
                      hintText: 'Message',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    maxLines: 3,
                    minLines: 1,
                    onChanged: (_) =>
                        context.read<ChatProvider>().sendTyping(widget.conversationId),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                if (_uploadingMedia)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  IconButton.filled(
                    onPressed: _send,
                    icon: const Icon(Icons.send),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Typing...',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessageModel message;
  final bool isMe;

  const _MessageBubble({
    required this.message,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final time = _formatTime(message.createdAt);
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          decoration: BoxDecoration(
            color: isMe
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Reply preview
              if (message.replyTo != null)
                Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border(
                      left: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 3,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Replying to ${message.replyTo!.senderId == message.senderId ? "yourself" : "message"}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        message.replyTo!.content,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontSize: 12,
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              if (message.content.isNotEmpty)
                Text(
                  message.content,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              if (message.attachments.isNotEmpty)
                ...message.attachments.map((a) {
                  if (a.type == 'IMAGE' || a.type == 'GIF') {
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: a.url,
                          fit: BoxFit.cover,
                          maxWidthDiskCache: 400,
                          maxHeightDiskCache: 400,
                        ),
                      ),
                    );
                  }
                  if (a.type == 'VIDEO') {
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        height: 200,
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CachedNetworkImage(
                              imageUrl: a.url,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: 200,
                            ),
                            const Icon(Icons.play_circle_outline, size: 48, color: Colors.white),
                          ],
                        ),
                      ),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('[${a.type}]', style: Theme.of(context).textTheme.bodySmall),
                  );
                }),
              const SizedBox(height: 4),
              Text(
                time,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
      ),
    );
  }

  String _formatTime(String iso) {
    try {
      final d = DateTime.parse(iso);
      return DateFormat.Hm().format(d);
    } catch (_) {
      return '';
    }
  }
}
