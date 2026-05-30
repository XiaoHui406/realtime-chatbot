import 'dart:async';
import 'dart:typed_data';
import 'package:just_audio/just_audio.dart';
import 'wav_utils.dart';

class AudioPlayerService {
  final AudioPlayer _player = AudioPlayer();
  final ConcatenatingAudioSource _playlist = ConcatenatingAudioSource(children: []);
  StreamSubscription? _stateSub;
  void Function(bool)? onPlayingChanged;
  bool _sourceSet = false;
  bool _isPlaying = false;

  AudioPlayerService() {
    _stateSub = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed && _isPlaying) {
        _isPlaying = false;
        onPlayingChanged?.call(false);
      }
    });
  }

  Future<void> playFloat32Pcm(Float32List samples, int sampleRate) async {
    final wavBytes = createWavFromFloat32(samples, sampleRate);
    final dataUri = Uri.dataFromBytes(wavBytes, mimeType: 'audio/wav');
    final source = AudioSource.uri(dataUri);

    if (!_sourceSet) {
      await _player.setAudioSource(_playlist);
      _sourceSet = true;
    }

    await _playlist.add(source);

    // Resume if player had stopped/completed before the new chunk arrived
    if (!_player.playing) {
      _player.play();
      if (!_isPlaying) {
        _isPlaying = true;
        onPlayingChanged?.call(true);
      }
    }
  }

  void stop() {
    _player.stop();
    _playlist.clear();
    _sourceSet = false;
    _isPlaying = false;
    onPlayingChanged?.call(false);
  }

  Future<void> dispose() async {
    _stateSub?.cancel();
    await _player.dispose();
  }
}
