import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/live2d_server.dart';
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

class _ChatDetailPageState extends State<ChatDetailPage>
    with WidgetsBindingObserver {
  final _api = ApiService();
  final _scrollController = ScrollController();

  List<ChatbotMessageInfo> _messages = [];
  bool _loading = true;

  /// 通话结束后需要继续刷新，好让工具调用产生的图片消息出现
  Timer? _refreshTimer;
  static const Duration _refreshInterval = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadMessages(initial: true);
  }

  @override
  void dispose() {
    _stopRefresh();
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 回到前台时立刻补一次，避免停留在后台期间漏掉的消息要等一个轮询周期
    if (state == AppLifecycleState.resumed) {
      _loadMessages();
    }
  }

  /// 加载消息
  ///
  /// [initial] 为 true 时显示加载态；轮询刷新只在内容真正变化时才 setState，
  /// 否则会不断重建列表、打断用户查看图片。
  Future<void> _loadMessages({bool initial = false}) async {
    if (initial) setState(() => _loading = true);
    try {
      final messages = await _api.getSessionMessages(widget.sessionId);
      if (!mounted) return;
      if (initial || !sameMessageList(_messages, messages)) {
        final hadNoMessages = _messages.isEmpty;
        setState(() {
          _messages = messages;
          _loading = false;
        });
        // 首次进入历史时滚到底部，直接看到最新内容（含刚生成的图片）
        if (initial && hadNoMessages) _scrollToBottom();
      } else if (_loading) {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (!mounted) return;
      if (initial) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController
          .jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  /// 通话期间不做轮询：通话页独占录音与网络，且结束时本页会重新加载
  void _startRefresh() {
    _refreshTimer ??= Timer.periodic(_refreshInterval, (_) {
      if (!mounted) return;
      _loadMessages();
    });
  }

  void _stopRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  Future<void> _startCall() async {
    // 在 async gap 之前取出 navigator，避免 await 之后再用 context
    final navigator = Navigator.of(context);
    final mode = SettingsService().callMode;
    final useLive2D =
        mode == CallMode.live2d && await Live2DServer.isDistAvailable();
    if (useLive2D) {
      await navigator.push(
        MaterialPageRoute(
            builder: (_) =>
                Live2DCallPage(sessionId: widget.sessionId)),
      );
    } else {
      await navigator.push(
        MaterialPageRoute(
            builder: (_) => CallPage(sessionId: widget.sessionId)),
      );
    }
    // 通话已结束，先把最终消息拉全，再开始周期性刷新等待工具图片
    await _loadMessages();
    _startRefresh();
    _scrollToBottom();
  }

  /// 从多模态 content 中取出纯文本部分
  ///
  /// 注意：拍照 / 相册选图产生的消息只有 image_url part、没有 text part，
  /// 因此这里返回空字符串是正常的，图片由 [ChatbotMessageInfo.imageDataUrls] 渲染。
  String _extractText(dynamic content) {
    if (content == null) return '';
    if (content is String) return content;
    if (content is List) {
      return content
          .map((part) =>
              (part is Map<String, dynamic>) ? part['text'] as String? ?? '' : '')
          .join();
    }
    return content.toString();
  }

  /// 需要渲染的消息（过滤掉 system 与 tool 结果）
  List<ChatbotMessageInfo> get _visibleMessages => _messages
      .where((msg) => !msg.isSystem && msg.role != 'tool')
      .toList();

  @override
  Widget build(BuildContext context) {
    final visibleMessages = _visibleMessages;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? '对话'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : visibleMessages.isEmpty
              ? const Center(child: Text('还没有消息，点击通话按钮开始', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: visibleMessages.length,
                  itemBuilder: (context, index) =>
                      _buildMessageBubble(visibleMessages[index]),
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

  Widget _buildMessageBubble(ChatbotMessageInfo msg) {
    final isUser = msg.isUser;
    final isToolCalling = msg.role == 'assistant' && msg.content == null;
    // 工具图片由后端以 role=user 的多模态消息存入，这里标记一下来源，
    // 否则用户看到"自己发了一张图"会困惑
    final isToolImage = isUser && msg.imageDataUrls.isNotEmpty;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75),
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
        child: isToolCalling
            ? Text(
                '正在调用工具...',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              )
            : _buildBubbleContent(msg, isToolImage: isToolImage),
      ),
    );
  }

  Widget _buildBubbleContent(ChatbotMessageInfo msg,
      {required bool isToolImage}) {
    final text = _extractText(msg.content);
    final images = msg.imageDataUrls;

    final children = <Widget>[];

    if (isToolImage) {
      children.add(Padding(
        padding: EdgeInsets.only(bottom: images.isEmpty ? 0 : 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image, size: 14, color: Colors.grey.shade700),
            const SizedBox(width: 4),
            Text(
              images.length > 1 ? '工具获取的图片 (${images.length})' : '工具获取的图片',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
        ),
      ));
    }

    if (text.isNotEmpty) {
      children.add(Text(text, style: const TextStyle(fontSize: 15)));
    }

    for (var i = 0; i < images.length; i++) {
      children.add(Padding(
        padding: EdgeInsets.only(top: children.isEmpty ? 0 : 8),
        child: _buildImage(images[i], index: i, total: images.length),
      ));
    }

    if (children.isEmpty) {
      // content 存在但既无文本也无可识别图片时的兜底，避免出现空白气泡
      children.add(Text(
        '（无可显示的内容）',
        style: TextStyle(
          fontSize: 15,
          color: Colors.grey.shade600,
          fontStyle: FontStyle.italic,
        ),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _buildImage(String dataUrl, {required int index, required int total}) {
    // 历史消息里的图片是 base64 内联数据，直接用 Image.memory 渲染，
    // 不走网络加载，离线也能看
    final bytes = decodeImageDataUrl(dataUrl);

    if (bytes == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined,
              size: 16, color: Colors.grey.shade700),
          const SizedBox(width: 6),
          Text('图片解析失败',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
        ],
      );
    }

    final maxWidth = MediaQuery.of(context).size.width * 0.75 - 28;

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: GestureDetector(
        onTap: () => _openImageViewer(bytes, index: index, total: total),
        child: Image.memory(
          bytes,
          width: maxWidth,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          // 交给 Image 控件自己按比例撑高，避免被 Column 拉伸变形
          errorBuilder: (context, error, stackTrace) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined,
                  size: 16, color: Colors.grey.shade700),
              const SizedBox(width: 6),
              Text('图片无法显示',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
            ],
          ),
        ),
      ),
    );
  }

  void _openImageViewer(Uint8List bytes, {required int index, required int total}) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.of(ctx).pop(),
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: InteractiveViewer(
                  maxScale: 6,
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                total > 1 ? '${index + 1} / $total  ·  点击任意处关闭' : '点击任意处关闭',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
