import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/providers/comment_provider.dart';
import 'package:tripthread/models/comment.dart';

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

class _CommentComposerState extends State<CommentComposer> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  bool _isSubmitting = false;
  final int _maxLength = 250;

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submitComment() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isSubmitting) return;

    setState(() => _isSubmitting = true);
    HapticFeedback.mediumImpact();

    try {
      final provider = context.read<CommentProvider>();
      await provider.createComment(
        widget.entityType,
        widget.entityId,
        text,
        widget.parentCommentId,
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
            color: Theme.of(context).scaffoldBackgroundColor,
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
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.reply, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Replying to ${widget.parentComment?.user?.name ?? 'user'}',
                          style: Theme.of(context).textTheme.bodySmall,
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final theme = Theme.of(context);
                        final textTheme = theme.textTheme;
                        final colorScheme = theme.colorScheme;
                        
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
                          onChanged: (value) => setState(() {}),
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
                      color: Theme.of(context).colorScheme.primary,
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

