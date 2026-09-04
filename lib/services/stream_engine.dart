import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/stream_session.dart';

abstract interface class StreamEngine {
  Future<void> start(StreamSession session);
  Future<void> switchCamera(String cameraName);
  Future<void> stop(StreamSession session);
}

/// Optional process health exposed by stream engines backed by an external
/// publisher such as FFmpeg.
abstract interface class StreamProcessMonitor {
  Future<int> get processExitCode;
  String get diagnosticSummary;
}

abstract interface class VideoRecorder {
  Future<void> start();
  Future<String> stop();
}

class CameraVideoRecorder implements VideoRecorder {
  CameraVideoRecorder(this.controller);
  final CameraController controller;

  @override
  Future<void> start() => controller.startVideoRecording();

  @override
  Future<String> stop() async => (await controller.stopVideoRecording()).path;
}

enum RecordingLifecycleStage {
  starting,
  recording,
  switchingCamera,
  stopping,
  finalizing,
  recordingSaved,
  stopped,
}

class RecordingLifecycleEvent {
  const RecordingLifecycleEvent(this.stage, this.detail, this.timestamp);
  final RecordingLifecycleStage stage;
  final String detail;
  final DateTime timestamp;
}

typedef VideoRecorderResolver = VideoRecorder? Function(String cameraName);
typedef DefaultRecordingDirectory = Future<Directory> Function();
typedef VideoSegmentMerger =
    Future<void> Function(List<String> inputPaths, String outputPath);
typedef FfmpegChecker = Future<bool> Function();

enum FfmpegAvailability { checking, available, unavailable }

