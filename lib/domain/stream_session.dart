enum StreamStatus { idle, preparing, live, stopping, failed }

enum ServicePrivacy { public, unlisted, private }

class StreamSession {
  const StreamSession({
    required this.title,
    this.privacy = ServicePrivacy.unlisted,
    this.recordLocally = true,
    this.recordingDirectory = '',
    this.cameraName,
    this.startupSplashEnabled = true,
    this.shutdownSplashEnabled = true,
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
  final bool startupSplashEnabled;
  final bool shutdownSplashEnabled;
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
    bool? startupSplashEnabled,
    bool? shutdownSplashEnabled,
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
    startupSplashEnabled: startupSplashEnabled ?? this.startupSplashEnabled,
    shutdownSplashEnabled: shutdownSplashEnabled ?? this.shutdownSplashEnabled,
    startupText: startupText ?? this.startupText,
    shutdownText: shutdownText ?? this.shutdownText,
    status: status ?? this.status,
    startedAt: startedAt ?? this.startedAt,
    error: clearError ? null : error ?? this.error,
  );
}
