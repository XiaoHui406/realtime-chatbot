import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/config.dart';
import '../services/ws_service.dart';
import '../services/audio_recorder.dart';
import '../services/audio_player.dart';
import '../services/wav_utils.dart';

class CallPage extends StatefulWidget {
  final int sessionId;

  const CallPage({super.key, required this.sessionId});

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  final _wsService = WebSocketService();
  final _recorderService = AudioRecorderService();
  final _playerService = AudioPlayerService();

  bool _isConnected = false;
  String _statusText = 'Connecting...';
  StreamSubscription? _wsSubscription;
  StreamSubscription? _audioSubscription;
  final List<int> _audioBuffer = [];
  static const int _chunkSize = 1024;

  @override
  void initState() {
    super.initState();
    _playerService.onPlayingChanged = (_) {};
    _connect();
  }

  @override
  void dispose() {
    _disconnect();
    _recorderService.dispose();
    _playerService.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final hasPermission = await _recorderService.hasPermission();
    if (!hasPermission) {
      setState(() => _statusText = 'Microphone permission denied');
      return;
    }

    await Geolocator.requestPermission();

    try {
      await _wsService.connectWithSession('${AppConfig.wsBaseUrl}/realtime-chat', widget.sessionId);
      await _recorderService.start();

      setState(() {
        _isConnected = true;
        _statusText = 'Connected';
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
            final chunk = Uint8List.fromList(_audioBuffer.sublist(0, _chunkSize));
            _audioBuffer.removeRange(0, _chunkSize);
            _wsService.sendAudio(chunk);
          }
        }
      });
    } catch (e) {
      setState(() => _statusText = 'Connection failed');
    }
  }

  void _onWsMessage(dynamic message) {
    if (message is String) {
      try {
        final json = jsonDecode(message);
        if (json is Map<String, dynamic>) {
          if (json['type'] == 'request' && json['action'] == 'get_location') {
            _handleLocationRequest(json['request_id'] as String);
            return;
          }
        }
      } catch (_) {}
    } else if (message is List<int>) {
      final float32List = bytesToFloat32List(message);
      _playerService.playFloat32Pcm(float32List, 24000);
      setState(() => _statusText = 'Assistant speaking...');
    }
  }

  Future<void> _handleLocationRequest(String requestId) async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _wsService.sendText(jsonEncode({
          'type': 'response',
          'request_id': requestId,
          'result': {'error': 'Location service is disabled'},
        }));
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _wsService.sendText(jsonEncode({
            'type': 'response',
            'request_id': requestId,
            'result': {'error': 'Location permission denied'},
          }));
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _wsService.sendText(jsonEncode({
          'type': 'response',
          'request_id': requestId,
          'result': {'error': 'Location permission permanently denied'},
        }));
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 5),
        ),
      );

      _wsService.sendText(jsonEncode({
        'type': 'response',
        'request_id': requestId,
        'result': {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracy': position.accuracy,
        },
      }));
    } catch (e) {
      _wsService.sendText(jsonEncode({
        'type': 'response',
        'request_id': requestId,
        'result': {'error': e.toString()},
      }));
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
        _statusText = 'Disconnected';
      });
    }
  }

  Future<void> _hangUp() async {
    _disconnect();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF3D3D6B),
        body: SafeArea(
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
              const Spacer(flex: 2),
              _buildStatusSection(),
              const Spacer(),
              _buildHangUpButton(),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildStatusSection() {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isConnected ? Colors.green.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.2),
          ),
          child: Icon(
            _isConnected ? Icons.mic : Icons.mic_off,
            size: 40,
            color: _isConnected ? Colors.green : Colors.grey,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          _statusText,
          style: const TextStyle(fontSize: 18, color: Colors.white70),
        ),
        if (_isConnected) ...[
          const SizedBox(height: 8),
          const Text(
            'Talking with AI...',
            style: TextStyle(fontSize: 14, color: Colors.white38),
          ),
        ],
      ],
    );
  }

  Widget _buildHangUpButton() {
    return GestureDetector(
      onTap: _hangUp,
      child: Container(
        width: 72,
        height: 72,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.red,
        ),
        child: const Icon(Icons.call_end, color: Colors.white, size: 36),
      ),
    );
  }
}
