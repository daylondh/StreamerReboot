part of 'ffmpeg_stream_engine.dart';

Future<Process> _startFfmpeg(List<String> arguments) async {
  for (final executable in _ffmpegCandidates) {
    try {
      return await Process.start(executable, arguments);
    } on ProcessException {
      // Try the next common installation location.
    }
  }
  throw StateError('FFmpeg is not installed.');
}

Future<bool> _isFfmpegInstalled() async {
  for (final executable in _ffmpegCandidates) {
    try {
      if ((await Process.run(executable, ['-version'])).exitCode == 0) {
        return true;
      }
    } on ProcessException {
      // Try the next candidate.
    }
  }
  return false;
}

List<String> get _ffmpegCandidates => [
  if (Platform.isWindows)
    '${File(Platform.resolvedExecutable).parent.path}\\ffmpeg.exe',
  'ffmpeg',
  if (Platform.isMacOS) ...[
    '/usr/local/bin/ffmpeg',
    '/opt/homebrew/bin/ffmpeg',
    '/opt/local/bin/ffmpeg',
  ],
];

String get _defaultVideoEncoder {
  if (Platform.isMacOS) return 'h264_videotoolbox';
  if (Platform.isWindows) return 'h264_mf';
  return 'libx264';
}

Future<String> _videoEncoder(
  VideoEncoderPreference preference, {
  required int width,
  required int height,
}) async {
  if (preference == VideoEncoderPreference.software) return 'libx264';
  if (Platform.isWindows) {
    final encoder = await _findWindowsHardwareEncoder(width, height);
    if (encoder != null) return encoder;
    if (preference == VideoEncoderPreference.automatic) return 'libx264';
    throw StateError(
      'No usable Windows hardware H.264 encoder was found. Church Streamer '
      'tested NVIDIA NVENC, AMD AMF, Intel Quick Sync, and Media Foundation. '
      'Update the graphics driver or package a full FFmpeg build, then try '
      'again.',
    );
  }
  return _defaultVideoEncoder;
}

final Map<String, Future<String?>> _windowsHardwareEncoderProbes = {};

Future<String?> _findWindowsHardwareEncoder(int width, int height) {
  final key = '${width}x$height';
  return _windowsHardwareEncoderProbes.putIfAbsent(
    key,
    () => _probeWindowsHardwareEncoders(width, height),
  );
}

Future<String?> _probeWindowsHardwareEncoders(int width, int height) async {
  // An encoder can be listed even though its driver or GPU session cannot be
  // opened. Encode one frame at the requested output size with each path so
  // a live stream—and especially a required 4K mode—never becomes the
  // capability test.
  for (final encoder in const [
    'h264_nvenc',
    'h264_amf',
    'h264_qsv',
    'h264_mf',
  ]) {
    for (final executable in _ffmpegCandidates) {
      try {
        final result = await Process.run(executable, [
          '-hide_banner',
          '-loglevel',
          'error',
          '-f',
          'lavfi',
          '-i',
          'color=c=black:s=${width}x$height:r=1:d=0.04',
          '-frames:v',
          '1',
          '-an',
          '-c:v',
          encoder,
          if (encoder == 'h264_mf') ...['-hw_encoding', '1'],
          '-f',
          'null',
          '-',
        ]);
        if (result.exitCode == 0) return encoder;
        break;
      } on ProcessException {
        // Try the next executable candidate.
      }
    }
  }
  return null;
}
