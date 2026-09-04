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
      RecordingLifecycleStage.segmentSaved,
      RecordingLifecycleStage.stopped,
    ]);
  });

  test('camera changes create consecutive recording segments', () async {
    final wide = FakeVideoRecorder(temporaryDirectory, 'wide');
    final close = FakeVideoRecorder(temporaryDirectory, 'close');
    final recorders = {'wide': wide, 'close': close};
    final engine = LocalRecordingStreamEngine(
      recorderForCamera: (name) => recorders[name],
      defaultDirectory: () async => destinationDirectory,
    );
    final session = StreamSession(title: 'Service', cameraName: 'wide');

    await engine.start(session);
    await engine.switchCamera('close');
    await engine.stop(session);

    expect(wide.stops, 1);
    expect(close.starts, 1);
    expect(close.stops, 1);
    expect(engine.recordedFiles, hasLength(2));
    expect(engine.recordedFiles.last, contains('part-2'));
  });
}
