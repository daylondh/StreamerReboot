import 'dart:async';
import 'dart:io';
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

  test('PCM queue prevents audio delay from growing with clock drift', () {
    final queue = PcmQueue(maxBufferBytes: 64);
    queue.add(Uint8List.fromList([1, 2, 3, 4, 5, 6]));

    expect(queue.takeDelayed(2, 4), [1, 2]);
    expect(queue.length, 4);

    // Capture supplies four bytes while the mixer consumes two. The oldest
    // two surplus bytes must be dropped so the requested four-byte delay is
    // preserved instead of silently growing to six bytes.
    queue.add(Uint8List.fromList([7, 8, 9, 10]));
    expect(queue.takeDelayed(2, 4), [5, 6]);
    expect(queue.length, 4);

    for (var tick = 0; tick < 1000; tick++) {
      queue.add(Uint8List.fromList([11, 12, 13]));
      queue.takeDelayed(2, 4);
      expect(queue.length, lessThanOrEqualTo(4));
    }
  });

  test('PCM queue preserves requested delay through an underrun', () {
    final queue = PcmQueue(maxBufferBytes: 32);
    queue.add(Uint8List.fromList([1, 2, 3, 4, 5, 6]));

    expect(queue.takeDelayed(2, 4), [1, 2]);
    expect(queue.takeDelayed(2, 4), [0, 0]);
    expect(queue.length, 4);

    queue.add(Uint8List.fromList([7]));
    expect(queue.takeDelayed(2, 4), [3, 0]);
    expect(queue.length, 4);
  });

  test(
    'video delay delivers frames when capture exceeds output rate',
    () async {
      final received = <List<int>>[];
      final controller = StreamController<List<int>>();
      final subscription = controller.stream.listen(received.add);
      final sink = IOSink(controller.sink);
      final queue = DelayedVideoQueue();
      final pump = Timer.periodic(const Duration(milliseconds: 5), (timer) {
        queue.add(
          Uint8List.fromList([timer.tick]),
          const Duration(milliseconds: 40),
          sink,
          (error) => fail('Unexpected delayed video write error: $error'),
          frameRate: 10,
        );
      });

      await Future<void>.delayed(const Duration(milliseconds: 160));

      expect(received.where((bytes) => bytes.first > 0), isNotEmpty);
      pump.cancel();
      queue.clear();
      await sink.close();
      await subscription.cancel();
    },
  );

  test(
    'video queue preserves nominal frame rate despite clock jitter',
    () async {
      var now = DateTime.now();
      final controller = StreamController<List<int>>();
      final subscription = controller.stream.listen((_) {});
      final sink = IOSink(controller.sink);
      final queue = DelayedVideoQueue(now: () => now);

      for (var frame = 0; frame < 10; frame++) {
        queue.add(
          Uint8List.fromList([frame]),
          const Duration(seconds: 1),
          sink,
          (error) => fail('Unexpected delayed video write error: $error'),
          frameRate: 30,
        );
        // Real 30 fps capture clocks commonly round to 33 ms rather than the
        // ideal repeating 33.333 ms interval.
        now = now.add(const Duration(milliseconds: 33));
      }

      expect(queue.bufferedFrameCount, 10);
      queue.clear();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sink.close();
      await subscription.cancel();
    },
  );

  test('video clock catches up after an event-loop stall', () async {
    var now = DateTime.now();
    final controller = StreamController<List<int>>();
    final subscription = controller.stream.listen((_) {});
    final sink = IOSink(controller.sink);
    final queue = DelayedVideoQueue(now: () => now);
    queue.add(
      Uint8List.fromList([1]),
      Duration.zero,
      sink,
      (error) => fail('Unexpected video write error: $error'),
      frameRate: 24,
    );
    expect(queue.framesWritten, 1);

    now = now.add(const Duration(milliseconds: 250));
    queue.pumpClock();

    expect(queue.framesWritten, 7);
    queue.clear();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await sink.close();
    await subscription.cancel();
  });

  for (final frameRate in [24, 30, 60]) {
    test('video queue holds frames at $frameRate fps for the delay', () async {
      final controller = StreamController<List<int>>();
      final firstCameraFrame = Completer<Duration>();
      final stopwatch = Stopwatch()..start();
      final subscription = controller.stream.listen((bytes) {
        if (bytes.first == 7 && !firstCameraFrame.isCompleted) {
          firstCameraFrame.complete(stopwatch.elapsed);
        }
      });
      final sink = IOSink(controller.sink);
      final queue = DelayedVideoQueue();

      queue.add(
        Uint8List.fromList([7]),
        const Duration(milliseconds: 150),
        sink,
        (error) => fail('Unexpected delayed video write error: $error'),
        frameRate: frameRate,
      );

      final deliveredAt = await firstCameraFrame.future.timeout(
        const Duration(seconds: 1),
      );
      expect(
        deliveredAt,
        greaterThanOrEqualTo(const Duration(milliseconds: 120)),
      );
      queue.clear();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sink.close();
      await subscription.cancel();
    });
  }

  test('video queue honors the full 1500 ms delay at 60 fps', () async {
    final controller = StreamController<List<int>>();
    final firstCameraFrame = Completer<Duration>();
    final stopwatch = Stopwatch()..start();
    final subscription = controller.stream.listen((bytes) {
      if (bytes.first == 1 && !firstCameraFrame.isCompleted) {
        firstCameraFrame.complete(stopwatch.elapsed);
      }
    });
    final sink = IOSink(controller.sink);
    final queue = DelayedVideoQueue();
    final pump = Timer.periodic(const Duration(milliseconds: 16), (_) {
      queue.add(
        Uint8List.fromList([1]),
        const Duration(milliseconds: 1500),
        sink,
        (error) => fail('Unexpected delayed video write error: $error'),
        frameRate: 60,
      );
    });

    final deliveredAt = await firstCameraFrame.future.timeout(
      const Duration(seconds: 3),
    );
    expect(
      deliveredAt,
      greaterThanOrEqualTo(const Duration(milliseconds: 1400)),
    );
    pump.cancel();
    queue.clear();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await sink.close();
    await subscription.cancel();
  });

  test('startup slate remains visible while video delay primes', () async {
    final received = <List<int>>[];
    final controller = StreamController<List<int>>();
    final subscription = controller.stream.listen(received.add);
    final sink = IOSink(controller.sink);
    final queue = DelayedVideoQueue();

    queue.add(
      Uint8List.fromList([9]),
      Duration.zero,
      sink,
      (error) => fail('Unexpected slate write error: $error'),
      frameRate: 30,
    );
    await Future<void>.delayed(const Duration(milliseconds: 45));
    queue.clear(preserveLastOutput: true);
    received.clear();
    queue.add(
      Uint8List.fromList([7]),
      const Duration(milliseconds: 120),
      sink,
      (error) => fail('Unexpected camera write error: $error'),
      frameRate: 30,
    );

    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(received, isNotEmpty);
    expect(received, everyElement(equals([9])));
    await Future<void>.delayed(const Duration(milliseconds: 90));
    expect(received, contains(equals([7])));
    queue.clear();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await sink.close();
    await subscription.cancel();
  });

  test('preserves 4K capture dimensions in the Windows encoder input', () {
    final arguments = FfmpegStreamEngine.buildArguments(
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
      audioPort: 41002,
      width: 1920,
      height: 1080,
      pixelFormat: 'bgra',
      videoEncoder: 'h264_nvenc',
      ingestionUrl: 'rtmps://youtube.example/live/key',
    );
    final amf = FfmpegStreamEngine.buildArguments(
      audioPort: 41002,
      width: 1920,
      height: 1080,
      pixelFormat: 'bgra',
      videoEncoder: 'h264_amf',
      ingestionUrl: 'rtmps://youtube.example/live/key',
    );
    final qsv = FfmpegStreamEngine.buildArguments(
      audioPort: 41002,
      width: 1920,
      height: 1080,
      pixelFormat: 'bgra',
      videoEncoder: 'h264_qsv',
      ingestionUrl: 'rtmps://youtube.example/live/key',
    );

    expect(nvenc, containsAllInOrder(['-preset', 'p1', '-tune', 'll']));
    expect(nvenc, containsAllInOrder(['-pix_fmt', 'nv12']));
    expect(
      amf,
      containsAllInOrder(['-usage', 'lowlatency', '-quality', 'speed']),
    );
    expect(amf, containsAllInOrder(['-pix_fmt', 'nv12']));
    expect(qsv, containsAllInOrder(['-preset', 'veryfast']));
    expect(qsv, containsAllInOrder(['-pix_fmt', 'nv12']));
  });

  test('builds a YouTube-compatible FFmpeg tee pipeline', () {
    final arguments = FfmpegStreamEngine.buildArguments(
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
    expect(arguments, contains('pipe:0'));
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
    expect(arguments, containsAllInOrder(['-pix_fmt', 'yuv420p']));
  });

  test('adds an aspect-preserving FFmpeg downscale filter', () {
    final arguments = FfmpegStreamEngine.buildArguments(
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

  test('uses steady rawvideo timing without rewriting audio timestamps', () {
    final arguments = FfmpegStreamEngine.buildArguments(
      audioPort: 41002,
      width: 1920,
      height: 1080,
      pixelFormat: 'bgra',
      videoEncoder: 'libx264',
      ingestionUrl: 'rtmps://youtube.example/live/key',
    );

    final videoInputIndex = arguments.indexOf('pipe:0');
    final audioInputIndex = arguments.indexOf('tcp://127.0.0.1:41002');
    expect(videoInputIndex, lessThan(audioInputIndex));
    expect(arguments, isNot(contains('-use_wallclock_as_timestamps')));
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
