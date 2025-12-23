import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class SocketService {
  WebSocketChannel? _channel;
  final Function(dynamic) onMessage;
  
  // Use computer's IP for physical device
  static const String wsUrl = 'ws://192.168.1.146:8080/ws';

  SocketService({required this.onMessage});

  void connect(String token) {
    if (_channel != null) return;

    try {
      print('Connecting to WS: $wsUrl?token=$token');
      _channel = WebSocketChannel.connect(
        Uri.parse('$wsUrl?token=$token'),
      );
      
      _channel!.stream.listen(
        (message) {
          print('WS Message: $message');
          onMessage(jsonDecode(message));
        },
        onError: (error) {
          print('WS Error: $error');
          _channel = null;
        },
        onDone: () {
          print('WS Disconnected');
          _channel = null;
        },
      );
    } catch (e) {
      print('WS Connection Exception: $e');
    }
  }

  void send(Map<String, dynamic> message) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode(message));
    } else {
      print('WS Not Connected. Cannot send: $message');
    }
  }

  void disconnect() {
    if (_channel != null) {
      _channel!.sink.close();
      _channel = null;
    }
  }
}
