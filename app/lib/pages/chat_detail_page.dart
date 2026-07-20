import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/settings_service.dart';
import 'call_page.dart';
import 'live2d_call_page.dart';

class ChatDetailPage extends StatefulWidget {
  final int sessionId;
  final String? title;

  const ChatDetailPage({super.key, required this.sessionId, this.title});

  @override
  State<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends State<ChatDetailPage> {
  final _api = ApiService();
  List<ChatbotMessageInfo> _messages = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    setState(() => _loading = true);
    try {
      final messages = await _api.getSessionMessages(widget.sessionId);
      if (mounted) setState(() { _messages = messages; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _startCall() async {
    final mode = SettingsService().callMode;
    if (mode == CallMode.live2d) {
      await Navigator.of(context).push(
        MaterialPageRoute(
            builder: (_) =>
                Live2DCallPage(sessionId: widget.sessionId)),
      );
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
            builder: (_) => CallPage(sessionId: widget.sessionId)),
      );
    }
    _loadMessages();
  }

  String _extractText(dynamic content) {
    if (content == null) return '';
    if (content is String) return content;
    if (content is List) {
      return content
          .map((part) => (part is Map<String, dynamic>) ? part['text'] as String? ?? '' : '')
          .join('');
    }
    return content.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? '对话'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _messages.isEmpty
              ? const Center(child: Text('还没有消息，点击通话按钮开始', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    if (msg.isSystem || msg.role == 'tool') return const SizedBox.shrink();
                    final isToolCalling = msg.role == 'assistant' && msg.content == null;
                    final isUser = msg.isUser;
                    return Align(
                      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                        decoration: BoxDecoration(
                          color: isToolCalling
                              ? Colors.grey.shade300
                              : isUser
                                  ? Theme.of(context).colorScheme.primaryContainer
                                  : Colors.grey.shade200,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: Radius.circular(isUser ? 16 : 4),
                            bottomRight: Radius.circular(isUser ? 4 : 16),
                          ),
                        ),
                        child: Text(
                          isToolCalling ? '正在调用工具...' : _extractText(msg.content),
                          style: TextStyle(
                            fontSize: 15,
                            color: isToolCalling ? Colors.grey.shade600 : null,
                            fontStyle: isToolCalling ? FontStyle.italic : null,
                          ),
                        ),
                      ),
                    );
                  },
                ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _startCall,
              icon: const Icon(Icons.call),
              label: const Text('通话', style: TextStyle(fontSize: 16)),
            ),
          ),
        ),
      ),
    );
  }
}
