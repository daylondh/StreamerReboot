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
  segmentSaved,
  stopping,
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

/// Records locally. Camera changes finish the current file and begin a
/// numbered segment from the newly selected camera.
class LocalRecordingStreamEngine extends ChangeNotifier
    implements StreamEngine {
  LocalRecordingStreamEngine({
    required this.recorderForCamera,
    DefaultRecordingDirectory? defaultDirectory,
  }) : _defaultDirectory = defaultDirectory ?? getApplicationDocumentsDirectory;

  final VideoRecorderResolver recorderForCamera;
  final DefaultRecordingDirectory _defaultDirectory;
  final List<RecordingLifecycleEvent> _trace = [];
  final List<String> _recordedFiles = [];
  VideoRecorder? _activeRecorder;
  String? _activeCameraName;
  StreamSession? _activeSession;
  int _segment = 0;

  List<RecordingLifecycleEvent> get trace => List.unmodifiable(_trace);
  List<String> get recordedFiles => List.unmodifiable(_recordedFiles);
  bool get isRecording => _activeRecorder != null;

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
    _segment = 1;
    _trace.clear();
    _recordedFiles.clear();
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
    await _finishSegment();
    _segment++;
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
    await _finishSegment();
    _activeSession = null;
    _activeCameraName = null;
    _addEvent(
      RecordingLifecycleStage.stopped,
      '${_recordedFiles.length} file(s) saved',
    );
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

  Future<void> _finishSegment() async {
    final recorder = _activeRecorder;
    final session = _activeSession;
    if (recorder == null || session == null) return;
    final temporaryPath = await recorder.stop();
    _activeRecorder = null;
    _activeCameraName = null;
    final savedPath = await _saveSegment(temporaryPath, session);
    _recordedFiles.add(savedPath);
    _addEvent(RecordingLifecycleStage.segmentSaved, savedPath);
  }

  Future<String> _saveSegment(
    String temporaryPath,
    StreamSession session,
  ) async {
    final source = File(temporaryPath);
    if (!await source.exists()) {
      throw StateError('The camera did not produce a recording file.');
    }
    final directory = session.recordingDirectory.isEmpty
        ? await _defaultDirectory()
        : Directory(session.recordingDirectory);
    await directory.create(recursive: true);
    final extension = _extensionOf(temporaryPath);
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final title = _safeFileName(session.title);
    final segmentSuffix = _segment == 1 ? '' : '-part-$_segment';
    var destination = File(
      '${directory.path}${Platform.pathSeparator}$title-$timestamp$segmentSuffix$extension',
    );
    var duplicate = 2;
    while (await destination.exists()) {
      destination = File(
        '${directory.path}${Platform.pathSeparator}$title-$timestamp$segmentSuffix-$duplicate$extension',
      );
      duplicate++;
    }
    await source.copy(destination.path);
    await source.delete();
    return destination.path;
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
