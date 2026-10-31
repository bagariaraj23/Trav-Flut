import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// GoRouter `extra` that tells a chat screen where its back button should go.
Map<String, String> chatReturnExtra(String from) => {'from': from};

/// The screen that opened this chat, when the caller recorded one.
String? chatReturnLocation(BuildContext context) {
  final extra = GoRouterState.of(context).extra;
  if (extra is! Map) return null;
  final from = extra['from'];
  if (from is! String) return null;
  if (!from.startsWith('/') || from.startsWith('//') || from.contains('://')) {
    return null;
  }
  return from;
}

/// Leaves a pushed chat route.
///
/// A normal pop drops every chat screen and lands on home, so this goes
/// straight to the screen that opened the chat.
void leaveChatRoute(BuildContext context, {required String fallback}) {
  context.go(chatReturnLocation(context) ?? fallback);
}

/// Back from chat details returns to that chat and keeps its return location.
void leaveChatSettings(BuildContext context, String conversationId) {
  context.go(
    '/chat/$conversationId',
    extra: GoRouterState.of(context).extra,
  );
}
