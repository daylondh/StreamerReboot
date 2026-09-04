import 'package:shared_preferences/shared_preferences.dart';

class StreamTextSettings {
  const StreamTextSettings({
    this.startupSplashEnabled = true,
    this.shutdownSplashEnabled = true,
    this.recordingDirectory = '',
    this.startupText = '',
    this.shutdownText = '',
  });

  final bool startupSplashEnabled;
  final bool shutdownSplashEnabled;
  final String recordingDirectory;
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

  @override
  Future<StreamTextSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    return StreamTextSettings(
      startupSplashEnabled: preferences.getBool(_startupEnabledKey) ?? true,
      shutdownSplashEnabled: preferences.getBool(_shutdownEnabledKey) ?? true,
      recordingDirectory: preferences.getString(_recordingDirectoryKey) ?? '',
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
      preferences.setString(
        _recordingDirectoryKey,
        settings.recordingDirectory,
      ),
      preferences.setString(_startupKey, settings.startupText),
      preferences.setString(_shutdownKey, settings.shutdownText),
    ]);
  }
}
