import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:geolocator/geolocator.dart';
import '../services/config.dart';
import '../services/live2d_model_service.dart';
import '../services/live2d_server.dart';
import '../services/ws_service.dart';
import '../services/audio_recorder.dart';
import '../services/audio_player.dart';
import '../services/wav_utils.dart';
import '../services/screen_capturer.dart';
import '../services/photo_capturer.dart';

class Live2DCallPage extends StatefulWidget {
  final int sessionId;

  const Live2DCallPage({super.key, required this.sessionId});

  @override
  State<Live2DCallPage> createState() => _Live2DCallPageState();
}

class _Live2DCallPageState extends State<Live2DCallPage> {
  final _wsService = WebSocketService();
  final _recorderService = AudioRecorderService();
  final _playerService = AudioPlayerService();
  Live2DServer? _server;

  InAppWebViewController? _controller;
  bool _isConnected = false;
  bool _requestInProgress = false;
  String _statusText = 'Connecting...';
  StreamSubscription? _wsSubscription;
  StreamSubscription? _audioSubscription;
  final List<int> _audioBuffer = [];
  static const int _chunkSize = 1024;

  bool _l2dReady = false;
  bool _pageReady = false;
  String? _error;
  Timer? _mouthTimer;
  double _pendingMs = 0;
  double _peakVolume = 0;
  double _currentMouth = 0;
  double _mouthPhase = 0;
  static const _mouthTickMs = 50;

  @override
  void initState() {
    super.initState();
    _playerService.onPlayingChanged = (playing) {
      if (!playing) _pendingMs = 0;
    };
    _initLive2D();
  }

  Future<void> _initLive2D() async {
    try {
      final distPath = await Live2DServer.findDistPath();
      if (distPath.isEmpty) {
        if (mounted) setState(() => _error = 'Live2D dist directory not found');
        return;
      }

      _server = Live2DServer(distPath);
      await _server!.start();

      if (mounted) setState(() => _pageReady = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Live2D init failed: $e');
    }
  }

  @override
  void dispose() {
    _mouthTimer?.cancel();
    _disconnect(updateUi: false);
    _recorderService.dispose();
    _playerService.dispose();
    _server?.stop();
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
      await _wsService.connectWithSession(
          '${AppConfig.wsBaseUrl}/realtime-chat', widget.sessionId);
      await _recorderService.start();

      setState(() {
        _isConnected = true;
        _statusText = 'Connected';
      });
      _ensureMouthLooper();

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
            final chunk =
                Uint8List.fromList(_audioBuffer.sublist(0, _chunkSize));
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
      final float32List = bytesToFloat32List(message);
      _playerService.playFloat32Pcm(float32List, 24000);
      _pendingMs += float32List.length * 1000.0 / 24000;
      final v = _rmsVolume(float32List);
      if (v > _peakVolume) _peakVolume = v;
      _ensureMouthLooper();
    }
  }

  double _rmsVolume(Float32List samples) {
    if (samples.isEmpty) return 0;
    double sum = 0;
    for (final s in samples) {
      sum += s * s;
    }
    final rms = math.sqrt(sum / samples.length);
    return (rms * 5).clamp(0.0, 1.0);
  }

  void _ensureMouthLooper() {
    if (_mouthTimer?.isActive == true) return;
    _mouthTimer = Timer.periodic(
        const Duration(milliseconds: _mouthTickMs), (_) => _mouthTick());
  }

  void _mouthTick() {
    if (_pendingMs <= 0 && _currentMouth < 0.01) {
      _currentMouth = 0;
      _mouthPhase = 0;
      _peakVolume = 0;
      _eval('Live2DBridge.setMouthOpen(0)');
      _mouthTimer?.cancel();
      _mouthTimer = null;
      return;
    }

    _pendingMs = (_pendingMs - _mouthTickMs).clamp(0, 999999);

    if (_pendingMs > 0) {
      _mouthPhase += (_mouthTickMs / 200.0) * 2 * math.pi;

      final w1 = math.sin(_mouthPhase) * 0.50;
      final w2 = math.sin(_mouthPhase * 1.73 + 2.1) * 0.30;
      final w3 = math.sin(_mouthPhase * 0.47 + 4.5) * 0.20;
      final raw = w1 + w2 + w3;
      final target = _peakVolume.clamp(0.18, 0.72);
      _currentMouth =
          (target * (0.5 + 0.5 * raw.clamp(-1.0, 1.0))).clamp(0.0, 1.0);
    } else {
      _currentMouth *= 0.78;
      _peakVolume = 0;
    }

    _eval(
        'Live2DBridge.setMouthOpen(${_currentMouth.toStringAsFixed(3)})');
  }

  void _closeMouth() {
    _mouthTimer?.cancel();
    _mouthTimer = null;
    _pendingMs = 0;
    _peakVolume = 0;
    _mouthPhase = 0;
    _currentMouth = 0;
    _eval('Live2DBridge.setMouthOpen(0)');
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
        _sendRequestError(
            requestId, 'Location permission permanently denied');
        return;
      }

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
    _mouthTimer?.cancel();
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
    _mouthTimer?.cancel();
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
    _closeMouth();
    _disconnect();
    if (mounted) Navigator.of(context).pop();
  }

  Future<dynamic> _eval(String js) async {
    if (_controller == null) return null;
    try {
      final result = await _controller!.callAsyncJavaScript(
          functionBody: 'return $js;',
          arguments: const <String, dynamic>{});
      return result?.value;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isConnected,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(_error!,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
              textAlign: TextAlign.center),
        ),
      );
    }

    if (!_pageReady) {
      return Stack(
        children: [
          const Center(child: CircularProgressIndicator(color: Colors.white)),
          Positioned(
            left: 0,
            right: 0,
            bottom: 32,
            child: Center(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white24,
                  ),
                  child: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
                ),
              ),
            ),
          ),
        ],
      );
    }

    final url = 'http://127.0.0.1:${_server!.port}';

    return Stack(
      children: [
        Positioned.fill(
          child: InAppWebView(
            initialSettings: InAppWebViewSettings(
              transparentBackground: true,
              javaScriptEnabled: true,
            ),
            initialUrlRequest: URLRequest(url: WebUri(url)),
            onWebViewCreated: (c) => _controller = c,
            onLoadStop: (c, u) {
              _eval(
                  "document.getElementById('l2d-status').style.display='none'");
              final model = Live2DModelService().getSelected();
              model.then((m) {
                if (m != null && m.path.isNotEmpty) {
                  _eval("Live2DBridge.switchModel('${m.path}')");
                }
              });
              final checkReady = Timer.periodic(
                  const Duration(milliseconds: 200), (t) {
                if (_l2dReady) {
                  t.cancel();
                  return;
                }
                _eval('Live2DBridge.isReady()').then((r) {
                  if (_l2dReady) return;
                  if (r == true) {
                    t.cancel();
                    _l2dReady = true;
                    _connect();
                  }
                });
              });
              Future.delayed(const Duration(seconds: 10), () {
                if (!_l2dReady) checkReady.cancel();
              });
            },
            onConsoleMessage: (c, m) =>
                debugPrint('[Live2D] ${m.message}'),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 32,
          child: _buildHangUpButton(),
        ),
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
        child:
            const Icon(Icons.call_end, color: Colors.white, size: 36),
      ),
    );
  }
}
