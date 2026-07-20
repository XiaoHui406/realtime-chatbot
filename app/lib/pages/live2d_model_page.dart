import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/live2d_model_service.dart';

class Live2DModelPage extends StatefulWidget {
  const Live2DModelPage({super.key});

  @override
  State<Live2DModelPage> createState() => _Live2DModelPageState();
}

class _Live2DModelPageState extends State<Live2DModelPage> {
  final _svc = Live2DModelService();
  List<Live2DModelInfo> _models = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final models = await _svc.listModels();
    if (mounted) setState(() { _models = models; _loading = false; });
  }

  Future<void> _importZip() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (result == null || result.files.isEmpty) return;
    if (result.files.first.path == null) return;

    setState(() => _loading = true);
    final id = await _svc.importZip(result.files.first.path!);
    await _refresh();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(id != null ? '模型导入成功' : '导入失败：未找到 .model3.json 文件'),
      ));
    }
  }

  Future<void> _select(String id) async {
    await _svc.selectModel(id);
    await _refresh();
  }

  Future<void> _rename(Live2DModelInfo model) async {
    final ctrl = TextEditingController(text: model.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名模型'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入新名称'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('确定')),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      await _svc.renameModel(model.id, result.trim());
      await _refresh();
    }
  }

  Future<void> _delete(Live2DModelInfo model) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除模型'),
        content: Text('确定要删除"${model.name}"吗？模型文件将被永久删除。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) {
      await _svc.deleteModel(model.id);
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live2D 模型管理'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _importZip,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _models.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.person_off,
                          size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('没有模型',
                          style:
                              TextStyle(fontSize: 16, color: Colors.grey)),
                      const SizedBox(height: 8),
                      const Text('点击右下角按钮导入模型 ZIP 包',
                          style:
                              TextStyle(fontSize: 13, color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _models.length,
                  itemBuilder: (context, index) {
                    final model = _models[index];
                    return _modelCard(model);
                  },
                ),
    );
  }

  Widget _modelCard(Live2DModelInfo model) {
    final isSelected = model.selected;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(
                color: Theme.of(context).colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(
              Icons.person,
              size: 40,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(model.name,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
                      if (model.builtin) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('内置',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    model.builtin ? '默认模型，不可删除' : model.path,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary, size: 22)
            else
              TextButton(
                onPressed: () => _select(model.id),
                child: const Text('选择'),
              ),
            if (!model.builtin) ...[
              IconButton(
                icon: const Icon(Icons.edit, size: 20),
                onPressed: () => _rename(model),
                tooltip: '重命名',
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () => _delete(model),
                tooltip: '删除',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
