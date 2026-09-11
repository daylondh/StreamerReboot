part of 'ffmpeg_stream_engine.dart';

extension _FfmpegDiagnostics on FfmpegStreamEngine {
  Future<String> _createOutputPath(StreamSession session) async {
    final directory = session.recordingDirectory.isEmpty
        ? await _defaultDirectory()
        : Directory(session.recordingDirectory);
    await directory.create(recursive: true);
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final title = session.title
        .trim()
        .replaceAll(RegExp(r'[\/:*?"<>|]'), '-')
        .replaceAll(RegExp(r'\s+'), ' ');
    final baseName = '${title.isEmpty ? 'Church Stream' : title}-$timestamp';
    var output = File(
      '${directory.path}${Platform.pathSeparator}$baseName.mp4',
    );
    var duplicate = 2;
    while (await output.exists()) {
      output = File(
        '${directory.path}${Platform.pathSeparator}$baseName-$duplicate.mp4',
      );
      duplicate++;
    }
    return output.path;
  }

  String _ffmpegFailure(String fallback) {
    final ffmpegLines = _stderr
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (ffmpegLines.isNotEmpty) {
      final first = (ffmpegLines.length - 6).clamp(0, ffmpegLines.length);
      return ffmpegLines.sublist(first).join(' | ');
    }
    if (_transportDiagnostics.isNotEmpty) {
      return '$fallback ${_transportDiagnostics.last}';
    }
    return fallback;
  }

  String _sanitizeDiagnostic(String line) {
    final target = _sensitiveIngestionUrl;
    return target == null ? line : line.replaceAll(target, '[YouTube ingest]');
  }

  String _ffmpegPixelFormat(CameraImage frame) {
    return _cameraPixelFormat(frame);
  }

  String _cameraPixelFormat(CameraImage frame) {
    final raw = frame.format.raw.toString().toLowerCase();
    if (raw.contains('rgba')) return 'rgba';
    if (raw.contains('bgra')) return 'bgra';
    throw StateError('Unsupported camera pixel format: ${frame.format.raw}');
  }
}
