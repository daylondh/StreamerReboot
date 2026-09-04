import '../domain/stream_session.dart';
import 'package:flutter/foundation.dart';
import 'stream_engine.dart';
import 'youtube_live_service.dart';

/// Couples local recording to YouTube broadcast and ingest-stream creation.
class YouTubeProvisioningStreamEngine implements StreamEngine {
  YouTubeProvisioningStreamEngine({
    required this.localRecording,
    required this.youtube,
  });

  final StreamEngine localRecording;
  final YouTubeLiveService youtube;

  @override
  Future<void> start(StreamSession session) async {
    if (!youtube.isConnected) {
      throw StateError('Connect a YouTube channel before going live.');
    }
    await youtube.prepareBroadcast(session);
    while (true) {
      try {
        await localRecording.start(session);
        if (localRecording case StreamProcessMonitor monitor) {
          final outcome = await Future.any<Object?>([
            youtube.startBroadcast(),
            monitor.processExitCode.then<Object?>((exitCode) {
              return StateError(
                'FFmpeg exited with code $exitCode before YouTube received '
                'video: ${monitor.diagnosticSummary}',
              );
            }),
          ]);
          if (outcome case final Object error) {
            youtube.reportPublisherError(error);
            throw error;
          }
        } else {
          await youtube.startBroadcast();
        }
        return;
      } catch (error, stackTrace) {
        debugPrint('[Stream startup] $error');
        youtube.cancelPendingStart();
        try {
          await localRecording.stop(session);
        } catch (_) {
          // Preserve the failure which caused this attempt to abort.
        }
        if (youtube.useFallbackIngestion()) {
          continue;
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
  }

  @override
  Future<void> switchCamera(String cameraName) =>
      localRecording.switchCamera(cameraName);

  @override
  Future<void> stop(StreamSession session) async {
    Object? recordingError;
    try {
      await localRecording.stop(session);
    } catch (error) {
      recordingError = error;
    }

    Object? youtubeError;
    try {
      await youtube.finishBroadcast();
    } catch (error) {
      youtubeError = error;
    }

    if (recordingError != null) throw recordingError;
    if (youtubeError != null) throw youtubeError;
  }
}
