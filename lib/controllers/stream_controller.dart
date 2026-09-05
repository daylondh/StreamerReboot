import 'package:flutter/foundation.dart';
import '../domain/liturgical_calendar.dart';
import '../domain/stream_session.dart';
import '../services/stream_engine.dart';
import '../services/stream_settings_store.dart';

class StreamController extends ChangeNotifier {
  StreamController(this._engine, {this.settingsStore, DateTime? now})
    : _session = StreamSession(
        title: suggestedServiceTitle(now ?? DateTime.now()),
      );
  final StreamEngine _engine;
  final StreamSettingsStore? settingsStore;
  StreamSession _session;
  bool _isSwitchingCamera = false;
  Future<void>? _activeOperation;
  StreamSession get session => _session;
  bool get isSwitchingCamera => _isSwitchingCamera;

  Future<void> initialize() async {
    final settings = await settingsStore?.load();
    if (settings == null) return;
    _session = _session.copyWith(
      startupSplashEnabled: settings.startupSplashEnabled,
      shutdownSplashEnabled: settings.shutdownSplashEnabled,
      recordingDirectory: settings.recordingDirectory,
      startupText: settings.startupText,
      shutdownText: settings.shutdownText,
    );
    notifyListeners();
  }

  static String suggestedServiceTitle(DateTime now) {
    return StreamTitleSuggester.suggest(now);
  }

  void refreshSuggestedTitle([DateTime? now]) {
    _session = _session.copyWith(
      title: suggestedServiceTitle(now ?? DateTime.now()),
      clearError: true,
    );
    notifyListeners();
  }

  void updateTitle(String value) {
    _session = _session.copyWith(title: value, clearError: true);
    notifyListeners();
  }

  void updatePrivacy(ServicePrivacy value) {
    _session = _session.copyWith(privacy: value);
    notifyListeners();
  }

  void updateRecording(bool value) {
    _session = _session.copyWith(recordLocally: value);
    notifyListeners();
  }

  void updateRecordingDirectory(String value) {
    _session = _session.copyWith(recordingDirectory: value, clearError: true);
    notifyListeners();
    _saveTextSettings();
  }

  void updateStartupText(String value) {
    _session = _session.copyWith(startupText: value, clearError: true);
    notifyListeners();
    _saveTextSettings();
  }

  void updateStartupSplashEnabled(bool value) {
    _session = _session.copyWith(startupSplashEnabled: value, clearError: true);
    notifyListeners();
    _saveTextSettings();
  }

  void updateShutdownSplashEnabled(bool value) {
    _session = _session.copyWith(
      shutdownSplashEnabled: value,
      clearError: true,
    );
    notifyListeners();
    _saveTextSettings();
  }

  void updateShutdownText(String value) {
    _session = _session.copyWith(shutdownText: value, clearError: true);
    notifyListeners();
    _saveTextSettings();
  }

  Future<void> _saveTextSettings() async {
    await settingsStore?.save(
      StreamTextSettings(
        startupSplashEnabled: _session.startupSplashEnabled,
        shutdownSplashEnabled: _session.shutdownSplashEnabled,
        recordingDirectory: _session.recordingDirectory,
        startupText: _session.startupText,
        shutdownText: _session.shutdownText,
      ),
    );
  }

  Future<void> selectCamera(String cameraName) async {
    if (_isSwitchingCamera || cameraName == _session.cameraName) return;

    if (!_session.isLive) {
      _session = _session.copyWith(cameraName: cameraName, clearError: true);
      notifyListeners();
      return;
    }

    _isSwitchingCamera = true;
    _session = _session.copyWith(clearError: true);
    notifyListeners();
    try {
      await _engine.switchCamera(cameraName);
      _session = _session.copyWith(cameraName: cameraName, clearError: true);
    } catch (error) {
      _session = _session.copyWith(error: 'Could not switch cameras: $error');
    } finally {
      _isSwitchingCamera = false;
      notifyListeners();
    }
  }

  Future<void> toggleLive() async {
    if (_session.isBusy) return;
    final operation = _session.isLive ? _stop() : _start();
    _activeOperation = operation;
    try {
      await operation;
    } finally {
      if (identical(_activeOperation, operation)) _activeOperation = null;
    }
  }

  /// Waits for any in-flight setup, then tears down local and remote stream
  /// resources. Calling this when idle is safe.
  Future<void> shutdown() async {
    final operation = _activeOperation;
    if (operation != null) await operation;
    if (_session.status == StreamStatus.idle) {
      // The engine may still own a partially-created remote resource after a
      // failed setup, so it must receive a stop even when the session is idle.
      await _engine.stop(_session);
      return;
    }
    await _stop();
  }

  Future<void> _start() async {
    if (_session.title.trim().isEmpty) {
      _session = _session.copyWith(
        status: StreamStatus.failed,
        error: 'Enter a service title before going live.',
      );
      notifyListeners();
      return;
    }
    _session = _session.copyWith(
      status: StreamStatus.preparing,
      clearError: true,
    );
    notifyListeners();
    try {
      await _engine.start(_session);
      _session = _session.copyWith(
        status: StreamStatus.live,
        startedAt: DateTime.now(),
      );
    } catch (error) {
      _session = _session.copyWith(
        status: StreamStatus.failed,
        error: 'Could not start the stream: $error',
      );
    }
    notifyListeners();
  }

  Future<void> _stop() async {
    _session = _session.copyWith(status: StreamStatus.stopping);
    notifyListeners();
    try {
      await _engine.stop(_session);
      _session = StreamSession(
        title: _session.title,
        privacy: _session.privacy,
        recordLocally: _session.recordLocally,
        recordingDirectory: _session.recordingDirectory,
        cameraName: _session.cameraName,
        startupSplashEnabled: _session.startupSplashEnabled,
        shutdownSplashEnabled: _session.shutdownSplashEnabled,
        startupText: _session.startupText,
        shutdownText: _session.shutdownText,
      );
    } catch (error) {
      _session = _session.copyWith(
        status: StreamStatus.failed,
        error: 'Could not stop the stream: $error',
      );
    }
    notifyListeners();
  }
}
