import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../services/live2d_server.dart';

class Live2DDemoPage extends StatefulWidget {
  final String? modelPath;

  const Live2DDemoPage({super.key, this.modelPath});
  @override
  State<Live2DDemoPage> createState() => _Live2DDemoPageState();
}

class _Live2DDemoPageState extends State<Live2DDemoPage> {
  InAppWebViewController? _controller;
  Live2DServer? _server;

  double _mouthOpen = 0;
  double _eyeOpen = 1.0;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initServer();
  }

  Future<void> _initServer() async {
    try {
      final distPath = await Live2DServer.findDistPath();
      if (distPath.isEmpty) {
        if (mounted) {
          setState(() => _error = 'Live2D dist directory not found.\n\n'
              'Please run the SDK build steps in assets/live2d/README.md, '
              'or copy the dist directory to the app support folder.');
        }
        return;
      }

      _server = Live2DServer(distPath);
      await _server!.start();

      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to start Live2D server: $e');
    }
  }

  @override
  void dispose() {
    _server?.stop();
    super.dispose();
  }

  Future<void> _eval(String js) async {
    if (_controller == null) return;
    try {
      await _controller!.callAsyncJavaScript(
          functionBody: 'return $js;',
          arguments: const <String, dynamic>{});
    } catch (_) {}
  }

  Future<void> _setMouthOpen(double v) async {
    _mouthOpen = v;
    await _eval('Live2DBridge.setMouthOpen(${v.toStringAsFixed(3)})');
  }

  Future<void> _setEyeOpen(double v) async {
    _eyeOpen = v;
    await _eval('Live2DBridge.setEyeOpen(${v.toStringAsFixed(3)})');
  }

  Future<void> _setExpression(String n) =>
      _eval("Live2DBridge.setExpression('$n')");
  Future<void> _startMotion(String g, int i) =>
      _eval("Live2DBridge.startMotion('$g', $i)");

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF3D3D6B),
      appBar: AppBar(
          title: const Text('Live2D Demo'),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white),
      body: _buildBody(),
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

    if (!_ready) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }

    final url = _server!.url;

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
              debugPrint('[Live2D] loaded: $u');
              if (widget.modelPath != null) {
                _eval(
                    "Live2DBridge.switchModel('${widget.modelPath}')");
              }
            },
            onConsoleMessage: (c, m) =>
                debugPrint('[Live2D] ${m.message}'),
          ),
        ),
        Positioned(left: 0, right: 0, bottom: 0, child: _controls()),
      ],
    );
  }

  Widget _controls() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Colors.black.withAlpha(100),
          Colors.black.withAlpha(180)
        ],
      )),
      child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _slider('mouth', _mouthOpen, _setMouthOpen, Colors.pinkAccent),
            _slider('eye', _eyeOpen, _setEyeOpen, Colors.cyanAccent),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _btn('smile', () => _setExpression('smile')),
              _btn('surprised', () => _setExpression('surprised')),
              _btn('angry', () => _setExpression('angry')),
              _btn('idle', () => _startMotion('Idle', 0)),
            ]),
          ])),
    );
  }

  Widget _slider(
      String label, double v, ValueChanged<double> cb, Color color) {
    return Row(children: [
      SizedBox(
          width: 60,
          child: Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 12))),
      Expanded(
          child: Slider(
              value: v, min: 0, max: 1, onChanged: cb, activeColor: color)),
      SizedBox(
          width: 40,
          child: Text(v.toStringAsFixed(2),
              style: const TextStyle(color: Colors.white54, fontSize: 11))),
    ]);
  }

  Widget _btn(String l, VoidCallback cb) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white24,
          foregroundColor: Colors.white,
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          textStyle: const TextStyle(fontSize: 12)),
      onPressed: cb,
      child: Text(l),
    );
  }
}
