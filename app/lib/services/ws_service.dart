import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'config.dart';
import 'settings_service.dart';

class WebSocketService {
  WebSocketChannel? _channel;

  Stream<dynamic>? get stream => _channel?.stream;
  bool get isConnected => _channel != null;

  Future<void> connect(String url) async {
    final apiKey = SettingsService().apiKey;
    var fullUrl = url;
    if (apiKey.isNotEmpty) {
      final separator = url.contains('?') ? '&' : '?';
      fullUrl = '$url${separator}api_key=$apiKey';
    }
    _channel = WebSocketChannel.connect(Uri.parse(fullUrl));
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
