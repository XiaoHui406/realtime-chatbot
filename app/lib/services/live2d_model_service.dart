import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class Live2DModelInfo {
  final String id;
  String name;
  final String path;
  bool selected;
  final bool builtin;

  Live2DModelInfo({
    required this.id,
    required this.name,
    required this.path,
    this.selected = false,
    this.builtin = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'path': path,
        'selected': selected,
        'builtin': builtin,
      };

  factory Live2DModelInfo.fromJson(Map<String, dynamic> json) =>
      Live2DModelInfo(
        id: json['id'] as String,
        name: json['name'] as String,
        path: json['path'] as String,
        selected: json['selected'] as bool? ?? false,
        builtin: json['builtin'] as bool? ?? false,
      );
}

class Live2DModelService {
  static final Live2DModelService _instance = Live2DModelService._();
  factory Live2DModelService() => _instance;
  Live2DModelService._();

  static const _modelsJson = 'models.json';
  String? _basePath;

  Future<String> get _rootPath async {
    _basePath ??= '${(await getApplicationSupportDirectory()).path}/live2d';
    return _basePath!;
  }

  Future<File> get _metaFile async =>
      File('${await _rootPath}/$_modelsJson');

  Future<List<Live2DModelInfo>> _loadMeta() async {
    final f = await _metaFile;
    if (!f.existsSync()) return [];
    try {
      final root = await _rootPath;
      final list = jsonDecode(await f.readAsString()) as List;
      final models = list
          .map((e) => Live2DModelInfo.fromJson(e as Map<String, dynamic>))
          .toList();
      models.removeWhere((m) => !Directory('$root/${m.path}').existsSync());
      return models;
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveMeta(List<Live2DModelInfo> models) async {
    final f = await _metaFile;
    await f.parent.create(recursive: true);
    await f.writeAsString(
        jsonEncode(models.map((m) => m.toJson()).toList()));
  }

  Future<List<Live2DModelInfo>> listModels() async {
    return _loadMeta();
  }

  Future<Live2DModelInfo?> getSelected() async {
    final models = await listModels();
    if (models.isEmpty) return null;
    return models.firstWhere((m) => m.selected,
        orElse: () => models.first);
  }

  Future<void> selectModel(String id) async {
    final models = await _loadMeta();
    for (final m in models) {
      m.selected = m.id == id;
    }
    await _saveMeta(models);
  }

  Future<void> renameModel(String id, String newName) async {
    final models = await _loadMeta();
    final idx = models.indexWhere((m) => m.id == id);
    if (idx == -1) return;
    models[idx].name = newName;
    await _saveMeta(models);
  }

  Future<void> deleteModel(String id) async {
    final models = await _loadMeta();
    final idx = models.indexWhere((m) => m.id == id);
    if (idx == -1) return;
    final model = models[idx];
    if (model.builtin) return;

    final root = await _rootPath;
    final dir = Directory('$root/${model.path}');
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }

    models.removeAt(idx);
    if (model.selected && models.isNotEmpty) {
      models[0].selected = true;
    }
    await _saveMeta(models);
  }

  Future<String?> importZip(String zipPath) async {
    final root = await _rootPath;
    final tempDir = Directory('${root}/_tmp_${DateTime.now().millisecondsSinceEpoch}');

    try {
      final bytes = File(zipPath).readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);

      String? model3RelPath;
      final allNames = <String>[];
      for (final file in archive.files) {
        if (file.isFile) {
          allNames.add(file.name);
          if (file.name.endsWith('.model3.json')) {
            model3RelPath = file.name;
          }
        }
      }

      debugPrint('[Live2DModel] zip contents: $allNames');

      if (model3RelPath == null) return null;

      final normalized = model3RelPath.replaceAll('\\', '/');
      final parentDir =
          normalized.contains('/')
              ? normalized.substring(0, normalized.lastIndexOf('/'))
              : '';

      for (final file in archive.files) {
        if (file.isFile && file.content != null) {
          final destFile = File('${tempDir.path}/${file.name}');
          await destFile.parent.create(recursive: true);
          await destFile.writeAsBytes(file.content as List<int>);
        }
      }

      String modelDir = parentDir.isNotEmpty
          ? '${tempDir.path}/$parentDir'
          : tempDir.path;

      final modelName = model3RelPath
          .split('/')
          .last
          .replaceAll('.model3.json', '');

      var finalName = modelName;
      var suffix = 1;
      while (Directory('$root/models/$finalName').existsSync()) {
        finalName = '$modelName$suffix';
        suffix++;
      }

      final targetPath = '$root/models/$finalName';
      await Directory(targetPath).parent.create(recursive: true);
      await Directory(modelDir).rename(targetPath);

      final models = await _loadMeta();
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      models.add(Live2DModelInfo(
        id: id,
        name: finalName,
        path: 'models/$finalName/',
        selected: false,
      ));
      await _saveMeta(models);

      debugPrint('[Live2DModel] imported "$finalName" -> $targetPath');
      return id;
    } catch (e) {
      debugPrint('[Live2DModel] import failed: $e');
      return null;
    } finally {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    }
  }
}
