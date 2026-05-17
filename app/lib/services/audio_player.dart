import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'wav_utils.dart';

class _AudioItem {
  final Float32List samples;
  final int sampleRate;
  _AudioItem(this.samples, this.sampleRate);
}

class AudioPlayerService {
  final AudioPlayer _player = AudioPlayer();
  final Queue<_AudioItem> _queue = Queue();
  bool _isPlaying = false;
  StreamSubscription? _completeSub;
  void Function(bool)? onPlayingChanged;

  AudioPlayerService() {
    _completeSub = _player.onPlayerComplete.listen((_) {
      _playNext();
    });
  }

  Future<void> playFloat32Pcm(Float32List samples, int sampleRate) async {
    _queue.add(_AudioItem(samples, sampleRate));
    if (!_isPlaying) {
      _playNext();
    }
  }

  void _playNext() {
    if (_queue.isEmpty) {
      _isPlaying = false;
      onPlayingChanged?.call(false);
      return;
    }

    _isPlaying = true;
    onPlayingChanged?.call(true);
    final item = _queue.removeFirst();
    final wavBytes = createWavFromFloat32(item.samples, item.sampleRate);
    _player.play(BytesSource(wavBytes));
  }

  void stop() {
    _queue.clear();
    _player.stop();
    _isPlaying = false;
    onPlayingChanged?.call(false);
  }

  Future<void> dispose() async {
    _completeSub?.cancel();
    _queue.clear();
    await _player.dispose();
  }
}
