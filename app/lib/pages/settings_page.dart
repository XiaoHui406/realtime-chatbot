import 'package:flutter/material.dart';
import '../services/live2d_server.dart';
import '../services/settings_service.dart';
import 'live2d_model_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _controller = TextEditingController();
  bool _obscureText = true;
  bool _hasApiKey = false;
  CallMode _callMode = CallMode.normal;
  bool _live2dAvailable = true;

  @override
  void initState() {
    super.initState();
    final settings = SettingsService();
    _controller.text = settings.apiKey;
    _hasApiKey = settings.apiKey.isNotEmpty;
    _callMode = settings.callMode;
    Live2DServer.isDistAvailable().then((v) {
      if (mounted) {
        setState(() => _live2dAvailable = v);
        if (!v && _callMode == CallMode.live2d) {
          _callMode = CallMode.normal;
          SettingsService().setCallMode(CallMode.normal);
        }
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = _controller.text.trim();
    await SettingsService().setApiKey(value);
    if (mounted) {
      setState(() => _hasApiKey = value.isNotEmpty);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API Key 已保存')),
      );
    }
  }

  Future<void> _setCallMode(CallMode mode) async {
    await SettingsService().setCallMode(mode);
    if (mounted) setState(() => _callMode = mode);
  }

  void _showLive2DGuide() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('如何开启 Live2D？'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('1. 从 Live2D 官网下载 Cubism SDK for Web'),
            SizedBox(height: 4),
            Text('2. 解压到 app/assets/live2d/CubismSdkForWeb-5-r.5/'),
            SizedBox(height: 4),
            Text('3. 在 app/assets/live2d/ 下执行：'),
            SizedBox(height: 4),
            Text(
              '   npm install && npm run build',
              style: TextStyle(
                  fontFamily: 'monospace', fontSize: 12),
            ),
            SizedBox(height: 4),
            Text('4. 重新运行应用前清除 Live2D 缓存（见 README）'),
            SizedBox(height: 12),
            Text(
              '详见 assets/live2d/README.md',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('通话模式',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('选择点击"通话"时进入的界面',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 12),
          SegmentedButton<CallMode>(
            segments: const [
              ButtonSegment(
                  value: CallMode.normal,
                  label: Text('普通通话'),
                  icon: Icon(Icons.call)),
              ButtonSegment(
                  value: CallMode.live2d,
                  label: Text('Live2D'),
                  icon: Icon(Icons.person)),
            ],
            selected: {_callMode},
            onSelectionChanged: _live2dAvailable
                ? (v) => _setCallMode(v.first)
                : null,
          ),
          if (!_live2dAvailable) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 16, color: Colors.orange),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    '未检测到 Cubism SDK，Live2D 不可用',
                    style: TextStyle(
                        color: Colors.orange,
                        fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: _showLive2DGuide,
              child: const Text(
                '如何开启 Live2D？',
                style: TextStyle(
                  color: Colors.blue,
                  fontSize: 13,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
          if (_callMode == CallMode.live2d && _live2dAvailable) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const Live2DModelPage()),
              ),
              icon: const Icon(Icons.manage_accounts, size: 20),
              label: const Text('管理 Live2D 模型'),
            ),
          ],
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(
                _hasApiKey ? Icons.check_circle : Icons.warning_amber_rounded,
                color: _hasApiKey ? Colors.green : Colors.orange,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                _hasApiKey ? 'API Key 已设置' : 'API Key 未设置',
                style: TextStyle(
                  color: _hasApiKey ? Colors.green : Colors.orange,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            obscureText: _obscureText,
            decoration: InputDecoration(
              labelText: 'API Key',
              hintText: '输入 API Key',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscureText ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscureText = !_obscureText),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '留空则不启用认证，后端需同步配置 AUTH_API_KEY',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
