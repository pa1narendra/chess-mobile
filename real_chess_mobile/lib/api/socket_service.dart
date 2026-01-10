import 'dart:convert';
import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../utils/config.dart';

enum SocketConnectionState { disconnected, connecting, connected, reconnecting }

class SocketService {
  WebSocketChannel? _channel;
  final Function(dynamic) onMessage;
  final Function(SocketConnectionState)? onConnectionStateChange;

  bool _isExplicitlyDisconnected = false;
  bool _isReconnecting = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  String? _currentToken;
  SocketConnectionState _connectionState = SocketConnectionState.disconnected;

  static String get wsUrl => Config.wsUrl;

  SocketService({required this.onMessage, this.onConnectionStateChange});

  SocketConnectionState get connectionState => _connectionState;

  void _setConnectionState(SocketConnectionState state) {
    _connectionState = state;
    onConnectionStateChange?.call(state);
  }

  void connect(String token) {
    _isExplicitlyDisconnected = false;
    _reconnectAttempts = 0;
    _currentToken = token;
    _connect(token);
  }

  void _connect(String token) {
    if (_channel != null || _isExplicitlyDisconnected) return;

    _setConnectionState(SocketConnectionState.connecting);

    try {
      _channel = WebSocketChannel.connect(
        Uri.parse('$wsUrl?token=$token'),
      );

      _channel!.stream.listen(
        (message) {
          _setConnectionState(SocketConnectionState.connected);
          _reconnectAttempts = 0;
          _isReconnecting = false;

          try {
            onMessage(jsonDecode(message));
          } catch (e) {
            // JSON decode error - don't crash the listener
            _socketDebugPrint('Socket JSON decode error: $e');
          }
        },
        onError: (error) {
          _socketDebugPrint('WS Error: $error');
          _channel = null;
          _attemptReconnect(token);
        },
        onDone: () {
          _socketDebugPrint('WS Disconnected');
          _channel = null;
          _attemptReconnect(token);
        },
      );
    } catch (e) {
      _socketDebugPrint('WS Connection Exception: $e');
      _channel = null;
      _attemptReconnect(token);
    }
  }

  void _attemptReconnect(String token) {
    if (_isExplicitlyDisconnected || _isReconnecting) return;

    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _socketDebugPrint('Max reconnection attempts reached ($_maxReconnectAttempts)');
      _setConnectionState(SocketConnectionState.disconnected);
      return;
    }

    _isReconnecting = true;
    _reconnectAttempts++;
    _setConnectionState(SocketConnectionState.reconnecting);

    // Exponential backoff: 1s, 2s, 4s, 8s, 16s
    final delay = Duration(seconds: (1 << (_reconnectAttempts - 1)).clamp(1, 16));
    _socketDebugPrint('Attempting to reconnect in ${delay.inSeconds}s (attempt $_reconnectAttempts/$_maxReconnectAttempts)');

    Future.delayed(delay, () {
      if (!_isExplicitlyDisconnected) {
        _isReconnecting = false;
        _connect(token);
      }
    });
  }

  void send(Map<String, dynamic> message) {
    if (_channel != null && _connectionState == SocketConnectionState.connected) {
      try {
        _channel!.sink.add(jsonEncode(message));
      } catch (e) {
        _socketDebugPrint('Error sending message: $e');
      }
    } else {
      _socketDebugPrint('WS Not Connected. Cannot send message.');
    }
  }

  void disconnect() {
    _isExplicitlyDisconnected = true;
    _isReconnecting = false;
    _reconnectAttempts = 0;
    _currentToken = null;

    if (_channel != null) {
      _channel!.sink.close();
      _channel = null;
    }
    _setConnectionState(SocketConnectionState.disconnected);
  }

  void resetReconnectAttempts() {
    _reconnectAttempts = 0;
  }
}

// Simple debug print that can be disabled in production
void _socketDebugPrint(String message) {
  // ignore: avoid_print
  print('[Socket] $message');
}
