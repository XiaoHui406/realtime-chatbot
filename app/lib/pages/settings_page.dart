import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    final settings = SettingsService();
    _controller.text = settings.apiKey;
    _hasApiKey = settings.apiKey.isNotEmpty;
    _callMode = settings.callMode;
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
            onSelectionChanged: (v) => _setCallMode(v.first),
          ),
          if (_callMode == CallMode.live2d) ...[
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
