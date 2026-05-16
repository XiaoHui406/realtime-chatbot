import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'wav_utils.dart';

class AudioPlayerService {
  final AudioPlayer _player = AudioPlayer();

  Future<void> playFloat32Pcm(Float32List samples, int sampleRate) async {
    final wavBytes = createWavFromFloat32(samples, sampleRate);
    await _player.play(BytesSource(wavBytes));
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}
