import 'dart:async';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'settings_service.dart';

class WebSocketService {
  WebSocketChannel? _channel;

  Stream<dynamic>? get stream => _channel?.stream;
  bool get isConnected => _channel != null;

  Future<void> connect(String url) async {
    final apiKey = SettingsService().apiKey;
    // api key通过Authorization header传递，与REST接口一致，
    // 避免出现在URL中被服务端访问日志记录（仅原生端支持，不兼容web）
    _channel = IOWebSocketChannel.connect(
      Uri.parse(url),
      headers: apiKey.isNotEmpty ? {'Authorization': 'Bearer $apiKey'} : null,
    );
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
