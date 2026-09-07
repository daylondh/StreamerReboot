enum StreamStatus { idle, preparing, live, stopping, failed }

enum ServicePrivacy { public, unlisted, private }

enum StreamOutputResolution {
  original(null, 'Original'),
  p1080(1080, '1080p'),
  p720(720, '720p'),
  p480(480, '480p');

  const StreamOutputResolution(this.maxHeight, this.label);

  final int? maxHeight;
  final String label;
}

enum StreamVideoBitrate {
  low(2500, '2.5 Mbps'),
  standard(4500, '4.5 Mbps'),
  high(6000, '6 Mbps'),
  maximum(9000, '9 Mbps');

  const StreamVideoBitrate(this.kbps, this.label);
  final int kbps;
  final String label;
}

enum StreamFrameRate {
  fps24(24, '24 fps'),
  fps30(30, '30 fps'),
  fps60(60, '60 fps');

  const StreamFrameRate(this.value, this.label);
  final int value;
  final String label;
}

enum CameraCaptureResolution {
  automatic('Automatic'),
  p720('720p'),
  p1080('1080p'),
  maximum('Maximum');

  const CameraCaptureResolution(this.label);
  final String label;
}

enum VideoEncoderPreference {
  automatic('Automatic'),
  hardware('Hardware'),
  software('Software');

  const VideoEncoderPreference(this.label);
  final String label;
}

class StreamSession {
  const StreamSession({
    required this.title,
    this.privacy = ServicePrivacy.unlisted,
    this.recordLocally = true,
    this.recordingDirectory = '',
    this.cameraName,
    this.outputResolution = StreamOutputResolution.original,
    this.videoBitrate = StreamVideoBitrate.standard,
    this.frameRate = StreamFrameRate.fps30,
    this.captureResolution = CameraCaptureResolution.automatic,
    this.encoderPreference = VideoEncoderPreference.automatic,
    this.startupSplashEnabled = true,
    this.shutdownSplashEnabled = true,
    this.startupSplashShowTitle = true,
    this.shutdownSplashShowTitle = false,
    this.startupSplashDurationSeconds = 5,
    this.shutdownSplashDurationSeconds = 5,
    this.startupSplashBackgroundPath = '',
    this.shutdownSplashBackgroundPath = '',
    this.startupText = '',
    this.shutdownText = '',
    this.status = StreamStatus.idle,
    this.startedAt,
    this.error,
  });
  final String title;
  final ServicePrivacy privacy;
  final bool recordLocally;
  final String recordingDirectory;
  final String? cameraName;
  final StreamOutputResolution outputResolution;
  final StreamVideoBitrate videoBitrate;
  final StreamFrameRate frameRate;
  final CameraCaptureResolution captureResolution;
  final VideoEncoderPreference encoderPreference;
  final bool startupSplashEnabled;
  final bool shutdownSplashEnabled;
  final bool startupSplashShowTitle;
  final bool shutdownSplashShowTitle;
  final int startupSplashDurationSeconds;
  final int shutdownSplashDurationSeconds;
  final String startupSplashBackgroundPath;
  final String shutdownSplashBackgroundPath;
  final String startupText;
  final String shutdownText;
  final StreamStatus status;
  final DateTime? startedAt;
  final String? error;
  bool get isBusy =>
      status == StreamStatus.preparing || status == StreamStatus.stopping;
  bool get isLive => status == StreamStatus.live;

  StreamSession copyWith({
    String? title,
    ServicePrivacy? privacy,
    bool? recordLocally,
    String? recordingDirectory,
    String? cameraName,
    StreamOutputResolution? outputResolution,
    StreamVideoBitrate? videoBitrate,
    StreamFrameRate? frameRate,
    CameraCaptureResolution? captureResolution,
    VideoEncoderPreference? encoderPreference,
    bool? startupSplashEnabled,
    bool? shutdownSplashEnabled,
    bool? startupSplashShowTitle,
    bool? shutdownSplashShowTitle,
    int? startupSplashDurationSeconds,
    int? shutdownSplashDurationSeconds,
    String? startupSplashBackgroundPath,
    String? shutdownSplashBackgroundPath,
    String? startupText,
    String? shutdownText,
    StreamStatus? status,
    DateTime? startedAt,
    String? error,
    bool clearError = false,
  }) => StreamSession(
    title: title ?? this.title,
    privacy: privacy ?? this.privacy,
    recordLocally: recordLocally ?? this.recordLocally,
    recordingDirectory: recordingDirectory ?? this.recordingDirectory,
    cameraName: cameraName ?? this.cameraName,
    outputResolution: outputResolution ?? this.outputResolution,
    videoBitrate: videoBitrate ?? this.videoBitrate,
    frameRate: frameRate ?? this.frameRate,
    captureResolution: captureResolution ?? this.captureResolution,
    encoderPreference: encoderPreference ?? this.encoderPreference,
    startupSplashEnabled: startupSplashEnabled ?? this.startupSplashEnabled,
    shutdownSplashEnabled: shutdownSplashEnabled ?? this.shutdownSplashEnabled,
    startupSplashShowTitle:
        startupSplashShowTitle ?? this.startupSplashShowTitle,
    shutdownSplashShowTitle:
        shutdownSplashShowTitle ?? this.shutdownSplashShowTitle,
    startupSplashDurationSeconds:
        startupSplashDurationSeconds ?? this.startupSplashDurationSeconds,
    shutdownSplashDurationSeconds:
        shutdownSplashDurationSeconds ?? this.shutdownSplashDurationSeconds,
    startupSplashBackgroundPath:
        startupSplashBackgroundPath ?? this.startupSplashBackgroundPath,
    shutdownSplashBackgroundPath:
        shutdownSplashBackgroundPath ?? this.shutdownSplashBackgroundPath,
    startupText: startupText ?? this.startupText,
    shutdownText: shutdownText ?? this.shutdownText,
    status: status ?? this.status,
    startedAt: startedAt ?? this.startedAt,
    error: clearError ? null : error ?? this.error,
  );
}
