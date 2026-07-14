import 'dart:typed_data';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';

/// 基于flutter_pcm_sound的低延迟PCM流式播放器
///
/// 收到的PCM数据直接喂给原生音频缓冲区，
/// 避免just_audio方案中WAV封装、data URI解析、播放器启动的开销。
class AudioPlayerService {
  void Function(bool)? onPlayingChanged;
  bool _isPlaying = false;
  bool _setupDone = false;
  int _sampleRate = 0;

  Future<void> _ensureSetup(int sampleRate) async {
    if (_setupDone && sampleRate == _sampleRate) return;
    if (_setupDone) {
      // 采样率变化时需要重新初始化
      await FlutterPcmSound.release();
    }
    _sampleRate = sampleRate;
    await FlutterPcmSound.setup(
      sampleRate: sampleRate,
      channelCount: 1,
      iosAudioCategory: IosAudioCategory.playback,
    );
    // 阈值设为0：不需要低缓冲回调（数据由websocket推送，而非拉取），
    // 只依赖缓冲区完全耗尽时的zero event来检测播放结束
    await FlutterPcmSound.setFeedThreshold(0);
    FlutterPcmSound.setFeedCallback(_onFeed);
    _setupDone = true;
  }

  void _onFeed(int remainingFrames) {
    // 缓冲区耗尽，播放结束
    if (remainingFrames == 0 && _isPlaying) {
      _isPlaying = false;
      onPlayingChanged?.call(false);
    }
  }

  Future<void> playFloat32Pcm(Float32List samples, int sampleRate) async {
    await _ensureSetup(sampleRate);

    // float32 -> int16
    final int16Samples = Int16List(samples.length);
    for (int i = 0; i < samples.length; i++) {
      int16Samples[i] =
          (samples[i] * 32767.0).round().clamp(-32768, 32767);
    }

    if (!_isPlaying) {
      _isPlaying = true;
      onPlayingChanged?.call(true);
      // 打点：本轮实际开始向音频设备喂数据
      // ignore: avoid_print
      print('playback started at '
          '${DateTime.now().millisecondsSinceEpoch / 1000.0}');
    }
    await FlutterPcmSound.feed(
        PcmArrayInt16(bytes: int16Samples.buffer.asByteData()));
  }

  void stop() {
    // flutter_pcm_sound没有flush接口，通过release丢弃未播放的缓冲数据
    if (_setupDone) {
      FlutterPcmSound.release();
      _setupDone = false;
    }
    if (_isPlaying) {
      _isPlaying = false;
      onPlayingChanged?.call(false);
    }
  }

  Future<void> dispose() async {
    await FlutterPcmSound.release();
    _setupDone = false;
    _isPlaying = false;
  }
}
