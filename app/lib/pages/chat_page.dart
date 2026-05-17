import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/ws_service.dart';
import '../services/audio_recorder.dart';
import '../services/audio_player.dart';
import '../services/wav_utils.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _wsService = WebSocketService();
  final _recorderService = AudioRecorderService();
  final _playerService = AudioPlayerService();

  bool _isConnected = false;
  bool _isRecording = false;
  bool _isPlaying = false;
  String _statusText = 'Not connected';
  final List<_ChatMessage> _messages = [];

  StreamSubscription? _wsSubscription;
  StreamSubscription? _audioSubscription;
  final List<int> _audioBuffer = [];
  static const int _chunkSize = 1024; // 512 samples * 2 bytes (int16)

  @override
  void initState() {
    super.initState();
    _playerService.onPlayingChanged = (playing) {
      if (mounted) setState(() => _isPlaying = playing);
    };
  }

  @override
  void dispose() {
    _disconnect();
    _recorderService.dispose();
    _playerService.dispose();
    super.dispose();
  }

  Future<void> _toggleConnection() async {
    if (_isConnected) {
      _disconnect();
    } else {
      await _connect();
    }
  }

  Future<void> _connect() async {
    final hasPermission = await _recorderService.hasPermission();
    if (!hasPermission) {
      setState(() => _statusText = 'Microphone permission denied');
      return;
    }

    try {
      setState(() => _statusText = 'Connecting...');
      await _wsService.connect('ws://127.0.0.1:8000/realtime-chat');

      await _recorderService.start();

      setState(() {
        _isConnected = true;
        _isRecording = true;
        _statusText = 'Connected - listening...';
      });

      _wsSubscription = _wsService.stream?.listen(
        _onWsMessage,
        onError: (error) {
          setState(() => _statusText = 'Error: $error');
          _disconnect();
        },
        onDone: () {
          setState(() => _statusText = 'Disconnected');
          _disconnect();
        },
      );

      _audioSubscription = _recorderService.audioStream?.listen((audioData) {
        if (_wsService.isConnected) {
          _audioBuffer.addAll(audioData);
          while (_audioBuffer.length >= _chunkSize) {
            final chunk = Uint8List.fromList(
              _audioBuffer.sublist(0, _chunkSize),
            );
            _audioBuffer.removeRange(0, _chunkSize);
            _wsService.sendAudio(chunk);
          }
        }
      });
    } catch (e) {
      setState(() => _statusText = 'Connection failed: $e');
    }
  }

  void _onWsMessage(dynamic message) {
    if (message is String) {
      try {
        final json = jsonDecode(message);
        final msg = json['msg'] ?? message;
        setState(() {
          _messages.add(_ChatMessage(text: msg.toString(), isUser: false));
        });
      } catch (_) {
        setState(() {
          _messages.add(_ChatMessage(text: message, isUser: false));
        });
      }
    } else if (message is List<int>) {
      final float32List = bytesToFloat32List(message);
      _playerService.playFloat32Pcm(float32List, 24000);
      setState(() {
        _messages.add(_ChatMessage(text: '[AI voice response]', isUser: false));
      });
    }
  }

  void _disconnect() {
    _wsSubscription?.cancel();
    _wsSubscription = null;
    _audioSubscription?.cancel();
    _audioSubscription = null;

    if (_wsService.isConnected) {
      _wsService.sendText('exit');
      _wsService.disconnect();
    }
    _recorderService.stop();
    _playerService.stop();

    if (mounted) {
      setState(() {
        _isConnected = false;
        _isRecording = false;
        _isPlaying = false;
        _statusText = 'Disconnected';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Voice Chat'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          _buildStatusBar(),
          Expanded(child: _buildMessageList()),
        ],
      ),
      floatingActionButton: _buildMicButton(),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: _isConnected ? Colors.green.shade50 : Colors.grey.shade100,
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isConnected ? Colors.green : Colors.red,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(_statusText)),
          if (_isRecording)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (_isPlaying) ...[
            const SizedBox(width: 8),
            const Icon(Icons.volume_up, size: 18, color: Colors.blue),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    if (_messages.isEmpty) {
      return const Center(
        child: Text(
          'Press the mic button to connect',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        return ListTile(
          dense: true,
          leading: Icon(
            msg.isUser ? Icons.person : Icons.smart_toy,
            size: 20,
            color: msg.isUser ? Colors.blue : Colors.green,
          ),
          title: Text(msg.text, style: const TextStyle(fontSize: 14)),
        );
      },
    );
  }

  Widget _buildMicButton() {
    return FloatingActionButton.extended(
      onPressed: _toggleConnection,
      backgroundColor: _isConnected
          ? Colors.red
          : Theme.of(context).colorScheme.primary,
      icon: Icon(_isConnected ? Icons.stop : Icons.mic),
      label: Text(_isConnected ? 'Disconnect' : 'Connect'),
    );
  }
}

class _ChatMessage {
  final String text;
  final bool isUser;

  _ChatMessage({required this.text, required this.isUser});
}
