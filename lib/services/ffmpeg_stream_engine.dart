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
import 'app_log.dart';
import 'stream_engine.dart';

part 'ffmpeg_media_queues.dart';
part 'ffmpeg_arguments.dart';
part 'ffmpeg_audio_mixer.dart';
part 'ffmpeg_diagnostics.dart';
part 'ffmpeg_platform.dart';
part 'ffmpeg_slate_pipeline.dart';
part 'ffmpeg_transport.dart';
part 'ffmpeg_video_pipeline.dart';

typedef CameraControllerResolver = CameraController? Function(String name);
typedef CameraDelayResolver = int Function(String name);
typedef IngestionUrlResolver = String? Function();
typedef FfmpegProcessStarter = Future<Process> Function(List<String> arguments);

/// Publishes camera and microphone data to YouTube while writing the same
/// encoded program to a local MP4 archive.
class FfmpegStreamEngine extends ChangeNotifier
    implements StreamEngine, StreamProcessMonitor, StartupSlateController {
  static const _cleanupTimeout = Duration(seconds: 3);

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
  final Map<AudioSource, PcmQueue> _audioQueues = {};

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
  Uint8List? _fadeSlate;
  DateTime? _fadeStartedAt;
  bool _fadingToSlate = false;
  Completer<void>? _startupSlateRelease;
  Duration _startupSlateDuration = const Duration(seconds: 5);
  StreamSubscription<String>? _stderrSubscription;
  int? _frameWidth;
  int? _frameHeight;
  int _frameRate = 30;
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
      _frameRate = session.frameRate.value;
      _pixelFormat = _ffmpegPixelFormat(frame);
      if (session.startupSplashEnabled) {
        _startupSlate = await _renderSlate(
          title: session.startupSplashShowTitle ? session.title : null,
          additionalText: session.startupText,
          backgroundPath: session.startupSplashBackgroundPath,
        );
      }
      if (session.shutdownSplashEnabled) {
        _shutdownSlate = await _renderSlate(
          title: session.shutdownSplashShowTitle ? session.title : null,
          additionalText: session.shutdownText,
          backgroundPath: session.shutdownSplashBackgroundPath,
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
      final videoEncoder = await _videoEncoder(
        session.encoderPreference,
        width: session.outputResolution.width ?? frame.width,
        height: session.outputResolution.height ?? frame.height,
      );
      logMessage('[FFmpeg] Selected video encoder: $videoEncoder');
      final arguments = buildArguments(
        videoPort: _videoServer!.port,
        audioPort: _audioServer!.port,
        width: frame.width,
        height: frame.height,
        pixelFormat: _pixelFormat!,
        videoEncoder: videoEncoder,
        forceHardwareEncoding: videoEncoder == 'h264_mf',
        ingestionUrl: target,
        outputPath: _outputPath,
        outputResolution: session.outputResolution,
        videoBitrate: session.videoBitrate.kbps,
        frameRate: session.frameRate.value,
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
            logMessage('[FFmpeg] $diagnostic');
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
        _startupSlateDuration = Duration(
          seconds: session.startupSplashDurationSeconds,
        );
        unawaited(_playStartupSlate(startupSlate, _startupSlateDuration));
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
          logMessage(
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
        logMessage(
          '[Splash] Starting ${session.shutdownSplashDurationSeconds}s '
          'shutdown splash.',
        );
        await _crossfade(shutdownSlate, toSlate: true);
        await _playSlate(
          shutdownSlate,
          Duration(seconds: session.shutdownSplashDurationSeconds),
        );
        await _flushVideoFeed();
        logMessage('[Splash] Shutdown splash delivered to FFmpeg.');
      } else {
        logMessage('[Splash] Shutdown splash is disabled.');
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
    bool forceHardwareEncoding = false,
    String? outputPath,
    StreamOutputResolution outputResolution = StreamOutputResolution.original,
    int videoBitrate = 4500,
    int frameRate = 30,
  }) => _buildFfmpegArguments(
    videoPort: videoPort,
    audioPort: audioPort,
    width: width,
    height: height,
    pixelFormat: pixelFormat,
    videoEncoder: videoEncoder,
    ingestionUrl: ingestionUrl,
    forceHardwareEncoding: forceHardwareEncoding,
    outputPath: outputPath,
    outputResolution: outputResolution,
    videoBitrate: videoBitrate,
    frameRate: frameRate,
  );

  @override
  Future<void> finishStartupSlate() => _finishStartupSlate();

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
        logMessage('FFmpeg teardown failed: $error');
      }),
    );
    super.dispose();
  }
}
