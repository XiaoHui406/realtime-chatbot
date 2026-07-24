import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/config.dart';
import '../services/ws_service.dart';
import '../services/audio_recorder.dart';
import '../services/audio_player.dart';
import '../services/wav_utils.dart';
import '../services/screen_capturer.dart';
import '../services/photo_capturer.dart';

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
  bool _requestInProgress = false;
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
    // dispose期间不能setState：unmount阶段element已defunct，
    // setState会触发断言并中断本方法，导致后面的资源释放全部不执行
    _disconnect(updateUi: false);
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
          if (_requestInProgress) return;
          setState(() => _statusText = 'Error: $error');
          _disconnect();
        },
        onDone: () {
          if (_requestInProgress) return;
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
          if (json['type'] == 'request') {
            final action = json['action'] as String?;
            final requestId = json['request_id'] as String;
            switch (action) {
              case 'get_location':
                _handleLocationRequest(requestId);
                return;
              case 'screenshot':
                _handleScreenshotRequest(requestId);
                return;
              case 'capture_photo':
                _handleCameraRequest(requestId);
                return;
            }
          }
        }
      } catch (_) {}
    } else if (message is List<int>) {
      print('audio received at ${DateTime.now().millisecondsSinceEpoch / 1000.0}');
      final float32List = bytesToFloat32List(message);
      _playerService.playFloat32Pcm(float32List, 24000);
      setState(() => _statusText = 'Assistant speaking...');
    }
  }

  Future<void> _handleLocationRequest(String requestId) async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _sendRequestError(requestId, 'Location permission denied');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _sendRequestError(requestId, 'Location permission permanently denied');
        return;
      }

      // 不预检isLocationServiceEnabled：部分Android ROM会误报false，
      // 直接尝试定位，由异常兜底
      // Android强制使用系统LocationManager，避免无谷歌服务的机型上
      // fused定位不可用导致失败
      final locationSettings = defaultTargetPlatform == TargetPlatform.android
          ? AndroidSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: const Duration(seconds: 5),
              forceLocationManager: true,
            )
          : const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 5),
            );

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: locationSettings,
        );
      } catch (e) {
        // 实时定位失败（超时等）时退回最后一次已知位置
        Position? lastKnown;
        try {
          lastKnown = await Geolocator.getLastKnownPosition();
        } catch (_) {}
        if (lastKnown == null) {
          _sendRequestError(requestId, e.toString());
          return;
        }
        position = lastKnown;
      }

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
      _sendRequestError(requestId, e.toString());
    }
  }

  void _sendRequestError(String requestId, String message) {
    _wsService.sendText(jsonEncode({
      'type': 'response',
      'request_id': requestId,
      'result': {'error': message},
    }));
  }

  Future<void> _handleScreenshotRequest(String requestId) async {
    try {
      _requestInProgress = true;
      final images = await ScreenCapturer.pick(context);
      _requestInProgress = false;

      if (!_wsService.isConnected) {
        await _reconnect();
      }

      if (images == null || images.isEmpty) {
        _sendRequestError(requestId, 'No images selected');
        return;
      }
      _wsService.sendText(jsonEncode({
        'type': 'response',
        'request_id': requestId,
        'result': {
          'images': images,
          'format': 'jpeg',
          'message': 'Selected ${images.length} image(s)',
        },
      }));
    } catch (e) {
      _requestInProgress = false;
      _sendRequestError(requestId, e.toString());
    }
  }

  Future<void> _handleCameraRequest(String requestId) async {
    try {
      _requestInProgress = true;
      final base64 = await PhotoCapturer.capture(context);
      _requestInProgress = false;

      if (!_wsService.isConnected) {
        await _reconnect();
      }

      if (base64 == null) {
        _sendRequestError(requestId, 'Camera capture cancelled or failed');
        return;
      }
      _wsService.sendText(jsonEncode({
        'type': 'response',
        'request_id': requestId,
        'result': {
          'image_base64': base64,
          'format': 'jpeg',
          'message': 'Photo captured',
        },
      }));
    } catch (e) {
      _requestInProgress = false;
      _sendRequestError(requestId, e.toString());
    }
  }

  Future<void> _reconnect() async {
    _wsSubscription?.cancel();
    _wsSubscription = null;
    _audioSubscription?.cancel();
    _audioSubscription = null;
    _recorderService.stop();
    _playerService.stop();
    _wsService.disconnect();
    await _connect();
  }

  void _disconnect({bool updateUi = true}) {
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

    if (updateUi && mounted) {
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