/// Records locally, joining the native clips created by camera changes into a
/// single file when the session ends.
class LocalRecordingStreamEngine extends ChangeNotifier
    implements StreamEngine {
  LocalRecordingStreamEngine({
    required this.recorderForCamera,
    DefaultRecordingDirectory? defaultDirectory,
    VideoSegmentMerger? segmentMerger,
    FfmpegChecker? ffmpegChecker,
  }) : _defaultDirectory = defaultDirectory ?? getApplicationDocumentsDirectory,
       _segmentMerger = segmentMerger ?? _mergeSegmentsWithFfmpeg,
       _ffmpegChecker = ffmpegChecker ?? _isFfmpegInstalled;

  final VideoRecorderResolver recorderForCamera;
  final DefaultRecordingDirectory _defaultDirectory;
  final VideoSegmentMerger _segmentMerger;
  final FfmpegChecker _ffmpegChecker;
  final List<RecordingLifecycleEvent> _trace = [];
  final List<String> _recordedFiles = [];
  final List<String> _temporarySegments = [];
  VideoRecorder? _activeRecorder;
  String? _activeCameraName;
  StreamSession? _activeSession;
  FfmpegAvailability _ffmpegAvailability = FfmpegAvailability.checking;

  List<RecordingLifecycleEvent> get trace => List.unmodifiable(_trace);
  List<String> get recordedFiles => List.unmodifiable(_recordedFiles);
  bool get isRecording => _activeRecorder != null;
  FfmpegAvailability get ffmpegAvailability => _ffmpegAvailability;

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
    if (_activeRecorder != null) {
      throw StateError('A local recording is already active.');
    }
    if (!session.recordLocally) {
      throw StateError('Enable local recording before going live.');
    }
    final cameraName = session.cameraName;
    if (cameraName == null) {
      throw StateError('Select a ready camera before going live.');
    }
    _activeSession = session;
    _trace.clear();
    _recordedFiles.clear();
    _temporarySegments.clear();
    _addEvent(RecordingLifecycleStage.starting, cameraName);
    try {
      await _startCamera(cameraName);
    } catch (_) {
      _activeSession = null;
      rethrow;
    }
  }

  @override
  Future<void> switchCamera(String cameraName) async {
    if (_activeRecorder == null || _activeSession == null) {
      throw StateError('No local recording is active.');
    }
    _addEvent(RecordingLifecycleStage.switchingCamera, cameraName);
    final previousCamera = _activeCameraName!;
    await _finishCameraClip();
    try {
      await _startCamera(cameraName);
    } catch (_) {
      await _startCamera(previousCamera);
      rethrow;
    }
  }

  @override
  Future<void> stop(StreamSession session) async {
    if (_activeRecorder == null) {
      _activeSession = null;
      _activeCameraName = null;
      return;
    }
    _addEvent(RecordingLifecycleStage.stopping, session.shutdownText);
    await _finishCameraClip();
    _addEvent(
      RecordingLifecycleStage.finalizing,
      '${_temporarySegments.length} clip(s)',
    );
    final savedPath = await _saveRecording(session);
    _recordedFiles.add(savedPath);
    _addEvent(RecordingLifecycleStage.recordingSaved, savedPath);
    _clearActiveSession();
    _addEvent(RecordingLifecycleStage.stopped, '1 file saved');
  }

  Future<void> _startCamera(String cameraName) async {
    final recorder = recorderForCamera(cameraName);
    if (recorder == null) {
      throw StateError('Camera "$cameraName" is not ready.');
    }
    _activeRecorder = recorder;
    try {
      await recorder.start();
    } catch (_) {
      _activeRecorder = null;
      rethrow;
    }
    _activeCameraName = cameraName;
    _addEvent(RecordingLifecycleStage.recording, cameraName);
  }

  Future<void> _finishCameraClip() async {
    final recorder = _activeRecorder;
    if (recorder == null) return;
    final temporaryPath = await recorder.stop();
    _activeRecorder = null;
    _activeCameraName = null;
    if (!await File(temporaryPath).exists()) {
      throw StateError('The camera did not produce a recording file.');
    }
    _temporarySegments.add(temporaryPath);
  }

  Future<String> _saveRecording(StreamSession session) async {
    if (_temporarySegments.isEmpty) {
      throw StateError('The camera did not produce any recording clips.');
    }
    final directory = session.recordingDirectory.isEmpty
        ? await _defaultDirectory()
        : Directory(session.recordingDirectory);
    await directory.create(recursive: true);
    final extension = _extensionOf(_temporarySegments.first);
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final title = _safeFileName(session.title);
    var destination = File(
      '${directory.path}${Platform.pathSeparator}$title-$timestamp$extension',
    );
    var duplicate = 2;
    while (await destination.exists()) {
      destination = File(
        '${directory.path}${Platform.pathSeparator}$title-$timestamp-$duplicate$extension',
      );
      duplicate++;
    }
    if (_temporarySegments.length == 1) {
      await File(_temporarySegments.single).copy(destination.path);
    } else {
      await _segmentMerger(
        List.unmodifiable(_temporarySegments),
        destination.path,
      );
    }
    for (final path in _temporarySegments) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    _temporarySegments.clear();
    return destination.path;
  }

  void _clearActiveSession() {
    _activeSession = null;
    _activeCameraName = null;
  }

  static Future<void> _mergeSegmentsWithFfmpeg(
    List<String> inputPaths,
    String outputPath,
  ) async {
    try {
      final inputs = <String>[
        for (final path in inputPaths) ...['-i', path],
      ];
      final filters = <String>[
        for (var index = 0; index < inputPaths.length; index++) ...[
          '[$index:v:0]setpts=PTS-STARTPTS,fps=30,'
              'scale=1280:720:force_original_aspect_ratio=decrease,'
              'pad=1280:720:(ow-iw)/2:(oh-ih)/2,'
              'setsar=1,format=yuv420p[v$index]',
          '[$index:a:0]asetpts=PTS-STARTPTS,'
              'aresample=async=1:first_pts=0[a$index]',
        ],
        '${List.generate(inputPaths.length, (index) => '[v$index][a$index]').join()}'
            'concat=n=${inputPaths.length}:v=1:a=1[outv][outa]',
      ];
      final result = await _runFfmpeg([
        '-hide_banner',
        '-loglevel',
        'error',
        ...inputs,
        '-filter_complex',
        filters.join(';'),
        '-map',
        '[outv]',
        '-map',
        '[outa]',
        '-c:v',
        'mpeg4',
        '-q:v',
        '3',
        '-c:a',
        'aac',
        '-b:a',
        '192k',
        '-movflags',
        '+faststart',
        '-y',
        outputPath,
      ]);
      if (result == null) {
        throw ProcessException('ffmpeg', []);
      }
      if (result.exitCode != 0) {
        await _deleteIfPresent(File(outputPath));
        throw StateError('Could not finalize recording: ${result.stderr}');
      }
    } on ProcessException catch (error) {
      throw StateError(
        'Could not finalize recording because FFmpeg is unavailable: $error',
      );
    }
  }

  static Future<bool> _isFfmpegInstalled() async {
    final result = await _runFfmpeg(['-version']);
    return result?.exitCode == 0;
  }

  static Future<ProcessResult?> _runFfmpeg(List<String> arguments) async {
    for (final executable in _ffmpegCandidates) {
      try {
        return await Process.run(executable, arguments);
      } on ProcessException {
        // GUI apps often lack the shell PATH, so try known install locations.
      }
    }
    return null;
  }

  static List<String> get _ffmpegCandidates => [
    'ffmpeg',
    if (Platform.isMacOS) ...[
      '/usr/local/bin/ffmpeg',
      '/opt/homebrew/bin/ffmpeg',
      '/opt/local/bin/ffmpeg',
    ],
  ];

  static Future<void> _deleteIfPresent(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Cleanup must not hide the original recording/finalization result.
    }
  }

  String _safeFileName(String value) {
    final safe = value
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '-')
        .replaceAll(RegExp(r'\s+'), ' ');
    return safe.isEmpty ? 'Church Stream' : safe;
  }

  String _extensionOf(String path) {
    final fileName = path.split(RegExp(r'[/\\]')).last;
    final dot = fileName.lastIndexOf('.');
    return dot < 0 ? '.mp4' : fileName.substring(dot);
  }

  void _addEvent(RecordingLifecycleStage stage, String detail) {
    _trace.add(RecordingLifecycleEvent(stage, detail, DateTime.now()));
    notifyListeners();
  }
}
