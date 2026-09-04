import 'package:flutter_test/flutter_test.dart';
import 'package:streamer_reboot/services/ffmpeg_stream_engine.dart';

void main() {
  test('builds a YouTube-compatible FFmpeg tee pipeline', () {
    final arguments = FfmpegStreamEngine.buildArguments(
      videoPort: 41001,
      audioPort: 41002,
      width: 1280,
      height: 720,
      pixelFormat: 'bgra',
      videoEncoder: 'libx264',
      ingestionUrl: 'rtmps://youtube.example/live/secret-key',
      outputPath: '/recordings/Sunday Worship.mp4',
    );

    expect(arguments, containsAllInOrder(['-f', 'rawvideo']));
    expect(arguments, containsAllInOrder(['-video_size', '1280x720']));
    expect(arguments, contains('tcp://127.0.0.1:41001'));
    expect(arguments, contains('tcp://127.0.0.1:41002'));
    expect(arguments, containsAllInOrder(['-c:v', 'libx264']));
    expect(arguments, containsAllInOrder(['-c:a', 'aac']));
    expect(arguments, containsAllInOrder(['-f', 'tee']));
    expect(
      arguments.last,
      '[f=flv:flvflags=no_duration_filesize:onfail=abort]'
      'rtmps://youtube.example/live/secret-key|'
      '[f=mp4:movflags=+faststart:onfail=ignore]'
      '/recordings/Sunday Worship.mp4',
    );
  });

  test('allows VideoToolbox software fallback on macOS', () {
    final arguments = FfmpegStreamEngine.buildArguments(
      videoPort: 41001,
      audioPort: 41002,
      width: 1280,
      height: 720,
      pixelFormat: 'bgra',
      videoEncoder: 'h264_videotoolbox',
      ingestionUrl: 'rtmps://youtube.example/live/key',
      outputPath: '/recordings/service.mp4',
    );

    expect(arguments, containsAllInOrder(['-realtime', '1']));
    expect(arguments, containsAllInOrder(['-allow_sw', '1']));
  });
}
