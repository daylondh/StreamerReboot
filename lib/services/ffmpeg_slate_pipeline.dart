part of 'ffmpeg_stream_engine.dart';

extension _FfmpegSlatePipeline on FfmpegStreamEngine {
  Future<void> _playStartupSlate(Uint8List bytes, Duration duration) async {
    await _playSlateUntil(bytes, _startupSlateRelease!.future);
    await _playSlate(bytes, duration, keepActive: true);
    await _crossfade(bytes, toSlate: false);
  }

  Future<void> _finishStartupSlate() async {
    final release = _startupSlateRelease;
    if (release == null) return;
    if (!release.isCompleted) release.complete();
    // Keep the splash visible for its full configured program duration after
    // YouTube has made the broadcast visible to viewers.
    await Future<void>.delayed(_startupSlateDuration + _fadeDuration);
    _startupSlateRelease = null;
  }

  Future<void> _playSlateUntil(Uint8List bytes, Future<void> until) async {
    final socket = _videoSocket;
    if (socket == null) return;
    _slateTimer?.cancel();
    _videoQueue.clear();
    _slateActive = true;

    _queueSlateFrame(socket, bytes);
    _slateTimer = Timer.periodic(
      _videoFrameInterval,
      (_) => _queueSlateFrame(socket, bytes),
    );
    await until;
  }

  Future<void> _playSlate(
    Uint8List bytes,
    Duration duration, {
    bool keepActive = false,
  }) async {
    final socket = _videoSocket;
    if (socket == null) return;
    _slateTimer?.cancel();
    final generation = ++_slateGeneration;
    _videoQueue.clear();
    _slateActive = true;

    _queueSlateFrame(socket, bytes);
    _slateTimer = Timer.periodic(
      _videoFrameInterval,
      (_) => _queueSlateFrame(socket, bytes),
    );
    await Future<void>.delayed(duration);
    if (generation != _slateGeneration) return;
    _slateTimer?.cancel();
    _slateTimer = null;
    if (!keepActive) _slateActive = false;
  }

  void _queueSlateFrame(Socket socket, Uint8List bytes) {
    _videoQueue.add(
      bytes,
      Duration.zero,
      socket,
      (error) => _recordTransportError('video', error),
      frameRate: _frameRate,
    );
  }

  Duration get _videoFrameInterval => Duration(
    microseconds: (Duration.microsecondsPerSecond / _frameRate).round(),
  );

  static const _fadeDuration = Duration(milliseconds: 600);

  Future<void> _crossfade(Uint8List slate, {required bool toSlate}) async {
    _slateTimer?.cancel();
    _slateTimer = null;
    _videoQueue.clear();
    _fadeSlate = slate;
    _fadeStartedAt = DateTime.now();
    _fadingToSlate = toSlate;
    _slateActive = false;
    await Future<void>.delayed(_fadeDuration);
    _fadeSlate = null;
    _fadeStartedAt = null;
    _slateActive = toSlate;
  }

  Uint8List _applyFade(Uint8List camera) {
    final slate = _fadeSlate;
    final startedAt = _fadeStartedAt;
    if (slate == null || startedAt == null || slate.length != camera.length) {
      return camera;
    }
    final elapsed = DateTime.now().difference(startedAt).inMicroseconds;
    final progress = (elapsed / _fadeDuration.inMicroseconds).clamp(0.0, 1.0);
    final cameraWeight = ((_fadingToSlate ? 1 - progress : progress) * 256)
        .round();
    final slateWeight = 256 - cameraWeight;
    final output = Uint8List(camera.length);
    for (var index = 0; index < camera.length; index += 4) {
      output[index] =
          (camera[index] * cameraWeight + slate[index] * slateWeight) >> 8;
      output[index + 1] =
          (camera[index + 1] * cameraWeight + slate[index + 1] * slateWeight) >>
          8;
      output[index + 2] =
          (camera[index + 2] * cameraWeight + slate[index + 2] * slateWeight) >>
          8;
      output[index + 3] = 255;
    }
    return output;
  }

  Future<Uint8List> _renderSlate({
    String? title,
    required String additionalText,
    required String backgroundPath,
  }) async {
    final width = _frameWidth!;
    final height = _frameHeight!;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..color = const ui.Color(0xff050f13),
    );
    if (backgroundPath.isNotEmpty) {
      try {
        final imageBytes = await File(backgroundPath).readAsBytes();
        final codec = await ui.instantiateImageCodec(imageBytes);
        final frame = await codec.getNextFrame();
        final background = frame.image;
        final sourceAspect = background.width / background.height;
        final targetAspect = width / height;
        final sourceRect = sourceAspect > targetAspect
            ? ui.Rect.fromLTWH(
                (background.width - background.height * targetAspect) / 2,
                0,
                background.height * targetAspect,
                background.height.toDouble(),
              )
            : ui.Rect.fromLTWH(
                0,
                (background.height - background.width / targetAspect) / 2,
                background.width.toDouble(),
                background.width / targetAspect,
              );
        canvas.drawImageRect(
          background,
          sourceRect,
          ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          ui.Paint(),
        );
        background.dispose();
        codec.dispose();
        canvas.drawRect(
          ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          ui.Paint()..color = const ui.Color(0x66000000),
        );
      } catch (error) {
        logMessage('[Splash] Could not load background image: $error');
      }
    }

    final content = [
      if (title != null && title.trim().isNotEmpty) title.trim(),
      if (additionalText.trim().isNotEmpty) additionalText.trim(),
    ];
    if (content.isEmpty) content.add('Thank you for joining us.');
    final paragraph =
        (ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: ui.TextAlign.center))
            ..pushStyle(
              ui.TextStyle(
                color: const ui.Color(0xffffffff),
                fontSize: math.max(24, width / 28),
                fontWeight: ui.FontWeight.w600,
                height: 1.35,
              ),
            ))
          ..addText(content.join('\n\n'));
    final laidOut = paragraph.build()
      ..layout(ui.ParagraphConstraints(width: width * .8));
    canvas.drawParagraph(
      laidOut,
      ui.Offset(width * .1, (height - laidOut.height) / 2),
    );

    final image = await recorder.endRecording().toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    final rgba = data!.buffer.asUint8List();
    if (_pixelFormat == 'rgba') return Uint8List.fromList(rgba);
    final bgra = Uint8List.fromList(rgba);
    for (var index = 0; index < bgra.length; index += 4) {
      final red = bgra[index];
      bgra[index] = bgra[index + 2];
      bgra[index + 2] = red;
    }
    return bgra;
  }
}
