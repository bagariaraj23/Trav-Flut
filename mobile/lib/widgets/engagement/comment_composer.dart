import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/models/comment_user.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/providers/comment_provider.dart';
import 'package:tripthread/models/comment.dart';
import 'package:tripthread/services/api_service.dart';
import 'package:tripthread/utils/debouncer.dart';

class CommentComposer extends StatefulWidget {
  final String entityType;
  final String entityId;
  final String? parentCommentId;
  final Comment? parentComment;
  final VoidCallback? onCommentPosted;
  final VoidCallback? onCancel;

  const CommentComposer({
    super.key,
    required this.entityType,
    required this.entityId,
    this.parentCommentId,
    this.parentComment,
    this.onCommentPosted,
    this.onCancel,
  });

  @override
  State<CommentComposer> createState() => _CommentComposerState();
}

class _MentionCandidate {
  final String id;
  final String? username;
  final String? name;
  final String? avatarUrl;

  const _MentionCandidate({
    required this.id,
    this.username,
    this.name,
    this.avatarUrl,
  });

  String get display =>
      (username != null && username!.trim().isNotEmpty) ? '@$username' : (name ?? 'User');
}

const _kTripEveryoneMention = _MentionCandidate(
  id: '__trip_all__',
  username: 'all',
  name: 'Everyone on this trip',
);

