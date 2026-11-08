part of 'ffmpeg_stream_engine.dart';

extension _FfmpegDiagnostics on FfmpegStreamEngine {
  static const _progressFields = {
    'bitrate',
    'drop_frames',
    'dup_frames',
    'fps',
    'frame',
    'out_time',
    'out_time_ms',
    'out_time_us',
    'progress',
    'speed',
    'stream_0_0_q',
    'total_size',
  };

  bool _captureFfmpegProgress(String line) {
    final separator = line.indexOf('=');
    if (separator <= 0) return false;
    final key = line.substring(0, separator);
    if (!_progressFields.contains(key)) return false;
    _ffmpegProgress[key] = line.substring(separator + 1);
    if (key == 'progress') {
      logMessage(
        '[FFmpeg progress] frame=${_ffmpegProgress['frame'] ?? '?'} '
        'fps=${_ffmpegProgress['fps'] ?? '?'} '
        'time=${_ffmpegProgress['out_time'] ?? '?'} '
        'speed=${_ffmpegProgress['speed'] ?? '?'} '
        'dup=${_ffmpegProgress['dup_frames'] ?? '0'} '
        'drop=${_ffmpegProgress['drop_frames'] ?? '0'}',
      );
    }
    return true;
  }

  void _startStreamHealthDiagnostics() {
    _streamHealthTimer?.cancel();
    _streamHealthClock = Stopwatch()..start();
    _lastStreamHealthAt = Duration.zero;
    _lastHealthVideoFrames = _videoQueue.framesWritten;
    _lastHealthAudioChunks = _audioChunksWritten;
    _streamHealthTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _logStreamHealth(),
    );
  }

  void _logStreamHealth() {
    final elapsed = _streamHealthClock?.elapsed ?? Duration.zero;
    final interval = elapsed - _lastStreamHealthAt;
    final eventLoopLag = math.max(interval.inMilliseconds - 5000, 0);
    final videoFrames = _videoQueue.framesWritten;
    final audioChunks = _audioChunksWritten;
    final videoDelta = videoFrames >= _lastHealthVideoFrames
        ? videoFrames - _lastHealthVideoFrames
        : videoFrames;
    final audioDelta = audioChunks >= _lastHealthAudioChunks
        ? audioChunks - _lastHealthAudioChunks
        : audioChunks;
    final rssMiB = ProcessInfo.currentRss / (1024 * 1024);
    logMessage(
      '[Stream health] interval=${interval.inMilliseconds}ms '
      'eventLoopLag=${eventLoopLag}ms rss=${rssMiB.toStringAsFixed(1)}MiB '
      'videoFrames=$videoDelta audioChunks=$audioDelta '
      'videoDelayQueue=${_videoQueue.bufferedFrameCount}',
    );
    _lastStreamHealthAt = elapsed;
    _lastHealthVideoFrames = videoFrames;
    _lastHealthAudioChunks = audioChunks;
  }

  void _stopStreamHealthDiagnostics() {
    _streamHealthTimer?.cancel();
    _streamHealthTimer = null;
    _streamHealthClock?.stop();
    _streamHealthClock = null;
    _ffmpegProgress.clear();
  }

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
