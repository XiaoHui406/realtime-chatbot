import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class Live2DDemoPage extends StatefulWidget {
  const Live2DDemoPage({super.key});

  @override
  State<Live2DDemoPage> createState() => _Live2DDemoPageState();
}

class _Live2DDemoPageState extends State<Live2DDemoPage> {
  late final WebViewController _controller;
  bool _modelReady = false;
  double _mouthOpen = 0;
  double _eyeOpen = 1.0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            debugPrint('[Live2D] page loaded');
          },
        ),
      )
      ..addJavaScriptChannel(
        'Live2DFlutterChannel',
        onMessageReceived: (msg) {
          debugPrint('[Live2D] JS message: ${msg.message}');
        },
      )
      ..loadFlutterAsset('assets/live2d/dist/index.html');
  }

  Future<void> _setMouthOpen(double value) async {
    _mouthOpen = value;
    await _controller.evaluateJavaScript(
      'Live2DBridge.setMouthOpen(${value.toStringAsFixed(3)})',
    );
  }

  Future<void> _setEyeOpen(double value) async {
    _eyeOpen = value;
    await _controller.evaluateJavaScript(
      'Live2DBridge.setEyeOpen(${value.toStringAsFixed(3)})',
    );
  }

  Future<void> _setExpression(String name) async {
    await _controller.evaluateJavaScript(
      "Live2DBridge.setExpression('$name')",
    );
  }

  Future<void> _startMotion(String group, int index) async {
    await _controller.evaluateJavaScript(
      "Live2DBridge.startMotion('$group', $index)",
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF3D3D6B),
      appBar: AppBar(
        title: const Text('Live2D Demo'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // Live2D WebView
          Positioned.fill(child: WebViewWidget(controller: _controller)),

          // 底部控制面板
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withAlpha(100),
                    Colors.black.withAlpha(180),
                  ],
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 嘴型滑块
                    Row(
                      children: [
                        const SizedBox(
                          width: 60,
                          child: Text('嘴巴',
                              style: TextStyle(color: Colors.white70, fontSize: 12)),
                        ),
                        Expanded(
                          child: Slider(
                            value: _mouthOpen,
                            min: 0,
                            max: 1,
                            onChanged: (v) => _setMouthOpen(v),
                            activeColor: Colors.pinkAccent,
                          ),
                        ),
                        SizedBox(
                          width: 40,
                          child: Text(
                            _mouthOpen.toStringAsFixed(2),
                            style: const TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                    // 眼睛滑块
                    Row(
                      children: [
                        const SizedBox(
                          width: 60,
                          child: Text('眼睛',
                              style: TextStyle(color: Colors.white70, fontSize: 12)),
                        ),
                        Expanded(
                          child: Slider(
                            value: _eyeOpen,
                            min: 0,
                            max: 1,
                            onChanged: (v) => _setEyeOpen(v),
                            activeColor: Colors.cyanAccent,
                          ),
                        ),
                        SizedBox(
                          width: 40,
                          child: Text(
                            _eyeOpen.toStringAsFixed(2),
                            style: const TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // 表情 / 动作按钮
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildBtn('微笑', () => _setExpression('smile')),
                        _buildBtn('惊讶', () => _setExpression('surprised')),
                        _buildBtn('生气', () => _setExpression('angry')),
                        _buildBtn('待机', () => _startMotion('Idle', 0)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBtn(String label, VoidCallback onTap) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white24,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        textStyle: const TextStyle(fontSize: 12),
      ),
      onPressed: onTap,
      child: Text(label),
    );
  }
}
