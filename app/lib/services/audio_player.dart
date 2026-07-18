import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';

/// 基于flutter_soloud的低延迟PCM流式播放器
///
/// 通过SoLoud的BufferStream把收到的PCM数据直接喂给音频引擎，
/// 全平台支持（含Windows桌面端），避免WAV封装、播放器启动的开销。
class AudioPlayerService {
  void Function(bool)? onPlayingChanged;

  final SoLoud _soloud = SoLoud.instance;
  Future<void>? _initFuture;
  AudioSource? _stream;
  bool _playRequested = false;
  bool _isPlaying = false;
  int _sampleRate = 0;

  Future<void> _ensureSetup(int sampleRate) async {
    if (!_soloud.isInitialized) {
      await (_initFuture ??= _soloud.init());
    }
    if (_stream != null && sampleRate == _sampleRate) return;
    // 采样率变化或首次播放时（重新）创建缓冲流
    await _disposeStream();
    _sampleRate = sampleRate;
    _createStream();
  }

  void _createStream() {
    _stream = _soloud.setBufferStream(
      // 仅限制单个流可写入的数据总量，不会预分配内存
      maxBufferSizeDuration: const Duration(hours: 3),
      // 已播放的数据即时释放，适合长时间实时会话
      bufferingType: BufferingType.released,
      // 无需预缓冲：数据由websocket推送，到达即播；
      // 缓冲区耗尽时通过onBuffering(isBuffering=true)检测本轮播放结束
      bufferingTimeNeeds: 0,
      sampleRate: _sampleRate,
      channels: Channels.mono,
      format: BufferType.f32le,
      onBuffering: _onBuffering,
    );
    _playRequested = false;
  }

  void _onBuffering(bool isBuffering, int handle, double time) {
    // 缓冲区耗尽，本轮播放结束
    if (isBuffering && _isPlaying) {
      _isPlaying = false;
      onPlayingChanged?.call(false);
    }
  }

  Future<void> playFloat32Pcm(Float32List samples, int sampleRate) async {
    await _ensureSetup(sampleRate);

    final bytes =
        samples.buffer.asUint8List(samples.offsetInBytes, samples.lengthInBytes);
    try {
      _soloud.addAudioDataStream(_stream!, bytes);
    } on SoLoudStreamEndedAlreadyCppException {
      // 写入总量达到上限导致流被标记结束，重建后继续
      await _disposeStream();
      _createStream();
      _soloud.addAudioDataStream(_stream!, bytes);
    }

    // 首次喂数据后开始播放（released类型的流只能play一次）；
    // 之后缓冲耗尽/恢复由引擎自动暂停/继续
    if (!_playRequested) {
      _playRequested = true;
      await _soloud.play(_stream!);
    }

    if (!_isPlaying) {
      _isPlaying = true;
      onPlayingChanged?.call(true);
      // 打点：本轮实际开始向音频设备喂数据
      // ignore: avoid_print
      print('playback started at '
          '${DateTime.now().millisecondsSinceEpoch / 1000.0}');
    }
  }

  void stop() {
    // 丢弃未播放的缓冲数据，播放随即因缓冲耗尽而静音；
    // 流保持存活，下一轮数据到达后自动继续播放
    final stream = _stream;
    if (stream != null && _soloud.isInitialized) {
      try {
        _soloud.resetBufferStream(stream);
      } on SoLoudException {
        // 重置失败则丢弃当前流，下次播放时重建
        _stream = null;
        _playRequested = false;
      }
    }
    if (_isPlaying) {
      _isPlaying = false;
      onPlayingChanged?.call(false);
    }
  }

  Future<void> _disposeStream() async {
    final stream = _stream;
    _stream = null;
    _playRequested = false;
    if (stream != null && _soloud.isInitialized) {
      await _soloud.disposeSource(stream);
    }
  }

  Future<void> dispose() async {
    final pendingInit = _initFuture;
    _initFuture = null;
    _stream = null;
    _playRequested = false;
    _isPlaying = false;
    if (pendingInit != null) {
      try {
        await pendingInit;
      } catch (_) {
        return;
      }
    }
    if (_soloud.isInitialized) {
      // 同步停止引擎并释放全部资源（含缓冲流）
      _soloud.deinit();
    }
  }
}
