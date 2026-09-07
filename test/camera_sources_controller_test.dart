import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamer_reboot/controllers/camera_sources_controller.dart';
import 'package:streamer_reboot/domain/stream_session.dart';

const camera = CameraDescription(
  name: 'HDMI capture',
  lensDirection: CameraLensDirection.external,
  sensorOrientation: 0,
);

class FakeCamera extends CameraController {
  FakeCamera(ResolutionPreset preset, this.failure) : super(camera, preset);
  final String? failure;
  bool disposed = false;

  @override
  Future<void> initialize() async {
    if (failure != null) throw CameraException('camera_error', failure);
    value = value.copyWith(
      isInitialized: true,
      previewSize: const Size(3840, 2160),
    );
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  for (final failure in [
    null,
    'Failed to enumerate camera media types',
    'Camera access denied',
  ]) {
    test('camera initialization handles $failure', () async {
      final attempts = <FakeCamera>[];
      final sources = CameraSourcesController(
        listCameras: () async => [camera],
        createCamera: (_, preset, fps) {
          expect(fps, 30);
          if (attempts.isNotEmpty) expect(attempts.last.disposed, isTrue);
          final next = FakeCamera(preset, attempts.isEmpty ? failure : null);
          attempts.add(next);
          return next;
        },
      );
      await sources.discover();
      final retries = failure == 'Failed to enumerate camera media types';
      expect(attempts.length, retries ? 2 : 1);
      expect(attempts.first.resolutionPreset, ResolutionPreset.high);
      if (retries) expect(attempts.last.resolutionPreset, ResolutionPreset.max);
      if (retries) {
        expect(
          sources.sources.single.controller!.value.previewSize,
          const Size(3840, 2160),
        );
      }
      expect(sources.sources.single.isReady, failure == null || retries);
      await sources.release();
      sources.dispose();
    });
  }

  test('uses configured capture resolution and frame rate', () async {
    ResolutionPreset? selectedPreset;
    int? selectedFps;
    final sources = CameraSourcesController(
      listCameras: () async => [camera],
      createCamera: (_, preset, fps) {
        selectedPreset = preset;
        selectedFps = fps;
        return FakeCamera(preset, null);
      },
    );
    sources.configure(
      captureResolution: CameraCaptureResolution.p1080,
      frameRate: StreamFrameRate.fps60,
    );

    await sources.discover();

    expect(selectedPreset, ResolutionPreset.veryHigh);
    expect(selectedFps, 60);
    await sources.release();
    sources.dispose();
  });
}
