import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamer_reboot/app.dart';
import 'package:streamer_reboot/controllers/audio_sources_controller.dart';
import 'package:streamer_reboot/controllers/camera_sources_controller.dart';
import 'package:streamer_reboot/controllers/stream_controller.dart';
import 'package:streamer_reboot/domain/stream_session.dart';
import 'package:streamer_reboot/services/ffmpeg_stream_engine.dart';
import 'package:streamer_reboot/services/youtube_live_service.dart';

class _NoCameras extends CameraSourcesController {
  @override
  Future<void> discover() async {}
}

class _NoAudio extends AudioSourcesController {
  @override
  Future<void> discover() async {}
}

void main() {
  testWidgets('settings retain focus when entering and clearing text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('church_streamer/media_permissions'),
      (_) async => {'camera': 'granted', 'microphone': 'granted'},
    );
    final audio = _NoAudio();
    final engine = FfmpegStreamEngine(
      cameraForName: (_) => null,
      audioSources: audio,
      ingestionUrl: () => null,
    );
    final controller = StreamController(engine)..updateTitle('');
    await tester.pumpWidget(
      MaterialApp(
        // Leave room for the test font in the unrelated fixed-width audio panel.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(0.8)),
          child: child!,
        ),
        home: StreamDashboard(
          controller: controller,
          cameraSources: _NoCameras(),
          audioSources: audio,
          recordingEngine: engine,
          youtube: YouTubeLiveService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('application-settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('stream-quality-settings')), findsOneWidget);
    expect(find.byKey(const Key('device-settings')), findsOneWidget);
    expect(find.byKey(const Key('splash-settings')), findsOneWidget);
    await tester.tap(find.byKey(const Key('stream-quality-settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('output-resolution')), findsOneWidget);
    await tester.tap(find.byKey(const Key('output-resolution')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('720p').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(controller.session.outputResolution, StreamOutputResolution.p720);
    await tester.tap(find.byKey(const Key('splash-settings')));
    await tester.pumpAndSettle();
    expect(find.text('Startup splash'), findsOneWidget);
    expect(find.text('Shutdown splash'), findsOneWidget);
    expect(find.text('Show stream name'), findsNWidgets(2));
    expect(find.text('Background image'), findsNWidgets(2));
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    for (final key in ['service-title', 'startup-text', 'shutdown-text']) {
      final field = find.byKey(Key(key));
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pump();
      final editable = find.descendant(
        of: field,
        matching: find.byType(EditableText),
      );
      final focus = tester.widget<EditableText>(editable).focusNode;
      expect(focus.hasFocus, isTrue, reason: key);
      for (final value in ['a', 'ab', '', 'c']) {
        // Simulate typing on the current input connection without refocusing.
        tester.testTextInput.enterText(value);
        await tester.pump();
        expect(
          tester.widget<EditableText>(editable).focusNode,
          same(focus),
          reason: key,
        );
        expect(focus.hasFocus, isTrue, reason: '$key after "$value"');
        expect(tester.widget<TextField>(field).controller!.text, value);
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
