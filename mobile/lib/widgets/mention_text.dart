import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/services/api_service.dart';

/// Renders text with @username mentions styled and tappable.
/// Tapping a mention invokes [onMentionTap] with the username (without @).
/// Optional [usernameToUserId] maps username -> userId for immediate navigation
/// without an API call (e.g. from entry.taggedUsers).
class MentionText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final Map<String, String>? usernameToUserId;
  final void Function(String username)? onMentionTap;

  const MentionText({
    super.key,
    required this.text,
    this.style,
    this.maxLines,
    this.overflow,
    this.usernameToUserId,
    this.onMentionTap,
  });

  static final RegExp _mentionRegex = RegExp(r'@(\w+)');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = style ?? theme.textTheme.bodyMedium ?? const TextStyle();
    final mentionColor = theme.colorScheme.primary;
    final mentionStyle = baseStyle.copyWith(
      color: mentionColor,
      fontWeight: FontWeight.w500,
    );

    final spans = <TextSpan>[];
    int lastEnd = 0;

    for (final match in _mentionRegex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: baseStyle,
        ));
      }
      final username = match.group(1)!;
      spans.add(TextSpan(
        text: '@$username',
        style: mentionStyle,
        recognizer: TapGestureRecognizer()
          ..onTap = () {
            if (onMentionTap != null) {
              onMentionTap!(username);
            } else {
              _navigateToProfile(context, username);
            }
          },
      ));
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: baseStyle,
      ));
    }

    if (spans.isEmpty) {
      return Text(
        text,
        style: baseStyle,
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    return RichText(
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
      text: TextSpan(style: baseStyle, children: spans),
    );
  }

  void _navigateToProfile(BuildContext context, String username) {
    final userId = usernameToUserId?[username];
    if (userId != null && userId.isNotEmpty) {
      context.push('/profile/$userId');
      return;
    }
    _resolveAndNavigate(context, username);
  }

  Future<void> _resolveAndNavigate(BuildContext context, String username) async {
    final api = _getApiService(context);
    if (api == null) return;
    final response = await api.searchUsers(search: username, limit: 5);
    if (!response.success || response.data == null) return;
    final normalized = username.toLowerCase();
    for (final u in response.data!) {
      final id = u['id'] as String?;
      final un = (u['username'] as String?)?.toLowerCase();
      if (id != null && un == normalized) {
        if (context.mounted) context.push('/profile/$id');
        return;
      }
    }
  }

  static ApiService? _getApiService(BuildContext context) {
    try {
      return context.read<ApiService>();
    } catch (_) {
      return null;
    }
  }
}
