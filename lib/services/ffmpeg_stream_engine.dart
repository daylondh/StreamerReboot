import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../controllers/audio_sources_controller.dart';
import '../domain/stream_session.dart';
import 'stream_engine.dart';

typedef CameraControllerResolver = CameraController? Function(String name);
typedef CameraDelayResolver = int Function(String name);
typedef IngestionUrlResolver = String? Function();
typedef FfmpegProcessStarter = Future<Process> Function(List<String> arguments);

/// Publishes camera and microphone data to YouTube while writing the same
/// encoded program to a local MP4 archive.
class FfmpegStreamEngine extends ChangeNotifier
    implements StreamEngine, StreamProcessMonitor, StartupSlateController {
  FfmpegStreamEngine({
    required this.cameraForName,
    CameraDelayResolver? cameraDelayForName,
    required this.audioSources,
    required this.ingestionUrl,
    Future<Directory> Function()? defaultDirectory,
    FfmpegProcessStarter? processStarter,
    Future<bool> Function()? ffmpegChecker,
  }) : cameraDelayForName = cameraDelayForName ?? ((_) => 0),
       _defaultDirectory = defaultDirectory ?? getApplicationDocumentsDirectory,
       _processStarter = processStarter ?? _startFfmpeg,
       _ffmpegChecker = ffmpegChecker ?? _isFfmpegInstalled;

  final CameraControllerResolver cameraForName;
  final CameraDelayResolver cameraDelayForName;
  final AudioSourcesController audioSources;
  final IngestionUrlResolver ingestionUrl;
  final Future<Directory> Function() _defaultDirectory;
  final FfmpegProcessStarter _processStarter;
  final Future<bool> Function() _ffmpegChecker;

  final List<RecordingLifecycleEvent> _trace = [];
  final List<String> _recordedFiles = [];
  final List<String> _stderr = [];
  final List<String> _transportDiagnostics = [];
  final List<StreamSubscription<Uint8List>> _audioSubscriptions = [];
  final Map<AudioSource, _PcmQueue> _audioQueues = {};

  FfmpegAvailability _ffmpegAvailability = FfmpegAvailability.checking;
  Process? _process;
  CameraController? _camera;
  String? _activeCameraName;
  Socket? _videoSocket;
  Socket? _audioSocket;
  ServerSocket? _videoServer;
  ServerSocket? _audioServer;
  Timer? _audioTimer;
  Timer? _slateTimer;
  int _slateGeneration = 0;
  final _DelayedVideoQueue _videoQueue = _DelayedVideoQueue();
  bool _slateActive = false;
  Uint8List? _startupSlate;
  Uint8List? _shutdownSlate;
  Completer<void>? _startupSlateRelease;
  StreamSubscription<String>? _stderrSubscription;
  int? _frameWidth;
  int? _frameHeight;
  String? _pixelFormat;
  String? _outputPath;
  String? _sensitiveIngestionUrl;
  Object? _transportError;
  bool _stopping = false;

  List<RecordingLifecycleEvent> get trace => List.unmodifiable(_trace);
  List<String> get recordedFiles => List.unmodifiable(_recordedFiles);
  bool get isRecording => _process != null;
  FfmpegAvailability get ffmpegAvailability => _ffmpegAvailability;
  @override
  Future<int> get processExitCode {
    final process = _process;
    if (process == null) throw StateError('FFmpeg is not running.');
    return process.exitCode;
  }

  @override
  String get diagnosticSummary =>
      _ffmpegFailure('FFmpeg stopped before YouTube detected incoming video.');

  Future<void> checkFfmpegAvailability() async {
    _ffmpegAvailability = FfmpegAvailability.checking;
    notifyListeners();
    _ffmpegAvailability = await _ffmpegChecker()
        ? FfmpegAvailability.available
        : FfmpegAvailability.unavailable;
    notifyListeners();
  }

  @override
  Future<void> start(StreamSession session) async {
    if (_process != null) throw StateError('FFmpeg is already publishing.');
    final cameraName = session.cameraName;
    final target = ingestionUrl();
    if (cameraName == null) throw StateError('Select a camera first.');
    if (target == null) throw StateError('YouTube ingest is not ready.');
    final camera = cameraForName(cameraName);
    if (camera == null || !camera.value.isInitialized) {
      throw StateError('Camera "$cameraName" is not ready.');
    }

    _trace.clear();
    _recordedFiles.clear();
    _stderr.clear();
    _transportDiagnostics.clear();
    _transportError = null;
    _addEvent(RecordingLifecycleStage.starting, cameraName);
    try {
      final firstFrame = Completer<CameraImage>();
      _camera = camera;
      _activeCameraName = cameraName;
      await camera.startImageStream((frame) {
        if (!firstFrame.isCompleted) firstFrame.complete(frame);
        _writeVideoFrame(frame);
      });
      final frame = await firstFrame.future.timeout(const Duration(seconds: 5));
      _frameWidth = frame.width;
      _frameHeight = frame.height;
      _pixelFormat = _ffmpegPixelFormat(frame);
      if (session.startupSplashEnabled) {
        _startupSlate = await _renderSlate(
          title: session.title,
          additionalText: session.startupText,
        );
      }
      if (session.shutdownSplashEnabled) {
        _shutdownSlate = await _renderSlate(
          additionalText: session.shutdownText,
        );
      }

      _videoServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      _audioServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final videoConnection = _videoServer!.first;
      final audioConnection = _audioServer!.first;
      _outputPath = session.recordLocally
          ? await _createOutputPath(session)
          : null;
      _sensitiveIngestionUrl = target;
      final arguments = buildArguments(
        videoPort: _videoServer!.port,
        audioPort: _audioServer!.port,
        width: frame.width,
        height: frame.height,
        pixelFormat: _pixelFormat!,
        videoEncoder: _defaultVideoEncoder,
        ingestionUrl: target,
        outputPath: _outputPath,
      );
      final process = await _processStarter(arguments);
      _process = process;
      _stderrSubscription = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            final diagnostic = _sanitizeDiagnostic(line);
            _stderr.add(diagnostic);
            if (_stderr.length > 30) _stderr.removeAt(0);
            debugPrint('[FFmpeg] $diagnostic');
          });
      _videoSocket = await videoConnection.timeout(const Duration(seconds: 5));
      _audioSocket = await audioConnection.timeout(const Duration(seconds: 5));
      _consumeSocketErrors(_videoSocket!, 'video');
      _consumeSocketErrors(_audioSocket!, 'audio');
      await _videoServer?.close();
      await _audioServer?.close();
      _videoServer = null;
      _audioServer = null;
      _startAudioMixer();
      final startupSlate = _startupSlate;
      if (startupSlate != null) {
        _startupSlateRelease = Completer<void>();
        unawaited(_playStartupSlate(startupSlate));
      }

      final earlyExit = await Future.any<Object?>([
        process.exitCode,
        Future<void>.delayed(const Duration(milliseconds: 500)),
      ]);
      if (earlyExit is int) {
        throw StateError(_ffmpegFailure('FFmpeg exited with code $earlyExit.'));
      }
      _addEvent(RecordingLifecycleStage.recording, cameraName);
    } catch (_) {
      await _tearDownMedia(killProcess: true);
      rethrow;
    }
  }

  @override
  Future<void> switchCamera(String cameraName) async {
    final next = cameraForName(cameraName);
    if (next == null || !next.value.isInitialized) {
      throw StateError('Camera "$cameraName" is not ready.');
    }
    final previous = _camera;
    final previousName = _activeCameraName;
    if (previous == null) throw StateError('No stream is active.');
    _addEvent(RecordingLifecycleStage.switchingCamera, cameraName);
    await previous.stopImageStream();
    _camera = next;
    _activeCameraName = cameraName;
    _videoQueue.clear();
    try {
      var describedFormat = false;
      await next.startImageStream((frame) {
        if (!describedFormat) {
          describedFormat = true;
          debugPrint(
            '[FFmpeg] Switched camera frame ${frame.width}x${frame.height} '
            '(${_cameraPixelFormat(frame)}); normalizing to '
            '${_frameWidth}x$_frameHeight ($_pixelFormat)',
          );
        }
        _writeVideoFrame(frame);
      });
    } catch (_) {
      _camera = previous;
      _activeCameraName = previousName;
      await previous.startImageStream(_writeVideoFrame);
      rethrow;
    }
    _addEvent(RecordingLifecycleStage.recording, cameraName);
  }

  @override
  Future<void> stop(StreamSession session) async {
    if (_stopping) return;
    final process = _process;
    if (process == null) {
      await _tearDownMedia(killProcess: false);
      return;
    }
    _stopping = true;
    _addEvent(RecordingLifecycleStage.stopping, session.shutdownText);
    try {
      final shutdownSlate = _shutdownSlate;
      if (shutdownSlate != null) {
        await _playSlate(shutdownSlate, const Duration(seconds: 5));
      }
      _addEvent(RecordingLifecycleStage.finalizing, 'FFmpeg outputs');
      // End both inputs normally. FFmpeg treats EOF as a graceful end-of-file
      // and flushes encoder buffers plus the FLV/MP4 trailers. Its interactive
      // `q` command instead interrupts active muxer writes on some builds.
      await _closeInputFeeds();
      int exitCode;
      try {
        exitCode = await process.exitCode.timeout(const Duration(seconds: 20));
      } on TimeoutException {
        process.kill();
        throw StateError('FFmpeg did not stop within 20 seconds.');
      }
      if (exitCode != 0) {
        throw StateError(_ffmpegFailure('FFmpeg exited with code $exitCode.'));
      }
      final outputPath = _outputPath;
      if (outputPath != null && await File(outputPath).exists()) {
        _recordedFiles.add(outputPath);
        _addEvent(RecordingLifecycleStage.recordingSaved, outputPath);
      }
      _addEvent(RecordingLifecycleStage.stopped, 'Stream finalized');
    } finally {
      await _tearDownMedia(killProcess: false);
      _stopping = false;
    }
  }

  @visibleForTesting
  static List<String> buildArguments({
    required int videoPort,
    required int audioPort,
    required int width,
    required int height,
    required String pixelFormat,
    required String videoEncoder,
    required String ingestionUrl,
    String? outputPath,
  }) => [
    '-hide_banner',
    '-loglevel',
    'warning',
    '-f',
    'rawvideo',
    '-pixel_format',
    pixelFormat,
    '-video_size',
    '${width}x$height',
    '-framerate',
    '30',
    '-i',
    'tcp://127.0.0.1:$videoPort',
    '-f',
    's16le',
    '-ar',
    '48000',
    '-ac',
    '1',
    '-i',
    'tcp://127.0.0.1:$audioPort',
    '-map',
    '0:v:0',
    '-map',
    '1:a:0',
    '-c:v',
    videoEncoder,
    if (videoEncoder == 'h264_videotoolbox') ...[
      '-realtime',
      '1',
      '-allow_sw',
      '1',
    ],
    '-b:v',
    '4500k',
    '-maxrate',
    '4500k',
    '-bufsize',
    '9000k',
    '-g',
    '60',
    '-keyint_min',
    '60',
    '-pix_fmt',
    'yuv420p',
    '-c:a',
    'aac',
    '-b:a',
    '128k',
    '-ar',
    '48000',
    '-ac',
    '2',
    '-f',
    'tee',
    '[f=flv:flvflags=no_duration_filesize:onfail=abort]$ingestionUrl'
        '${outputPath == null ? '' : '|[f=mp4:movflags=+faststart:onfail=ignore]$outputPath'}',
  ];

  void _writeVideoFrame(CameraImage frame) {
    final socket = _videoSocket;
    if (socket == null || frame.planes.isEmpty || _slateActive) return;
    final targetWidth = _frameWidth;
    final targetHeight = _frameHeight;
    final targetFormat = _pixelFormat;
    if (targetWidth == null || targetHeight == null || targetFormat == null) {
      return;
    }
    final plane = frame.planes.first;
    final cameraName = _activeCameraName;
    final videoDelay = Duration(
      milliseconds: cameraName == null ? 0 : cameraDelayForName(cameraName),
    );
    final rowBytes = frame.width * 4;
    try {
      final sourceFormat = _cameraPixelFormat(frame);
      if (frame.width == targetWidth &&
          frame.height == targetHeight &&
          sourceFormat == targetFormat &&
          plane.bytesPerRow == rowBytes) {
        _videoQueue.add(
          Uint8List.fromList(plane.bytes),
          videoDelay,
          socket,
          (error) => _recordTransportError('video', error),
        );
        return;
      }
      _videoQueue.add(
        _normalizeFrame(
          frame,
          sourceFormat: sourceFormat,
          targetWidth: targetWidth,
          targetHeight: targetHeight,
          targetFormat: targetFormat,
        ),
        videoDelay,
        socket,
        (error) => _recordTransportError('video', error),
      );
    } catch (error) {
      _recordTransportError('video', error);
    }
  }

  Uint8List _normalizeFrame(
    CameraImage frame, {
    required String sourceFormat,
    required int targetWidth,
    required int targetHeight,
    required String targetFormat,
  }) {
    final source = frame.planes.first;
    final output = Uint8List(targetWidth * targetHeight * 4);
    final scale = math.min(
      targetWidth / frame.width,
      targetHeight / frame.height,
    );
    final scaledWidth = (frame.width * scale).round();
    final scaledHeight = (frame.height * scale).round();
    final left = (targetWidth - scaledWidth) ~/ 2;
    final top = (targetHeight - scaledHeight) ~/ 2;
    final swapRedBlue = sourceFormat != targetFormat;

    for (var y = 0; y < scaledHeight; y++) {
      final sourceY = y * frame.height ~/ scaledHeight;
      final sourceRow = sourceY * source.bytesPerRow;
      final targetRow = (top + y) * targetWidth * 4;
      for (var x = 0; x < scaledWidth; x++) {
        final sourceX = x * frame.width ~/ scaledWidth;
        final sourceOffset = sourceRow + sourceX * 4;
        final targetOffset = targetRow + (left + x) * 4;
        if (swapRedBlue) {
          output[targetOffset] = source.bytes[sourceOffset + 2];
          output[targetOffset + 1] = source.bytes[sourceOffset + 1];
          output[targetOffset + 2] = source.bytes[sourceOffset];
        } else {
          output[targetOffset] = source.bytes[sourceOffset];
          output[targetOffset + 1] = source.bytes[sourceOffset + 1];
          output[targetOffset + 2] = source.bytes[sourceOffset + 2];
        }
        output[targetOffset + 3] = source.bytes[sourceOffset + 3];
      }
    }
    return output;
  }

  void _startAudioMixer() {
    for (final source in audioSources.sources) {
      final queue = _PcmQueue();
      _audioQueues[source] = queue;
      _audioSubscriptions.add(source.mixedAudio.stream.listen(queue.add));
    }
    // 20 ms of 48 kHz mono signed 16-bit PCM.
    const byteCount = 1920;
    _audioTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      final socket = _audioSocket;
      if (socket == null) return;
      final enabled = audioSources.sources
          .where((source) => source.enabled)
          .toList();
      if (enabled.isEmpty) {
        _writeAudio(socket, Uint8List(byteCount));
        return;
      }
      final chunks = [
        for (final source in enabled)
          _audioQueues[source]!.takeDelayed(
            byteCount,
            source.delayMs * 96, // 48 kHz, mono, 16-bit = 96 bytes/ms.
          ),
      ];
      final output = Uint8List(byteCount);
      final outputData = ByteData.sublistView(output);
      for (var offset = 0; offset < byteCount; offset += 2) {
        var mixed = 0;
        for (final chunk in chunks) {
          mixed += ByteData.sublistView(chunk).getInt16(offset, Endian.little);
        }
        outputData.setInt16(offset, mixed.clamp(-32768, 32767), Endian.little);
      }
      _writeAudio(socket, output);
    });
  }

  void _writeAudio(Socket socket, Uint8List bytes) {
    try {
      socket.add(bytes);
    } catch (error) {
      _recordTransportError('audio', error);
    }
  }

  Future<void> _playStartupSlate(Uint8List bytes) async {
    await _playSlateUntil(bytes, _startupSlateRelease!.future);
    await _playSlate(bytes, const Duration(seconds: 5));
  }

  @override
  Future<void> finishStartupSlate() async {
    final release = _startupSlateRelease;
    if (release == null) return;
    if (!release.isCompleted) release.complete();
    // Keep the splash visible for its full configured program duration after
    // YouTube has made the broadcast visible to viewers.
    await Future<void>.delayed(const Duration(seconds: 5));
    _startupSlateRelease = null;
  }

  Future<void> _playSlateUntil(Uint8List bytes, Future<void> until) async {
    final socket = _videoSocket;
    if (socket == null) return;
    _slateTimer?.cancel();
    _videoQueue.clear();
    _slateActive = true;

    void writeFrame() {
      try {
        socket.add(bytes);
      } catch (error) {
        _recordTransportError('video', error);
      }
    }

    writeFrame();
    _slateTimer = Timer.periodic(
      const Duration(milliseconds: 33),
      (_) => writeFrame(),
    );
    await until;
  }

  Future<void> _playSlate(Uint8List bytes, Duration duration) async {
    final socket = _videoSocket;
    if (socket == null) return;
    _slateTimer?.cancel();
    final generation = ++_slateGeneration;
    _videoQueue.clear();
    _slateActive = true;

    void writeFrame() {
      try {
        socket.add(bytes);
      } catch (error) {
        _recordTransportError('video', error);
      }
    }

    writeFrame();
    _slateTimer = Timer.periodic(
      const Duration(milliseconds: 33),
      (_) => writeFrame(),
    );
    await Future<void>.delayed(duration);
    if (generation != _slateGeneration) return;
    _slateTimer?.cancel();
    _slateTimer = null;
    _slateActive = false;
  }

  Future<Uint8List> _renderSlate({
    String? title,
    required String additionalText,
  }) async {
    final width = _frameWidth!;
    final height = _frameHeight!;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..color = const ui.Color(0xff050f13),
    );

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

  void _consumeSocketErrors(Socket socket, String channel) {
    socket.listen(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        _recordTransportError(channel, error);
      },
    );
    unawaited(
      socket.done.catchError((Object error, StackTrace stackTrace) {
        _recordTransportError(channel, error);
      }),
    );
  }

  void _recordTransportError(String channel, Object error) {
    if (_stopping) return;
    _transportError ??= error;
    final message = _sanitizeDiagnostic('$channel transport: $error');
    _transportDiagnostics.add(message);
    debugPrint('[FFmpeg transport] $message');
    if (_transportDiagnostics.length > 10) {
      _transportDiagnostics.removeAt(0);
    }
  }

  Future<void> _tearDownMedia({required bool killProcess}) async {
    if (killProcess) _process?.kill();
    await _closeInputFeeds();
    await _ignoreCleanup(_stderrSubscription?.cancel(), 'FFmpeg diagnostics');
    _stderrSubscription = null;
    _process = null;
    _frameWidth = null;
    _frameHeight = null;
    _pixelFormat = null;
    _outputPath = null;
    _sensitiveIngestionUrl = null;
    _transportError = null;
  }

  Future<void> _closeInputFeeds() async {
    _slateGeneration++;
    _slateTimer?.cancel();
    _slateTimer = null;
    _slateActive = false;
    _audioTimer?.cancel();
    _audioTimer = null;
    for (final subscription in _audioSubscriptions) {
      await _ignoreCleanup(subscription.cancel(), 'audio subscription');
    }
    _audioSubscriptions.clear();
    _audioQueues.clear();
    _videoQueue.clear();
    _startupSlate = null;
    _shutdownSlate = null;
    final startupRelease = _startupSlateRelease;
    if (startupRelease != null && !startupRelease.isCompleted) {
      startupRelease.complete();
    }
    _startupSlateRelease = null;
    final camera = _camera;
    _camera = null;
    _activeCameraName = null;
    if (camera?.value.isStreamingImages ?? false) {
      await _ignoreCleanup(camera!.stopImageStream(), 'camera image stream');
    }
    await _ignoreCleanup(_videoSocket?.close(), 'video socket');
    await _ignoreCleanup(_audioSocket?.close(), 'audio socket');
    await _ignoreCleanup(_videoServer?.close(), 'video server');
    await _ignoreCleanup(_audioServer?.close(), 'audio server');
    _videoSocket = null;
    _audioSocket = null;
    _videoServer = null;
    _audioServer = null;
  }

  Future<void> _ignoreCleanup(Future<void>? operation, String resource) async {
    if (operation == null) return;
    try {
      await operation;
    } catch (error) {
      _recordTransportError(resource, error);
    }
  }

  Future<String> _createOutputPath(StreamSession session) async {
    final directory = session.recordingDirectory.isEmpty
        ? await _defaultDirectory()
        : Directory(session.recordingDirectory);
    await directory.create(recursive: true);
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final title = session.title
        .trim()
        .replaceAll(RegExp(r'[\/:*?"<>|]'), '-')
        .replaceAll(RegExp(r'\s+'), ' ');
    final baseName = '${title.isEmpty ? 'Church Stream' : title}-$timestamp';
    var output = File(
      '${directory.path}${Platform.pathSeparator}$baseName.mp4',
    );
    var duplicate = 2;
    while (await output.exists()) {
      output = File(
        '${directory.path}${Platform.pathSeparator}$baseName-$duplicate.mp4',
      );
      duplicate++;
    }
    return output.path;
  }

  String _ffmpegFailure(String fallback) {
    final ffmpegLines = _stderr
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (ffmpegLines.isNotEmpty) {
      final first = (ffmpegLines.length - 6).clamp(0, ffmpegLines.length);
      return ffmpegLines.sublist(first).join(' | ');
    }
    if (_transportDiagnostics.isNotEmpty) {
      return '$fallback ${_transportDiagnostics.last}';
    }
    return fallback;
  }

  String _sanitizeDiagnostic(String line) {
    final target = _sensitiveIngestionUrl;
    return target == null ? line : line.replaceAll(target, '[YouTube ingest]');
  }

  String _ffmpegPixelFormat(CameraImage frame) {
    return _cameraPixelFormat(frame);
  }

  String _cameraPixelFormat(CameraImage frame) {
    final raw = frame.format.raw.toString().toLowerCase();
    if (raw.contains('rgba')) return 'rgba';
    if (raw.contains('bgra')) return 'bgra';
    throw StateError('Unsupported camera pixel format: ${frame.format.raw}');
  }

  void _addEvent(RecordingLifecycleStage stage, String detail) {
    _trace.add(RecordingLifecycleEvent(stage, detail, DateTime.now()));
    notifyListeners();
  }

  @override
  void dispose() {
    // The normal Quit path awaits stop(); this is a final safety net for an
    // operating-system window close or an unexpected widget teardown.
    unawaited(
      _tearDownMedia(killProcess: true).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        debugPrint('FFmpeg teardown failed: $error');
      }),
    );
    super.dispose();
  }

  static Future<Process> _startFfmpeg(List<String> arguments) async {
    for (final executable in _ffmpegCandidates) {
      try {
        return await Process.start(executable, arguments);
      } on ProcessException {
        // Try the next common installation location.
      }
    }
    throw StateError('FFmpeg is not installed.');
  }

  static Future<bool> _isFfmpegInstalled() async {
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

  static List<String> get _ffmpegCandidates => [
    'ffmpeg',
    if (Platform.isMacOS) ...[
      '/usr/local/bin/ffmpeg',
      '/opt/homebrew/bin/ffmpeg',
      '/opt/local/bin/ffmpeg',
    ],
  ];

  static String get _defaultVideoEncoder {
    if (Platform.isMacOS) return 'h264_videotoolbox';
    if (Platform.isWindows) return 'h264_mf';
    return 'libx264';
  }
}

