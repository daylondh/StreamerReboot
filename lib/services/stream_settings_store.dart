import 'package:shared_preferences/shared_preferences.dart';

import '../domain/stream_session.dart';

class StreamTextSettings {
  const StreamTextSettings({
    this.startupSplashEnabled = true,
    this.shutdownSplashEnabled = true,
    this.privacy = ServicePrivacy.unlisted,
    this.recordLocally = true,
    this.recordingDirectory = '',
    this.cameraName,
    this.startupText = '',
    this.shutdownText = '',
  });

  final bool startupSplashEnabled;
  final bool shutdownSplashEnabled;
  final ServicePrivacy privacy;
  final bool recordLocally;
  final String recordingDirectory;
  final String? cameraName;
  final String startupText;
  final String shutdownText;
}

abstract interface class StreamSettingsStore {
  Future<StreamTextSettings> load();
  Future<void> save(StreamTextSettings settings);
}

class SharedPreferencesStreamSettingsStore implements StreamSettingsStore {
  static const _startupKey = 'stream.startupText';
  static const _shutdownKey = 'stream.shutdownText';
  static const _startupEnabledKey = 'stream.startupSplashEnabled';
  static const _shutdownEnabledKey = 'stream.shutdownSplashEnabled';
  static const _recordingDirectoryKey = 'stream.recordingDirectory';
  static const _recordLocallyKey = 'stream.recordLocally';
  static const _privacyKey = 'stream.privacy';
  static const _cameraNameKey = 'stream.cameraName';

  @override
  Future<StreamTextSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    final privacyName = preferences.getString(_privacyKey);
    return StreamTextSettings(
      startupSplashEnabled: preferences.getBool(_startupEnabledKey) ?? true,
      shutdownSplashEnabled: preferences.getBool(_shutdownEnabledKey) ?? true,
      privacy: ServicePrivacy.values.firstWhere(
        (value) => value.name == privacyName,
        orElse: () => ServicePrivacy.unlisted,
      ),
      recordLocally: preferences.getBool(_recordLocallyKey) ?? true,
      recordingDirectory: preferences.getString(_recordingDirectoryKey) ?? '',
      cameraName: preferences.getString(_cameraNameKey),
      startupText: preferences.getString(_startupKey) ?? '',
      shutdownText: preferences.getString(_shutdownKey) ?? '',
    );
  }

  @override
  Future<void> save(StreamTextSettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.setBool(_startupEnabledKey, settings.startupSplashEnabled),
      preferences.setBool(_shutdownEnabledKey, settings.shutdownSplashEnabled),
      preferences.setString(_privacyKey, settings.privacy.name),
      preferences.setBool(_recordLocallyKey, settings.recordLocally),
      preferences.setString(
        _recordingDirectoryKey,
        settings.recordingDirectory,
      ),
      preferences.setString(_startupKey, settings.startupText),
      preferences.setString(_shutdownKey, settings.shutdownText),
      if (settings.cameraName == null)
        preferences.remove(_cameraNameKey)
      else
        preferences.setString(_cameraNameKey, settings.cameraName!),
    ]);
  }
}
