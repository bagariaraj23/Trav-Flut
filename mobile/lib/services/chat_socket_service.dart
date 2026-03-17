import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:tripthread/config/app_config.dart';
import 'package:tripthread/models/chat_message.dart';

typedef OnChatMessageNew = void Function(String conversationId, ChatMessageModel message);
typedef OnTyping = void Function(String conversationId, String userId, String untilIso);
typedef OnConnected = void Function(String userId);
typedef OnError = void Function(String message);

class ChatSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  String? _userId;
  OnChatMessageNew? onMessageNew;
  OnTyping? onTyping;
  OnConnected? onConnected;
  OnError? onError;
  final Future<String?> Function() getAccessToken;
  Timer? _reconnectTimer;
  static const _reconnectDelay = Duration(seconds: 3);
  bool _closed = false;

  ChatSocketService({required this.getAccessToken});

  bool get isConnected => _channel != null;

  String? get userId => _userId;

  void connect() async {
    if (_closed) return;
    final token = await getAccessToken();
    if (token == null || token.isEmpty) {
      debugPrint('[ChatSocket] No token, skip connect');
      return;
    }
    try {
      final uri = Uri.parse(AppConfig.apiBaseUrl);
      final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
      final port = uri.hasPort ? ':${uri.port}' : '';
      final wsUrl = '$scheme://${uri.host}$port/chat?token=${Uri.encodeComponent('Bearer $token')}';
      debugPrint('[ChatSocket] Connecting to $wsUrl');
      final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      // Await the ready future so connection errors are caught here
      // instead of becoming unhandled exceptions.
      try {
        await channel.ready;
      } catch (e) {
        debugPrint('[ChatSocket] WebSocket handshake failed: $e');
        onError?.call(e.toString());
        _scheduleReconnect();
        return;
      }
      if (_closed) {
        channel.sink.close();
        return;
      }
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
      if (event == 'typing') {
        final conversationId = map['conversationId'] as String?;
        final userId = map['userId'] as String?;
        final until = map['until'] as String?;
        if (conversationId != null && userId != null && until != null) {
          onTyping?.call(conversationId, userId, until);
        }
      }
    } catch (e) {
      debugPrint('[ChatSocket] Parse error: $e');
    }
  }

  void disconnect() {
    _closed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _userId = null;
  }

  void sendTyping(String conversationId) {
    if (_channel == null) return;
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
