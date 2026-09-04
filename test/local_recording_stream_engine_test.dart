import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:streamer_reboot/domain/stream_session.dart';
import 'package:streamer_reboot/services/stream_engine.dart';

class FakeVideoRecorder implements VideoRecorder {
  FakeVideoRecorder(this.temporaryDirectory, this.cameraName);

  final Directory temporaryDirectory;
  final String cameraName;
  int starts = 0;
  int stops = 0;

  @override
  Future<void> start() async {
    starts++;
  }

  @override
  Future<String> stop() async {
    stops++;
    final file = File('${temporaryDirectory.path}/$cameraName-$stops.mp4');
    await file.writeAsBytes([1, 2, 3]);
    return file.path;
  }
}

class ExistingFileVideoRecorder implements VideoRecorder {
  ExistingFileVideoRecorder(this.path);
  final String path;

  @override
  Future<void> start() async {}

  @override
  Future<String> stop() async => path;
}

Future<void> concatenateFakeSegments(
  List<String> inputPaths,
  String outputPath,
) async {
  final output = File(outputPath).openWrite();
  for (final path in inputPaths) {
    output.add(await File(path).readAsBytes());
  }
  await output.close();
}

void main() {
  late Directory temporaryDirectory;
  late Directory destinationDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'church-stream-source-',
    );
    destinationDirectory = await Directory.systemTemp.createTemp(
      'church-stream-output-',
    );
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
    await destinationDirectory.delete(recursive: true);
  });

  test('reports whether FFmpeg is available', () async {
    final availableEngine = LocalRecordingStreamEngine(
      recorderForCamera: (_) => null,
      ffmpegChecker: () async => true,
    );
    final unavailableEngine = LocalRecordingStreamEngine(
      recorderForCamera: (_) => null,
      ffmpegChecker: () async => false,
    );

    await availableEngine.checkFfmpegAvailability();
    await unavailableEngine.checkFfmpegAvailability();

    expect(availableEngine.ffmpegAvailability, FfmpegAvailability.available);
    expect(
      unavailableEngine.ffmpegAvailability,
      FfmpegAvailability.unavailable,
    );
  });

  test('records and saves a real local file through the lifecycle', () async {
    final recorder = FakeVideoRecorder(temporaryDirectory, 'wide');
    final engine = LocalRecordingStreamEngine(
      recorderForCamera: (_) => recorder,
      defaultDirectory: () async => destinationDirectory,
    );
    final session = StreamSession(title: 'Sunday: Worship', cameraName: 'wide');

    await engine.start(session);
    expect(engine.isRecording, isTrue);
    await engine.stop(session);

    expect(recorder.starts, 1);
    expect(recorder.stops, 1);
    expect(engine.recordedFiles, hasLength(1));
    expect(await File(engine.recordedFiles.single).readAsBytes(), [1, 2, 3]);
    expect(engine.recordedFiles.single, contains('Sunday- Worship'));
    expect(engine.trace.map((event) => event.stage), [
      RecordingLifecycleStage.starting,
      RecordingLifecycleStage.recording,
      RecordingLifecycleStage.stopping,
      RecordingLifecycleStage.finalizing,
      RecordingLifecycleStage.recordingSaved,
      RecordingLifecycleStage.stopped,
    ]);
  });

  test('camera changes produce one coherent recording file', () async {
    final wide = FakeVideoRecorder(temporaryDirectory, 'wide');
    final close = FakeVideoRecorder(temporaryDirectory, 'close');
    final recorders = {'wide': wide, 'close': close};
    final engine = LocalRecordingStreamEngine(
      recorderForCamera: (name) => recorders[name],
      defaultDirectory: () async => destinationDirectory,
      segmentMerger: concatenateFakeSegments,
    );
    final session = StreamSession(title: 'Service', cameraName: 'wide');

    await engine.start(session);
    await engine.switchCamera('close');
    await engine.stop(session);

    expect(wide.stops, 1);
    expect(close.starts, 1);
    expect(close.stops, 1);
    expect(engine.recordedFiles, hasLength(1));
    expect(engine.recordedFiles.single, isNot(contains('part-')));
    expect(await File(engine.recordedFiles.single).readAsBytes(), [
      1,
      2,
      3,
      1,
      2,
      3,
    ]);
    expect(
      engine.trace.map((event) => event.stage),
      containsAllInOrder([
        RecordingLifecycleStage.switchingCamera,
        RecordingLifecycleStage.stopping,
        RecordingLifecycleStage.finalizing,
        RecordingLifecycleStage.recordingSaved,
        RecordingLifecycleStage.stopped,
      ]),
    );
  });

  test('FFmpeg preserves moving video after a camera change', () async {
    final ffmpeg = await _availableFfmpeg();
    if (ffmpeg == null) return;
    final redPath = '${temporaryDirectory.path}/red.mp4';
    final bluePath = '${temporaryDirectory.path}/blue.mp4';
    await _makeColorClip(ffmpeg, redPath, 'red', '640x480', 24);
    await _makeColorClip(ffmpeg, bluePath, 'blue', '1280x720', 30);
    final engine = LocalRecordingStreamEngine(
      recorderForCamera: (name) =>
          ExistingFileVideoRecorder(name == 'red' ? redPath : bluePath),
      defaultDirectory: () async => destinationDirectory,
    );
    final session = StreamSession(title: 'Color test', cameraName: 'red');

    await engine.start(session);
    await engine.switchCamera('blue');
    await engine.stop(session);

    final firstPixel = await _pixelAt(ffmpeg, engine.recordedFiles.single, 0.2);
    final secondPixel = await _pixelAt(
      ffmpeg,
      engine.recordedFiles.single,
      0.8,
    );
    expect(firstPixel[0], greaterThan(firstPixel[2]));
    expect(secondPixel[2], greaterThan(secondPixel[0]));
  });
}

Future<String?> _availableFfmpeg() async {
  final candidates = [
    'ffmpeg',
    if (Platform.isMacOS) ...[
      '/usr/local/bin/ffmpeg',
      '/opt/homebrew/bin/ffmpeg',
      '/opt/local/bin/ffmpeg',
    ],
  ];
  for (final candidate in candidates) {
    try {
      if ((await Process.run(candidate, ['-version'])).exitCode == 0) {
        return candidate;
      }
    } on ProcessException {
      continue;
    }
  }
  return null;
}

Future<void> _makeColorClip(
  String ffmpeg,
  String path,
  String color,
  String size,
  int frameRate,
) async {
  final result = await Process.run(ffmpeg, [
    '-f',
    'lavfi',
    '-i',
    'color=c=$color:s=$size:r=$frameRate:d=0.6',
    '-f',
    'lavfi',
    '-i',
    'sine=frequency=440:duration=0.6',
    '-shortest',
    '-c:v',
    'mpeg4',
    '-c:a',
    'aac',
    '-y',
    path,
  ]);
  expect(result.exitCode, 0, reason: result.stderr.toString());
}

Future<List<int>> _pixelAt(String ffmpeg, String path, double seconds) async {
  final result = await Process.run(ffmpeg, [
    '-ss',
    '$seconds',
    '-i',
    path,
    '-frames:v',
    '1',
    '-vf',
    'scale=1:1',
    '-f',
    'rawvideo',
    '-pix_fmt',
    'rgb24',
    'pipe:1',
  ], stdoutEncoding: null);
  expect(result.exitCode, 0, reason: result.stderr.toString());
  return (result.stdout as List<int>).take(3).toList();
}
