import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';

class ReferenceAudioPage extends StatefulWidget {
  const ReferenceAudioPage({super.key});

  @override
  State<ReferenceAudioPage> createState() => _ReferenceAudioPageState();
}

class _ReferenceAudioPageState extends State<ReferenceAudioPage> {
  final _apiService = ApiService();
  List<ReferenceAudioInfo> _audios = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAudios();
  }

  Future<void> _loadAudios() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final audios = await _apiService.getReferenceAudios();
      if (mounted) {
        setState(() {
          _audios = audios;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _setAudio(int audioId) async {
    try {
      final result = await _apiService.setReferenceAudio(audioId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('错误: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteAudio(ReferenceAudioInfo audio) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除音频'),
        content: Text('确定要删除"${audio.name}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final result = await _apiService.deleteReferenceAudio(audio.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result)),
        );
        _loadAudios();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('错误: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _editAudio(ReferenceAudioInfo audio) async {
    final nameController = TextEditingController(text: audio.name);
    final tagsController = TextEditingController(text: audio.tags);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑参考音频'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: '名称'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: tagsController,
              decoration: const InputDecoration(labelText: '标签'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('名称不能为空'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              Navigator.of(ctx).pop(true);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (result != true) return;

    try {
      await _apiService.editReferenceAudio(
        audio.id,
        nameController.text,
        tagsController.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('音频更新成功')),
        );
        _loadAudios();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('编辑失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _uploadAudio() async {
    final nameController = TextEditingController();
    final tagsController = TextEditingController();
    String? filePath;
    String? fileName;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('上传参考音频'),
        content: StatefulBuilder(
          builder: (context, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: '名称'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: tagsController,
                decoration: const InputDecoration(labelText: '标签'),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () async {
                  final picked = await FilePicker.platform.pickFiles(
                    type: FileType.audio,
                  );
                  if (picked != null && picked.files.isNotEmpty) {
                    setDialogState(() {
                      filePath = picked.files.first.path;
                      fileName = picked.files.first.name;
                    });
                  }
                },
                icon: const Icon(Icons.audio_file),
                label: Text(fileName ?? '选择音频文件'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              if (filePath == null || nameController.text.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('请选择文件并输入名称'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              Navigator.of(ctx).pop(true);
            },
            child: const Text('上传'),
          ),
        ],
      ),
    );

    if (result != true || filePath == null) return;

    try {
      await _apiService.uploadReferenceAudio(
        filePath: filePath!,
        fileName: fileName!,
        name: nameController.text,
        tags: tagsController.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('音频上传成功')),
        );
        _loadAudios();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('上传失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('参考音频'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAudios,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploadAudio,
        icon: const Icon(Icons.add),
        label: const Text('上传'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text('错误: $_error', style: const TextStyle(color: Colors.red)));
    }
    if (_audios.isEmpty) {
      return const Center(
        child: Text('暂无参考音频', style: TextStyle(color: Colors.grey)),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadAudios,
      child: ListView.builder(
        itemCount: _audios.length,
        itemBuilder: (context, index) {
          final audio = _audios[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.multitrack_audio),
              title: Text(audio.name),
              subtitle: Text(audio.tags.isNotEmpty ? audio.tags : '无标签'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () => _editAudio(audio),
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: '编辑',
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _setAudio(audio.id),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('设为当前'),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: () => _deleteAudio(audio),
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: '删除',
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