class _CommentComposerState extends State<CommentComposer> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  bool _isSubmitting = false;
  final int _maxLength = 250;

  bool get _tripScopedForTag =>
      widget.entityType == 'TRIP_THREAD_ENTRY' ||
      widget.entityType == 'TRIP_FINAL_POST';

  final Debouncer _mentionDebouncer =
      Debouncer(delay: const Duration(milliseconds: 220));
  int? _mentionStart;
  String? _mentionQuery;
  bool _isMentionLoading = false;
  int _mentionRequestId = 0;
  List<_MentionCandidate> _mentionResults = const [];

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    _mentionDebouncer.dispose();
    super.dispose();
  }

  void _clearMentions() {
    if (_mentionStart == null &&
        _mentionQuery == null &&
        _mentionResults.isEmpty &&
        !_isMentionLoading) {
      return;
    }
    setState(() {
      _mentionStart = null;
      _mentionQuery = null;
      _mentionResults = const [];
      _isMentionLoading = false;
    });
  }

  bool _isWhitespace(String ch) => ch.trim().isEmpty;

  void _onComposerChanged(String _) {
    setState(() {}); // keep send button reactive
    _updateMentionQuery();
  }

  void _updateMentionQuery() {
    final selection = _textController.selection;
    final cursor = selection.baseOffset;
    final text = _textController.text;

    if (cursor < 0 || cursor > text.length) {
      _clearMentions();
      return;
    }

    final beforeCursor = text.substring(0, cursor);
    final at = beforeCursor.lastIndexOf('@');
    if (at == -1) {
      _clearMentions();
      return;
    }

    if (at > 0 && !_isWhitespace(beforeCursor[at - 1])) {
      // Avoid triggering on emails / mid-word '@'
      _clearMentions();
      return;
    }

    final rawQuery = beforeCursor.substring(at + 1);
    if (rawQuery.contains(RegExp(r'\s'))) {
      _clearMentions();
      return;
    }

    final query = rawQuery.trim();
    if (query.isEmpty) {
      // Don’t spam the API on just "@"
      _clearMentions();
      return;
    }

    // Update state immediately so the dropdown appears while we debounce-fetch.
    if (_mentionStart != at || _mentionQuery != query) {
      setState(() {
        _mentionStart = at;
        _mentionQuery = query;
      });
    }

    final int requestId = ++_mentionRequestId;
    _mentionDebouncer.run(() async {
      if (!mounted) return;

      setState(() => _isMentionLoading = true);
      try {
        final api = context.read<ApiService>();
        final resp = await api.searchUsers(
          search: query,
          page: 1,
          limit: 8,
          prioritizeFollowed: true,
        );

        if (!mounted || requestId != _mentionRequestId) return;

        List<_MentionCandidate> users = (resp.success ? (resp.data ?? const []) : const [])
            .whereType<Map<String, dynamic>>()
            .map(
              (u) => _MentionCandidate(
                id: (u['id'] ?? '').toString(),
                username: u['username']?.toString(),
                name: u['name']?.toString(),
                avatarUrl: u['avatarUrl']?.toString(),
              ),
            )
            .where((u) => u.id.isNotEmpty)
            .toList(growable: false);

        if (_tripScopedForTag &&
            _mentionQuery != null &&
            _mentionQuery!.toLowerCase() == 'all') {
          users = [_kTripEveryoneMention, ...users];
        }

        setState(() {
          _mentionResults = users;
          _isMentionLoading = false;
        });
      } catch (_) {
        if (!mounted || requestId != _mentionRequestId) return;
        setState(() {
          _mentionResults = const [];
          _isMentionLoading = false;
        });
      }
    });
  }

  void _insertMention(_MentionCandidate user) {
    final start = _mentionStart;
    final selection = _textController.selection;
    final cursor = selection.baseOffset;
    if (start == null || cursor < 0) return;

    final usernameOrName = (user.username != null && user.username!.trim().isNotEmpty)
        ? user.username!.trim()
        : (user.name ?? 'user').trim().replaceAll(RegExp(r'\s+'), '');

    final mentionText = '@$usernameOrName ';
    final fullText = _textController.text;

    final newText =
        '${fullText.substring(0, start)}$mentionText${fullText.substring(cursor)}';

    final newCursor = (start + mentionText.length).clamp(0, newText.length);

    _textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursor),
    );

    _clearMentions();
    _focusNode.requestFocus();
  }

  Future<void> _submitComment() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isSubmitting) return;

    setState(() => _isSubmitting = true);
    HapticFeedback.mediumImpact();

    try {
      final auth = context.read<AuthProvider>();
      final me = auth.currentUser;
      final provider = context.read<CommentProvider>();
      CommentUser? preview;
      if (me != null) {
        preview = CommentUser(
          id: me.id,
          username: me.username,
          name: me.name,
          avatarUrl: me.avatarUrl,
        );
      }
      await provider.createComment(
        widget.entityType,
        widget.entityId,
        text,
        widget.parentCommentId,
        currentUserId: me?.id,
        currentUserPreview: preview,
      );

      _textController.clear();
      widget.onCommentPosted?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to post comment: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CommentProvider>(
      builder: (context, provider, child) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;

        final entityKey = '${widget.entityType}:${widget.entityId}';
        final isCreating = provider.isCreating(entityKey);

        return Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 8,
          ),
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.parentComment != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.onSurface.withValues(
                      alpha: isDark ? 0.08 : 0.04,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.reply,
                        size: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Replying to ${widget.parentComment?.user?.displayName ?? 'user'}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: widget.onCancel,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
              if (_mentionStart != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colorScheme.onSurface.withValues(
                        alpha: isDark ? 0.18 : 0.10,
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Builder(
                    builder: (context) {
                      final hasResults = _mentionResults.isNotEmpty;
                      final shouldScroll = _mentionResults.length > 4;

                      final Widget content = _isMentionLoading
                        ? Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Searching…',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : (!hasResults
                            ? Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(
                                  'No users found',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                shrinkWrap: !shouldScroll,
                                physics: shouldScroll
                                    ? const BouncingScrollPhysics()
                                    : const NeverScrollableScrollPhysics(),
                                itemCount: _mentionResults.length,
                                separatorBuilder: (context, index) => Divider(
                                  height: 1,
                                  color: colorScheme.onSurface.withValues(
                                    alpha: isDark ? 0.12 : 0.08,
                                  ),
                                ),
                                itemBuilder: (context, index) {
                                  final user = _mentionResults[index];
                                  final subtitle = (user.username != null &&
                                          user.username!.trim().isNotEmpty)
                                      ? '@${user.username}'
                                      : null;
                                  return InkWell(
                                    onTap: () => _insertMention(user),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 16,
                                            backgroundImage: (user.avatarUrl !=
                                                        null &&
                                                    user.avatarUrl!
                                                        .trim()
                                                        .isNotEmpty)
                                                ? NetworkImage(user.avatarUrl!)
                                                : null,
                                            child: (user.avatarUrl == null ||
                                                    user.avatarUrl!
                                                        .trim()
                                                        .isEmpty)
                                                ? Text(
                                                    (user.name?.isNotEmpty ==
                                                                true
                                                            ? user.name!
                                                                .substring(0, 1)
                                                            : (user.username
                                                                        ?.isNotEmpty ==
                                                                    true)
                                                                ? user.username!
                                                                    .substring(0, 1)
                                                                : 'U')
                                                        .toUpperCase(),
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                    ),
                                                  )
                                                : null,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  user.name ??
                                                      user.username ??
                                                      'User',
                                                  style: theme
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                    color:
                                                        colorScheme.onSurface,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                if (subtitle != null)
                                                  Text(
                                                    subtitle,
                                                    style: theme
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                      color: colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ));

                      // If there are only a few items, let it size naturally.
                      // If there are many, cap the height and allow scrolling.
                      if (!shouldScroll) return content;

                      return ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: content,
                      );
                    },
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final textTheme = theme.textTheme;
                        
                        // Create base text styles with all required properties (fontSize and textBaseline for inherit: false)
                        final baseBodyLarge = textTheme.bodyLarge ?? const TextStyle(fontSize: 16, textBaseline: TextBaseline.alphabetic);
                        final baseBodyMedium = textTheme.bodyMedium ?? const TextStyle(fontSize: 14, textBaseline: TextBaseline.alphabetic);
                        final baseBodySmall = textTheme.bodySmall ?? const TextStyle(fontSize: 12, textBaseline: TextBaseline.alphabetic);
                        
                        // Ensure fontSize and textBaseline are preserved when setting inherit: false
                        final inputStyle = TextStyle(
                          fontSize: baseBodyLarge.fontSize ?? 16,
                          textBaseline: baseBodyLarge.textBaseline ?? TextBaseline.alphabetic,
                          color: baseBodyLarge.color,
                          fontFamily: baseBodyLarge.fontFamily,
                          fontWeight: baseBodyLarge.fontWeight,
                          inherit: false,
                        );
                        
                        return TextField(
                          controller: _textController,
                          focusNode: _focusNode,
                          maxLength: _maxLength,
                          maxLines: null,
                          minLines: 1,
                          textInputAction: TextInputAction.newline,
                          style: inputStyle,
                          decoration: InputDecoration(
                            hintText: widget.parentCommentId == null
                                ? 'Add a comment...'
                                : 'Write a reply...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            hintStyle: TextStyle(
                              fontSize: baseBodyMedium.fontSize ?? 14,
                              textBaseline: baseBodyMedium.textBaseline ?? TextBaseline.alphabetic,
                              color: colorScheme.onSurface.withOpacity(0.6),
                              fontFamily: baseBodyMedium.fontFamily,
                              inherit: false,
                            ),
                            counterStyle: TextStyle(
                              fontSize: baseBodySmall.fontSize ?? 12,
                              textBaseline: baseBodySmall.textBaseline ?? TextBaseline.alphabetic,
                              color: colorScheme.onSurface.withOpacity(0.6),
                              fontFamily: baseBodySmall.fontFamily,
                              inherit: false,
                            ),
                          ),
                          onChanged: _onComposerChanged,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_textController.text.trim().isNotEmpty)
                    IconButton(
                      icon: _isSubmitting || isCreating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                      onPressed:
                          (_isSubmitting || isCreating) ? null : _submitComment,
                      color: colorScheme.primary,
                    ),
                ],
              ),
              if (_textController.text.length > _maxLength * 0.8)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 16),
                  child: Text(
                    '${_textController.text.length}/$_maxLength',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _textController.text.length > _maxLength
                              ? Colors.red
                              : Colors.grey,
                        ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

