import 'package:flutter_test/flutter_test.dart';
import 'package:streamer_reboot/controllers/stream_controller.dart';
import 'package:streamer_reboot/domain/stream_session.dart';
import 'package:streamer_reboot/services/stream_engine.dart';
import 'package:streamer_reboot/services/stream_settings_store.dart';

class MemorySettingsStore implements StreamSettingsStore {
  MemorySettingsStore(this.settings);

  StreamTextSettings settings;

  @override
  Future<StreamTextSettings> load() async => settings;

  @override
  Future<void> save(StreamTextSettings settings) async {
    this.settings = settings;
  }
}

class ImmediateEngine implements StreamEngine {
  int starts = 0;
  int stops = 0;
  final List<String> cameraSwitches = [];
  StreamSession? startedSession;
  @override
  Future<void> start(StreamSession session) async {
    starts++;
    startedSession = session;
  }

  @override
  Future<void> stop(StreamSession session) async {
    stops++;
    stoppedSession = session;
  }

  StreamSession? stoppedSession;

  @override
  Future<void> switchCamera(String cameraName) async {
    cameraSwitches.add(cameraName);
  }
}

class FailingStartEngine extends ImmediateEngine {
  @override
  Future<void> start(StreamSession session) async {
    await super.start(session);
    throw StateError('setup interrupted');
  }
}

void main() {
  test('suggests a human-friendly service title', () {
    expect(
      StreamController.suggestedServiceTitle(DateTime(2026, 6, 28, 8)),
      'Fifth Sunday after Pentecost - Early Service',
    );
  });

  test(
    'refresh updates the suggestion but start preserves an edited name',
    () async {
      final engine = ImmediateEngine();
      final controller = StreamController(
        engine,
        now: DateTime(2026, 6, 28, 8),
      );
      controller.refreshSuggestedTitle(DateTime(2026, 11, 26, 12));
      expect(controller.session.title, 'Thanksgiving Day - Evening Service');

      controller.updateTitle('Thanksgiving Worship - Community Stream');
      await controller.toggleLive();
      expect(
        engine.startedSession?.title,
        'Thanksgiving Worship - Community Stream',
      );
    },
  );

  test('starts and stops through the engine boundary', () async {
    final engine = ImmediateEngine();
    final controller = StreamController(engine, now: DateTime(2026, 9, 6, 9));
    await controller.toggleLive();
    expect(controller.session.status, StreamStatus.live);
    expect(engine.starts, 1);
    await controller.toggleLive();
    expect(controller.session.status, StreamStatus.idle);
    expect(engine.stops, 1);
  });

  test('shutdown stops resources after an interrupted setup', () async {
    final engine = FailingStartEngine();
    final controller = StreamController(engine);

    await controller.toggleLive();
    expect(controller.session.status, StreamStatus.failed);

    await controller.shutdown();
    expect(engine.stops, 1);
    expect(controller.session.status, StreamStatus.idle);
  });

  test('requires a title', () async {
    final controller = StreamController(ImmediateEngine());
    controller.updateTitle('  ');
    await controller.toggleLive();
    expect(controller.session.status, StreamStatus.failed);
    expect(controller.session.error, contains('title'));
  });

  test('starts without local recording', () async {
    final engine = ImmediateEngine();
    final controller = StreamController(engine);
    controller.updateRecording(false);

    await controller.toggleLive();

    expect(controller.session.status, StreamStatus.live);
    expect(engine.startedSession?.recordLocally, isFalse);
  });

  test(
    'selects a camera before going live without switching the engine',
    () async {
      final engine = ImmediateEngine();
      final controller = StreamController(engine);

      await controller.selectCamera('Sanctuary wide');

      expect(controller.session.cameraName, 'Sanctuary wide');
      expect(engine.cameraSwitches, isEmpty);
      await controller.toggleLive();
      expect(engine.startedSession?.cameraName, 'Sanctuary wide');
    },
  );

  test('switches the active camera while live', () async {
    final engine = ImmediateEngine();
    final controller = StreamController(engine);
    await controller.selectCamera('Sanctuary wide');
    await controller.toggleLive();

    await controller.selectCamera('Lectern close-up');

    expect(engine.cameraSwitches, ['Lectern close-up']);
    expect(controller.session.cameraName, 'Lectern close-up');
    expect(controller.session.status, StreamStatus.live);
  });

  test(
    'passes startup and shutdown slate text through the lifecycle',
    () async {
      final engine = ImmediateEngine();
      final controller = StreamController(engine);
      controller.updateTitle('Sunday Worship');
      controller.updateStartupText('We will begin in a moment.');
      controller.updateShutdownText('Thank you for joining us.');

      await controller.toggleLive();
      expect(engine.startedSession?.title, 'Sunday Worship');
      expect(engine.startedSession?.startupText, 'We will begin in a moment.');
      await controller.toggleLive();
      expect(engine.stoppedSession?.shutdownText, 'Thank you for joining us.');
      expect(controller.session.startupText, 'We will begin in a moment.');
      expect(controller.session.shutdownText, 'Thank you for joining us.');
    },
  );

  test('loads and saves slate text between controller sessions', () async {
    final store = MemorySettingsStore(
      const StreamTextSettings(
        startupSplashEnabled: false,
        shutdownSplashEnabled: true,
        recordingDirectory: '/recordings/original',
        startupText: 'Welcome to worship.',
        shutdownText: 'Have a blessed week.',
      ),
    );
    final first = StreamController(ImmediateEngine(), settingsStore: store);
    await first.initialize();
    expect(first.session.startupSplashEnabled, isFalse);
    expect(first.session.shutdownSplashEnabled, isTrue);
    expect(first.session.recordingDirectory, '/recordings/original');
    expect(first.session.startupText, 'Welcome to worship.');
    expect(first.session.shutdownText, 'Have a blessed week.');

    first.updateStartupText('Starting soon.');
    first.updateShutdownText('See you next Sunday.');
    first.updateStartupSplashEnabled(true);
    first.updateShutdownSplashEnabled(false);
    first.updateRecordingDirectory('/recordings/new');
    await Future<void>.delayed(Duration.zero);

    final second = StreamController(ImmediateEngine(), settingsStore: store);
    await second.initialize();
    expect(second.session.startupSplashEnabled, isTrue);
    expect(second.session.shutdownSplashEnabled, isFalse);
    expect(second.session.recordingDirectory, '/recordings/new');
    expect(second.session.startupText, 'Starting soon.');
    expect(second.session.shutdownText, 'See you next Sunday.');
  });

  test('passes the recording destination to the stream engine', () async {
    final engine = ImmediateEngine();
    final controller = StreamController(engine);
    controller.updateRecordingDirectory('/recordings/services');

    await controller.toggleLive();

    expect(engine.startedSession?.recordingDirectory, '/recordings/services');
  });

  test(
    'passes independent splash options through the stream lifecycle',
    () async {
      final engine = ImmediateEngine();
      final controller = StreamController(engine);
      controller.updateStartupSplashEnabled(false);
      controller.updateShutdownSplashEnabled(true);

      await controller.toggleLive();
      expect(engine.startedSession?.startupSplashEnabled, isFalse);
      expect(engine.startedSession?.shutdownSplashEnabled, isTrue);
      await controller.toggleLive();
      expect(engine.stoppedSession?.startupSplashEnabled, isFalse);
      expect(engine.stoppedSession?.shutdownSplashEnabled, isTrue);
    },
  );
}
