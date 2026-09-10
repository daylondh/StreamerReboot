import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:streamer_reboot/services/ffmpeg_stream_engine.dart';
import 'package:streamer_reboot/domain/stream_session.dart';

void main() {
  test('PCM queue stays bounded during a long-running capture', () {
    final queue = PcmQueue(maxBufferBytes: 8);

    queue.add(Uint8List.fromList([1, 2, 3, 4, 5, 6]));
    queue.add(Uint8List.fromList([7, 8, 9, 10, 11, 12]));

    expect(queue.length, 8);
    expect(queue.take(8), [5, 6, 7, 8, 9, 10, 11, 12]);
  });

  test('PCM queue preserves silence while an audio delay is priming', () {
    final queue = PcmQueue(maxBufferBytes: 32);
    queue.add(Uint8List.fromList([1, 2, 3, 4]));

    expect(queue.takeDelayed(2, 4), [0, 0]);
    expect(queue.length, 4);
    queue.add(Uint8List.fromList([5, 6]));
    expect(queue.takeDelayed(2, 4), [1, 2]);
  });

  test('preserves 4K capture dimensions in the Windows encoder input', () {
    final arguments = FfmpegStreamEngine.buildArguments(
      videoPort: 41001,
      audioPort: 41002,
      width: 3840,
      height: 2160,
      pixelFormat: 'bgra',
      videoEncoder: 'h264_mf',
      ingestionUrl: 'rtmps://youtube.example/live/key',
    );

    expect(arguments, containsAllInOrder(['-video_size', '3840x2160']));
    expect(arguments, containsAllInOrder(['-c:v', 'h264_mf']));
    expect(arguments, containsAllInOrder(['-scenario', 'live_streaming']));
    expect(arguments, isNot(contains('-hw_encoding')));
  });

  test('forces Windows hardware encoding only when explicitly requested', () {
    final arguments = FfmpegStreamEngine.buildArguments(
      videoPort: 41001,
      audioPort: 41002,
      width: 1280,
      height: 720,
      pixelFormat: 'bgra',
      videoEncoder: 'h264_mf',
      forceHardwareEncoding: true,
      ingestionUrl: 'rtmps://youtube.example/live/key',
    );

    expect(
      arguments,
      containsAllInOrder([
        '-c:v',
        'h264_mf',
        '-scenario',
        'live_streaming',
        '-hw_encoding',
        '1',
      ]),
    );
  });

  test('uses low-latency vendor hardware encoder options', () {
    final nvenc = FfmpegStreamEngine.buildArguments(
      videoPort: 41001,
      audioPort: 41002,
      width: 1920,
      height: 1080,
      pixelFormat: 'bgra',
      videoEncoder: 'h264_nvenc',
      ingestionUrl: 'rtmps://youtube.example/live/key',
    );
    final amf = FfmpegStreamEngine.buildArguments(
      videoPort: 41001,
      audioPort: 41002,
      width: 1920,
      height: 1080,
      pixelFormat: 'bgra',
      videoEncoder: 'h264_amf',
      ingestionUrl: 'rtmps://youtube.example/live/key',
    );
    final qsv = FfmpegStreamEngine.buildArguments(
      videoPort: 41001,
      audioPort: 41002,
      width: 1920,
      height: 1080,
      pixelFormat: 'bgra',
      videoEncoder: 'h264_qsv',
      ingestionUrl: 'rtmps://youtube.example/live/key',
    );

    expect(nvenc, containsAllInOrder(['-preset', 'p1', '-tune', 'll']));
    expect(
      amf,
      containsAllInOrder(['-usage', 'lowlatency', '-quality', 'speed']),
    );
    expect(qsv, containsAllInOrder(['-preset', 'veryfast']));
  });

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

  test('publishes without adding a local recording output', () {
    final arguments = FfmpegStreamEngine.buildArguments(
      videoPort: 41001,
      audioPort: 41002,
      width: 1280,
      height: 720,
      pixelFormat: 'bgra',
      videoEncoder: 'libx264',
      ingestionUrl: 'rtmps://youtube.example/live/key',
    );

    expect(
      arguments.last,
      '[f=flv:flvflags=no_duration_filesize:onfail=abort]'
      'rtmps://youtube.example/live/key',
    );
    expect(arguments.last, isNot(contains('[f=mp4')));
    expect(
      arguments,
      containsAllInOrder([
        '-c:v',
        'libx264',
        '-preset',
        'ultrafast',
        '-tune',
        'zerolatency',
      ]),
    );
  });

  test('adds an aspect-preserving FFmpeg downscale filter', () {
    final arguments = FfmpegStreamEngine.buildArguments(
      videoPort: 41001,
      audioPort: 41002,
      width: 3840,
      height: 2160,
      pixelFormat: 'bgra',
      videoEncoder: 'h264_mf',
      ingestionUrl: 'rtmps://youtube.example/live/key',
      outputResolution: StreamOutputResolution.p1080,
    );

    expect(
      arguments,
      containsAllInOrder([
        '-vf',
        r'setpts=PTS-STARTPTS,crop=trunc(min(iw\,ih*16/9)/2)*2:'
            r'trunc(min(ih\,iw*9/16)/2)*2,scale=1920:1080,setsar=1',
      ]),
    );
  });

  test('applies selected bitrate and frame rate to FFmpeg', () {
    final arguments = FfmpegStreamEngine.buildArguments(
      videoPort: 41001,
      audioPort: 41002,
      width: 1920,
      height: 1080,
      pixelFormat: 'bgra',
      videoEncoder: 'libx264',
      ingestionUrl: 'rtmps://youtube.example/live/key',
      videoBitrate: 6000,
      frameRate: 24,
    );

    expect(arguments, containsAllInOrder(['-framerate', '24']));
    expect(arguments, containsAllInOrder(['-fps_mode', 'cfr', '-r', '24']));
    expect(arguments, containsAllInOrder(['-b:v', '6000k']));
    expect(arguments, containsAllInOrder(['-maxrate', '6000k']));
    expect(arguments, containsAllInOrder(['-bufsize', '12000k']));
    expect(arguments, containsAllInOrder(['-g', '48']));
  });

  test('uses wall-clock video timing without rewriting audio timestamps', () {
    final arguments = FfmpegStreamEngine.buildArguments(
      videoPort: 41001,
      audioPort: 41002,
      width: 1920,
      height: 1080,
      pixelFormat: 'bgra',
      videoEncoder: 'libx264',
      ingestionUrl: 'rtmps://youtube.example/live/key',
    );

    expect(
      arguments.where((value) => value == '-use_wallclock_as_timestamps'),
      hasLength(1),
    );
    final wallClockIndex = arguments.indexOf('-use_wallclock_as_timestamps');
    final videoInputIndex = arguments.indexOf('tcp://127.0.0.1:41001');
    final audioInputIndex = arguments.indexOf('tcp://127.0.0.1:41002');
    expect(wallClockIndex, lessThan(videoInputIndex));
    expect(videoInputIndex, lessThan(audioInputIndex));
    expect(
      arguments,
      containsAllInOrder([
        '-vf',
        r'setpts=PTS-STARTPTS,crop=trunc(min(iw\,ih*16/9)/2)*2:'
            r'trunc(min(ih\,iw*9/16)/2)*2,setsar=1',
      ]),
    );
    expect(arguments, isNot(contains('-af')));
  });
}
