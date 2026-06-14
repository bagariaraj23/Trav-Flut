import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:tripthread/config/app_config.dart';
import 'package:tripthread/models/chat_message.dart';

typedef OnChatMessageNew = void Function(String conversationId, ChatMessageModel message);
typedef OnChatMessageUpdated = void Function(String conversationId, ChatMessageModel message);
typedef OnChatMessageDeleted = void Function(String conversationId, String messageId, String deletedAt);
typedef OnTyping = void Function(String conversationId, String userId, String untilIso);
typedef OnConnected = void Function(String userId);
typedef OnError = void Function(String message);
typedef OnConversationRead = void Function(String conversationId, String userId, String lastReadAt);
typedef OnPresenceUpdate = void Function(String userId, String status, String lastSeen);

class ChatSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  String? _userId;
  OnChatMessageNew? onMessageNew;
  OnChatMessageUpdated? onMessageUpdated;
  OnChatMessageDeleted? onMessageDeleted;
  OnTyping? onTyping;
  OnConnected? onConnected;
  OnError? onError;
  OnConversationRead? onConversationRead;
  OnPresenceUpdate? onPresenceUpdate;
  final Future<String?> Function() getAccessToken;
  Timer? _reconnectTimer;
  static const _reconnectDelay = Duration(seconds: 3);
  bool _closed = false;
  bool _connecting = false;

  ChatSocketService({required this.getAccessToken});

  bool get isConnected => _channel != null;

  String? get userId => _userId;

  void connect() async {
    if (_closed) return;
    if (_connecting) {
      if (kDebugMode) {
        debugPrint('[ChatSocket] connect skipped (already in progress)');
      }
      return;
    }
    _connecting = true;
    try {
      final token = await getAccessToken();
      if (token == null || token.isEmpty) {
        debugPrint('[ChatSocket] No token yet; scheduling reconnect');
        _scheduleReconnect();
        return;
      }
      try {
        final origin = AppConfig.chatWebSocketHttpOrigin;
        final scheme = origin.scheme == 'https' ? 'wss' : 'ws';
        final port = origin.hasPort ? ':${origin.port}' : '';
        // Connect WITHOUT the token in the URL to prevent JWT exposure in
        // server/proxy access logs. The token is sent as the first WS message
        // after the handshake completes (server supports this via the 10-s
        // auth-timeout path in chat-ws.ts).
        final wsUrl = '$scheme://${origin.host}$port/chat';
        debugPrint('[ChatSocket] Connecting to $wsUrl');
        final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
        try {
          await channel.ready;
        } catch (e) {
          debugPrint('[ChatSocket] WebSocket handshake failed: $e');
          if (kDebugMode) {
            debugPrint(
              '[ChatSocket] Ensure `npm run dev` (server.cjs) is running on port 3000 — '
              'plain `next dev` does not host /chat (no WebSocket upgrade).',
            );
          }
          onError?.call(e.toString());
          _scheduleReconnect();
          return;
        }
        // Send auth token immediately after the handshake so the server can
        // authenticate the connection without it ever appearing in any URL.
        try {
          channel.sink.add(jsonEncode({'type': 'auth', 'token': 'Bearer $token'}));
        } catch (e) {
          debugPrint('[ChatSocket] Failed to send auth message: $e');
        }
        if (_closed) {
          channel.sink.close();
          return;
        }
        await _subscription?.cancel();
        _subscription = null;
        try {
          await _channel?.sink.close();
        } catch (_) {}
        _channel = null;
        _channel = channel;
        _subscription = _channel!.stream.listen(
          _onData,
          onError: (e) {
            debugPrint('[ChatSocket] Stream error: $e');
            onError?.call(e.toString());
            _channel = null;
            _subscription = null;
            _scheduleReconnect();
          },
          onDone: () {
            debugPrint('[ChatSocket] Done');
            _channel = null;
            _subscription = null;
            if (!_closed) _scheduleReconnect();
          },
          cancelOnError: false,
        );
        debugPrint('[ChatSocket] Connected successfully');
      } catch (e) {
        debugPrint('[ChatSocket] Connect error: $e');
        onError?.call(e.toString());
        _scheduleReconnect();
      }
    } finally {
      _connecting = false;
    }
  }

  void _scheduleReconnect() {
    if (_closed || _reconnectTimer != null) return;
    _reconnectTimer = Timer(_reconnectDelay, () {
      _reconnectTimer = null;
      connect();
    });
  }

  void _onData(dynamic data) {
    try {
      if (data is! String) return;
      final map = jsonDecode(data) as Map<String, dynamic>?;
      if (map == null) return;
      final type = map['type'] as String?;
      if (type == 'connected') {
        _userId = map['userId'] as String?;
        onConnected?.call(_userId ?? '');
        return;
      }
      if (type == 'error') {
        onError?.call(map['message'] as String? ?? 'Unknown error');
        return;
      }
      final event = map['event'] as String?;
      if (event == 'message.new') {
        final conversationId = map['conversationId'] as String?;
        final messageJson = map['message'] as Map<String, dynamic>?;
        if (conversationId != null && messageJson != null) {
          final message = ChatMessageModel.fromJson(messageJson);
          onMessageNew?.call(conversationId, message);
        }
        return;
      }
      if (event == 'message.updated') {
        final conversationId = map['conversationId'] as String?;
        final messageJson = map['message'] as Map<String, dynamic>?;
        if (conversationId != null && messageJson != null) {
          final message = ChatMessageModel.fromJson(messageJson);
          onMessageUpdated?.call(conversationId, message);
        }
        return;
      }
      if (event == 'typing') {
        final conversationId = map['conversationId'] as String?;
        final userId = map['userId'] as String?;
        final until = map['until'] as String?;
        if (conversationId != null && userId != null && until != null) {
          onTyping?.call(conversationId, userId, until);
        }
        return;
      }
      if (event == 'message.deleted') {
        final conversationId = map['conversationId'] as String?;
        final messageId = map['messageId'] as String?;
        final deletedAt = map['deletedAt'] as String?;
        if (conversationId != null && messageId != null && deletedAt != null) {
          onMessageDeleted?.call(conversationId, messageId, deletedAt);
        }
        return;
      }
      if (event == 'conversation.read') {
        final conversationId = map['conversationId'] as String?;
        final userId = map['userId'] as String?;
        final lastReadAt = map['lastReadAt'] as String?;
        if (conversationId != null && userId != null && lastReadAt != null) {
          onConversationRead?.call(conversationId, userId, lastReadAt);
        }
        return;
      }
      if (event == 'presence.update') {
        final userId = map['userId'] as String?;
        final status = map['status'] as String?;
        final lastSeen = map['lastSeen'] as String?;
        if (userId != null && status != null && lastSeen != null) {
          onPresenceUpdate?.call(userId, status, lastSeen);
        }
        return;
      }
    } catch (e) {
      debugPrint('[ChatSocket] Parse error: $e');
    }
  }

  /// Close the socket but allow [connect] again (e.g. after logout → next login).
  void resetConnection() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _subscription?.cancel();
    _subscription = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _userId = null;
    _connecting = false;
  }

  void disconnect() {
    _closed = true;
    resetConnection();
  }

  void sendTyping(String conversationId) {
    if (_channel == null) {
      connect();
      return;
    }
    try {
      _channel!.sink.add(jsonEncode({
        'type': 'typing',
        'conversationId': conversationId,
      }));
    } catch (e) {
      debugPrint('[ChatSocket] Send typing error: $e');
    }
  }
}
