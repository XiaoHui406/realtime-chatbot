import 'dart:typed_data';

Uint8List createWavFromFloat32(Float32List samples, int sampleRate) {
  final int16Samples = Int16List(samples.length);
  for (int i = 0; i < samples.length; i++) {
    int16Samples[i] = (samples[i] * 32767).clamp(-32768, 32767).toInt();
  }
  return _createWavInt16(int16Samples, sampleRate);
}

Uint8List _createWavInt16(Int16List samples, int sampleRate) {
  final byteBuffer = BytesBuilder();
  final dataSize = samples.length * 2;
  final fileSize = 36 + dataSize;

  byteBuffer.add('RIFF'.codeUnits);
  byteBuffer.add(_int32Bytes(fileSize));
  byteBuffer.add('WAVE'.codeUnits);

  byteBuffer.add('fmt '.codeUnits);
  byteBuffer.add(_int32Bytes(16));
  byteBuffer.add(_int16Bytes(1));
  byteBuffer.add(_int16Bytes(1));
  byteBuffer.add(_int32Bytes(sampleRate));
  byteBuffer.add(_int32Bytes(sampleRate * 2));
  byteBuffer.add(_int16Bytes(2));
  byteBuffer.add(_int16Bytes(16));

  byteBuffer.add('data'.codeUnits);
  byteBuffer.add(_int32Bytes(dataSize));
  byteBuffer.add(samples.buffer.asUint8List());

  return byteBuffer.toBytes();
}

Float32List bytesToFloat32List(List<int> bytes) {
  final byteData = Uint8List.fromList(bytes).buffer.asByteData();
  final floatCount = byteData.lengthInBytes ~/ 4;
  final floatList = Float32List(floatCount);
  for (int i = 0; i < floatCount; i++) {
    floatList[i] = byteData.getFloat32(i * 4, Endian.little);
  }
  return floatList;
}

Uint8List _int32Bytes(int value) {
  final bytes = ByteData(4);
  bytes.setInt32(0, value, Endian.little);
  return bytes.buffer.asUint8List();
}

Uint8List _int16Bytes(int value) {
  final bytes = ByteData(2);
  bytes.setInt16(0, value, Endian.little);
  return bytes.buffer.asUint8List();
}
