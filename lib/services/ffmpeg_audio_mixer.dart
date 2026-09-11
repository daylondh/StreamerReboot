part of 'ffmpeg_stream_engine.dart';

extension _FfmpegAudioMixer on FfmpegStreamEngine {
  void _startAudioMixer() {
    for (final source in audioSources.sources) {
      final queue = PcmQueue();
      _audioQueues[source] = queue;
      _audioSubscriptions.add(source.mixedAudio.stream.listen(queue.add));
    }
    // 20 ms of 48 kHz mono signed 16-bit PCM.
    const byteCount = 1920;
    _audioTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      final socket = _audioSocket;
      if (socket == null) return;
      final enabled = audioSources.sources
          .where((source) => source.enabled)
          .toList();
      if (enabled.isEmpty) {
        _writeAudio(socket, Uint8List(byteCount));
        return;
      }
      final chunks = [
        for (final source in enabled)
          _audioQueues[source]!.takeDelayed(
            byteCount,
            source.delayMs * 96, // 48 kHz, mono, 16-bit = 96 bytes/ms.
          ),
      ];
      final chunkData = [
        for (final chunk in chunks) ByteData.sublistView(chunk),
      ];
      final output = Uint8List(byteCount);
      final outputData = ByteData.sublistView(output);
      for (var offset = 0; offset < byteCount; offset += 2) {
        var mixed = 0;
        for (final data in chunkData) {
          mixed += data.getInt16(offset, Endian.little);
        }
        outputData.setInt16(offset, mixed.clamp(-32768, 32767), Endian.little);
      }
      _writeAudio(socket, output);
    });
  }

  void _writeAudio(Socket socket, Uint8List bytes) {
    try {
      socket.add(bytes);
    } catch (error) {
      _recordTransportError('audio', error);
    }
  }
}
