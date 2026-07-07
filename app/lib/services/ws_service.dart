import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketService {
  WebSocketChannel? _channel;

  Stream<dynamic>? get stream => _channel?.stream;
  bool get isConnected => _channel != null;

  Future<void> connect(String url) async {
    _channel = WebSocketChannel.connect(Uri.parse(url));
    await _channel!.ready;
  }

  Future<void> connectWithSession(String baseUrl, int sessionId) async {
    final url = '$baseUrl?session_id=$sessionId';
    await connect(url);
  }

  void sendAudio(List<int> data) {
    _channel?.sink.add(data);
  }

  void sendText(String text) {
    _channel?.sink.add(text);
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }
}