class _PcmQueue {
  final Queue<int> _bytes = Queue<int>();
  int _bufferedDelayBytes = 0;

  void add(Uint8List bytes) => _bytes.addAll(bytes);

  Uint8List take(int count) {
    final output = Uint8List(count);
    for (var index = 0; index < count && _bytes.isNotEmpty; index++) {
      output[index] = _bytes.removeFirst();
    }
    return output;
  }

  Uint8List takeDelayed(int count, int delayBytes) {
    if (delayBytes < _bufferedDelayBytes) {
      var discard = math.min(_bufferedDelayBytes - delayBytes, _bytes.length);
      while (discard-- > 0) {
        _bytes.removeFirst();
      }
      _bufferedDelayBytes = delayBytes;
    } else if (delayBytes > _bufferedDelayBytes) {
      // Emit silence only while intentionally growing the delay buffer. Once
      // primed, consume whatever capture supplied this tick, just as the
      // original non-delayed mixer did, instead of converting input jitter to
      // repeated 20 ms gaps.
      if (_bytes.length < delayBytes + count) return Uint8List(count);
      _bufferedDelayBytes = delayBytes;
    }
    return take(count);
  }
}

class _DelayedVideoQueue {
  final Queue<_DelayedVideoFrame> _frames = Queue<_DelayedVideoFrame>();
  Timer? _timer;

  void add(
    Uint8List bytes,
    Duration delay,
    Socket socket,
    void Function(Object error) onError,
  ) {
    if (delay == Duration.zero && _frames.isEmpty) {
      try {
        socket.add(bytes);
      } catch (error) {
        onError(error);
      }
      return;
    }
    _frames.add(_DelayedVideoFrame(bytes, DateTime.now().add(delay)));
    _schedule(socket, onError);
  }

  void _schedule(Socket socket, void Function(Object error) onError) {
    _timer?.cancel();
    if (_frames.isEmpty) return;
    final wait = _frames.first.sendAt.difference(DateTime.now());
    _timer = Timer(wait.isNegative ? Duration.zero : wait, () {
      final now = DateTime.now();
      try {
        while (_frames.isNotEmpty && !_frames.first.sendAt.isAfter(now)) {
          socket.add(_frames.removeFirst().bytes);
        }
      } catch (error) {
        onError(error);
      }
      _schedule(socket, onError);
    });
  }

  void clear() {
    _timer?.cancel();
    _timer = null;
    _frames.clear();
  }
}

class _DelayedVideoFrame {
  const _DelayedVideoFrame(this.bytes, this.sendAt);
  final Uint8List bytes;
  final DateTime sendAt;
}
