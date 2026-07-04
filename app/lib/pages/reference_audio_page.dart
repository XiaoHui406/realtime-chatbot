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
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteAudio(ReferenceAudioInfo audio) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Audio'),
        content: Text('Delete "${audio.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
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
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
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
        title: const Text('Edit Reference Audio'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: tagsController,
              decoration: const InputDecoration(labelText: 'Tags'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Name cannot be empty'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              Navigator.of(ctx).pop(true);
            },
            child: const Text('Save'),
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
          const SnackBar(content: Text('Audio updated successfully')),
        );
        _loadAudios();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Edit failed: $e'), backgroundColor: Colors.red),
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
        title: const Text('Upload Reference Audio'),
        content: StatefulBuilder(
          builder: (context, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: tagsController,
                decoration: const InputDecoration(labelText: 'Tags'),
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
                label: Text(fileName ?? 'Select Audio File'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (filePath == null || nameController.text.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Please select a file and enter a name'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              Navigator.of(ctx).pop(true);
            },
            child: const Text('Upload'),
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
          const SnackBar(content: Text('Audio uploaded successfully')),
        );
        _loadAudios();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reference Audio'),
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
        label: const Text('Upload'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text('Error: $_error', style: const TextStyle(color: Colors.red)));
    }
    if (_audios.isEmpty) {
      return const Center(
        child: Text('No reference audio available', style: TextStyle(color: Colors.grey)),
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
              subtitle: Text(audio.tags.isNotEmpty ? audio.tags : 'No tags'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () => _editAudio(audio),
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Edit',
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _setAudio(audio.id),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Set'),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: () => _deleteAudio(audio),
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: 'Delete',
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
