import 'package:shared_preferences/shared_preferences.dart';

import '../domain/stream_session.dart';

class StreamTextSettings {
  const StreamTextSettings({
    this.startupSplashEnabled = true,
    this.shutdownSplashEnabled = true,
    this.startupSplashShowTitle = true,
    this.shutdownSplashShowTitle = false,
    this.startupSplashDurationSeconds = 5,
    this.shutdownSplashDurationSeconds = 5,
    this.startupSplashBackgroundPath = '',
    this.shutdownSplashBackgroundPath = '',
    this.youtubeDescription = StreamSession.defaultYouTubeDescription,
    this.supportContactName = '',
    this.supportContactPhone = '',
    this.privacy = ServicePrivacy.unlisted,
    this.recordLocally = true,
    this.recordingDirectory = '',
    this.cameraName,
    this.outputResolution = StreamOutputResolution.original,
    this.videoBitrate = StreamVideoBitrate.standard,
    this.frameRate = StreamFrameRate.fps30,
    this.captureResolution = CameraCaptureResolution.automatic,
    this.encoderPreference = VideoEncoderPreference.automatic,
    this.startupText = '',
    this.shutdownText = '',
  });

  final bool startupSplashEnabled;
  final bool shutdownSplashEnabled;
  final bool startupSplashShowTitle;
  final bool shutdownSplashShowTitle;
  final int startupSplashDurationSeconds;
  final int shutdownSplashDurationSeconds;
  final String startupSplashBackgroundPath;
  final String shutdownSplashBackgroundPath;
  final String youtubeDescription;
  final String supportContactName;
  final String supportContactPhone;
  final ServicePrivacy privacy;
  final bool recordLocally;
  final String recordingDirectory;
  final String? cameraName;
  final StreamOutputResolution outputResolution;
  final StreamVideoBitrate videoBitrate;
  final StreamFrameRate frameRate;
  final CameraCaptureResolution captureResolution;
  final VideoEncoderPreference encoderPreference;
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
  static const _startupShowTitleKey = 'stream.startupSplashShowTitle';
  static const _shutdownShowTitleKey = 'stream.shutdownSplashShowTitle';
  static const _startupDurationKey = 'stream.startupSplashDurationSeconds';
  static const _shutdownDurationKey = 'stream.shutdownSplashDurationSeconds';
  static const _startupBackgroundKey = 'stream.startupSplashBackgroundPath';
  static const _shutdownBackgroundKey = 'stream.shutdownSplashBackgroundPath';
  static const _youtubeDescriptionKey = 'stream.youtubeDescription';
  static const _supportContactNameKey = 'app.supportContactName';
  static const _supportContactPhoneKey = 'app.supportContactPhone';
  static const _recordingDirectoryKey = 'stream.recordingDirectory';
  static const _recordLocallyKey = 'stream.recordLocally';
  static const _privacyKey = 'stream.privacy';
  static const _cameraNameKey = 'stream.cameraName';
  static const _outputResolutionKey = 'stream.outputResolution';
  static const _videoBitrateKey = 'stream.videoBitrate';
  static const _frameRateKey = 'stream.frameRate';
  static const _captureResolutionKey = 'stream.captureResolution';
  static const _encoderPreferenceKey = 'stream.encoderPreference';

  @override
  Future<StreamTextSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    final privacyName = preferences.getString(_privacyKey);
    return StreamTextSettings(
      startupSplashEnabled: preferences.getBool(_startupEnabledKey) ?? true,
      shutdownSplashEnabled: preferences.getBool(_shutdownEnabledKey) ?? true,
      startupSplashShowTitle: preferences.getBool(_startupShowTitleKey) ?? true,
      shutdownSplashShowTitle:
          preferences.getBool(_shutdownShowTitleKey) ?? false,
      startupSplashDurationSeconds:
          preferences.getInt(_startupDurationKey) ?? 5,
      shutdownSplashDurationSeconds:
          preferences.getInt(_shutdownDurationKey) ?? 5,
      startupSplashBackgroundPath:
          preferences.getString(_startupBackgroundKey) ?? '',
      shutdownSplashBackgroundPath:
          preferences.getString(_shutdownBackgroundKey) ?? '',
      youtubeDescription:
          preferences.getString(_youtubeDescriptionKey) ??
          StreamSession.defaultYouTubeDescription,
      supportContactName: preferences.getString(_supportContactNameKey) ?? '',
      supportContactPhone: preferences.getString(_supportContactPhoneKey) ?? '',
      privacy: ServicePrivacy.values.firstWhere(
        (value) => value.name == privacyName,
        orElse: () => ServicePrivacy.unlisted,
      ),
      recordLocally: preferences.getBool(_recordLocallyKey) ?? true,
      recordingDirectory: preferences.getString(_recordingDirectoryKey) ?? '',
      cameraName: preferences.getString(_cameraNameKey),
      outputResolution: StreamOutputResolution.values.firstWhere(
        (value) => value.name == preferences.getString(_outputResolutionKey),
        orElse: () => StreamOutputResolution.original,
      ),
      videoBitrate: StreamVideoBitrate.values.firstWhere(
        (value) => value.name == preferences.getString(_videoBitrateKey),
        orElse: () => StreamVideoBitrate.standard,
      ),
      frameRate: StreamFrameRate.values.firstWhere(
        (value) => value.name == preferences.getString(_frameRateKey),
        orElse: () => StreamFrameRate.fps30,
      ),
      captureResolution: CameraCaptureResolution.values.firstWhere(
        (value) => value.name == preferences.getString(_captureResolutionKey),
        orElse: () => CameraCaptureResolution.automatic,
      ),
      encoderPreference: VideoEncoderPreference.values.firstWhere(
        (value) => value.name == preferences.getString(_encoderPreferenceKey),
        orElse: () => VideoEncoderPreference.automatic,
      ),
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
      preferences.setBool(
        _startupShowTitleKey,
        settings.startupSplashShowTitle,
      ),
      preferences.setBool(
        _shutdownShowTitleKey,
        settings.shutdownSplashShowTitle,
      ),
      preferences.setInt(
        _startupDurationKey,
        settings.startupSplashDurationSeconds,
      ),
      preferences.setInt(
        _shutdownDurationKey,
        settings.shutdownSplashDurationSeconds,
      ),
      preferences.setString(
        _startupBackgroundKey,
        settings.startupSplashBackgroundPath,
      ),
      preferences.setString(
        _shutdownBackgroundKey,
        settings.shutdownSplashBackgroundPath,
      ),
      preferences.setString(
        _youtubeDescriptionKey,
        settings.youtubeDescription,
      ),
      preferences.setString(
        _supportContactNameKey,
        settings.supportContactName,
      ),
      preferences.setString(
        _supportContactPhoneKey,
        settings.supportContactPhone,
      ),
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
      preferences.setString(
        _outputResolutionKey,
        settings.outputResolution.name,
      ),
      preferences.setString(_videoBitrateKey, settings.videoBitrate.name),
      preferences.setString(_frameRateKey, settings.frameRate.name),
      preferences.setString(
        _captureResolutionKey,
        settings.captureResolution.name,
      ),
      preferences.setString(
        _encoderPreferenceKey,
        settings.encoderPreference.name,
      ),
    ]);
  }
}
