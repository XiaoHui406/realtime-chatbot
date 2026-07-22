import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

const _assetPrefix = 'assets/live2d/dist/';

const _essentialRelPaths = [
  'index.html',
  'assets/index.js',
  'Core/live2dcubismcore.js',
  'Framework/Shaders/WebGL/vertshadersrc.vert',
  'Framework/Shaders/WebGL/vertshadersrcmasked.vert',
  'Framework/Shaders/WebGL/vertshadersrcsetupmask.vert',
  'Framework/Shaders/WebGL/vertshadersrccopy.vert',
  'Framework/Shaders/WebGL/vertshadersrcblend.vert',
  'Framework/Shaders/WebGL/fragshadersrcsetupmask.frag',
  'Framework/Shaders/WebGL/fragshadersrcpremultipliedalpha.frag',
  'Framework/Shaders/WebGL/fragshadersrcpremultipliedalphablend.frag',
  'Framework/Shaders/WebGL/fragshadersrcmaskpremultipliedalpha.frag',
  'Framework/Shaders/WebGL/fragshadersrcmaskinvertedpremultipliedalpha.frag',
  'Framework/Shaders/WebGL/fragshadersrccopy.frag',
  'Framework/Shaders/WebGL/fragshadersrccolorblend.frag',
  'Framework/Shaders/WebGL/fragshadersrcalphablend.frag',
];

class Live2DServer {
  HttpServer? _server;
  int? _port;
  String _docRoot;

  Live2DServer(this._docRoot);

  int get port => _port ?? 0;

  String get url => 'http://127.0.0.1:$port';

  static Future<String> findDistPath() async {
    final supportDir = await getApplicationSupportDirectory();
    final dest = '${supportDir.path}/live2d';
    final marker = File('$dest/.init_done');

    if (marker.existsSync()) {
      final coreJs = File('$dest/Core/live2dcubismcore.js');
      final aShader = File(
          '$dest/Framework/Shaders/WebGL/vertshadersrc.vert');
      if (coreJs.existsSync() && aShader.existsSync()) return dest;
      await marker.delete();
    }

    final cwdDir =
        Directory('${Directory.current.path}/assets/live2d/dist');
    if (cwdDir.existsSync()) {
      await _copyDir(cwdDir.path, dest);
      await marker.writeAsString('1');
      debugPrint('[Live2DServer] synced dist from cwd to $dest');
      return dest;
    }

    final exeDir = Directory(
        '${File(Platform.resolvedExecutable).parent.path}/assets/live2d/dist');
    if (exeDir.existsSync()) {
      await _copyDir(exeDir.path, dest);
      await marker.writeAsString('1');
      debugPrint('[Live2DServer] synced dist from exe to $dest');
      return dest;
    }

    final count = await _extractAssets(dest);
    if (count > 0) {
      await marker.writeAsString('1');
      debugPrint('[Live2DServer] extracted $count files from assets to $dest');
    }

    // always return dest — models are stored here, and
    // missing dist files are served from rootBundle on the fly
    await Directory(dest).create(recursive: true);
    return dest;
  }

  static Future<void> _copyDir(String src, String dst) async {
    final srcDir = Directory(src);
    await for (final entity in srcDir.list(recursive: true)) {
      if (entity is File) {
        final relPath = entity.path.substring(src.length);
        final destFile = File('$dst$relPath');
        await destFile.parent.create(recursive: true);
        await entity.copy(destFile.path);
      }
    }
  }

  static Future<int> _extractAssets(String dest) async {
    int count = 0;

    try {
      final manifestJson = await rootBundle.loadString('AssetManifest.json');
      final manifest = jsonDecode(manifestJson) as Map<String, dynamic>;
      for (final key in manifest.keys) {
        if (key is String && key.startsWith(_assetPrefix)) {
          final rel = key.substring(_assetPrefix.length);
          if (rel.isEmpty) continue;
          if (await _tryExtract(dest, key, rel)) count++;
        }
      }
    } catch (_) {
      debugPrint('[Live2DServer] AssetManifest not available');
    }

    // always try hardcoded essential files as supplement
    for (final rel in _essentialRelPaths) {
      final destFile = File('$dest/$rel');
      if (!destFile.existsSync()) {
        if (await _tryExtract(dest, '$_assetPrefix$rel', rel)) count++;
      }
    }
    return count;
  }

  static Future<bool> _tryExtract(String dest, String assetKey, String rel) async {
    try {
      final data = (await rootBundle.load(assetKey)).buffer.asUint8List();
      final destFile = File('$dest/$rel');
      await destFile.parent.create(recursive: true);
      await destFile.writeAsBytes(data);
      return true;
    } catch (e) {
      debugPrint('[Live2DServer] failed to extract $assetKey: $e');
      return false;
    }
  }

  static Future<bool> isDistAvailable() async {
    try {
      await rootBundle.load('assets/live2d/dist/Core/live2dcubismcore.js');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<int> start() async {
    if (_docRoot.isEmpty) {
      throw StateError('Live2D dist directory not found');
    }

    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;

    _server!.listen(_handleRequest);

    debugPrint('[Live2DServer] started on port $_port, docRoot=$_docRoot');
    return _port!;
  }

  void _handleRequest(HttpRequest request) async {
    String path = request.uri.path;
    if (path == '/') path = '/index.html';

    final sanitized = path.split('?').first;
    final file = File('$_docRoot$sanitized');

    if (file.existsSync()) {
      final ext = sanitized.split('.').last.toLowerCase();
      request.response.headers.contentType = _contentType(ext);
      request.response.headers.set('Access-Control-Allow-Origin', '*');
      file.openRead().pipe(request.response);
      return;
    }

    // fallback: serve from Flutter asset bundle
    final assetKey = '$_assetPrefix${sanitized.replaceFirst('/', '')}';
    try {
      final byteData = await rootBundle.load(assetKey);
      final ext = sanitized.split('.').last.toLowerCase();
      request.response.headers.contentType = _contentType(ext);
      request.response.headers.set('Access-Control-Allow-Origin', '*');
      request.response.add(byteData.buffer.asUint8List());
      request.response.close();
      return;
    } catch (_) {}

    debugPrint('[Live2DServer] 404: $sanitized');
    request.response.statusCode = 404;
    request.response.headers.contentType = ContentType.text;
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.write('404 Not Found: $sanitized');
    request.response.close();
  }

  ContentType _contentType(String ext) {
    switch (ext) {
      case 'html':
        return ContentType.html;
      case 'js':
        return ContentType('application', 'javascript', charset: 'utf-8');
      case 'json':
        return ContentType.json;
      case 'png':
        return ContentType('image', 'png');
      case 'moc3':
        return ContentType('application', 'octet-stream');
      case 'vert':
      case 'frag':
        return ContentType.text;
      default:
        return ContentType.binary;
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _port = null;
  }
}
