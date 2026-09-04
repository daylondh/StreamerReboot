import '../domain/stream_session.dart';
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
    await localRecording.start(session);
  }

  @override
  Future<void> switchCamera(String cameraName) =>
      localRecording.switchCamera(cameraName);

  @override
  Future<void> stop(StreamSession session) => localRecording.stop(session);
}
