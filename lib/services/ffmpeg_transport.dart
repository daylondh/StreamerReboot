part of 'ffmpeg_stream_engine.dart';

extension _FfmpegTransport on FfmpegStreamEngine {
  void _consumeSocketErrors(Socket socket, String channel) {
    socket.listen(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        _recordTransportError(channel, error);
      },
    );
    unawaited(
      socket.done.catchError((Object error, StackTrace stackTrace) {
        _recordTransportError(channel, error);
      }),
    );
  }

  void _recordTransportError(String channel, Object error) {
    if (_stopping) return;
    _transportError ??= error;
    final message = _sanitizeDiagnostic('$channel transport: $error');
    _transportDiagnostics.add(message);
    logMessage('[FFmpeg transport] $message');
    if (_transportDiagnostics.length > 10) {
      _transportDiagnostics.removeAt(0);
    }
  }

  Future<void> _tearDownMedia({required bool killProcess}) async {
    if (killProcess) _process?.kill();
    await _closeInputFeeds();
    await _ignoreCleanup(_stderrSubscription?.cancel(), 'FFmpeg diagnostics');
    _stderrSubscription = null;
    _process = null;
    _frameWidth = null;
    _frameHeight = null;
    _pixelFormat = null;
    _outputPath = null;
    _sensitiveIngestionUrl = null;
    _transportError = null;
  }

  Future<void> _closeInputFeeds() async {
    _slateGeneration++;
    _slateTimer?.cancel();
    _slateTimer = null;
    _slateActive = false;
    _fadeSlate = null;
    _fadeStartedAt = null;
    _audioTimer?.cancel();
    _audioTimer = null;
    for (final subscription in _audioSubscriptions) {
      await _ignoreCleanup(subscription.cancel(), 'audio subscription');
    }
    _audioSubscriptions.clear();
    _audioQueues.clear();
    _videoQueue.clear();
    _startupSlate = null;
    _shutdownSlate = null;
    final startupRelease = _startupSlateRelease;
    if (startupRelease != null && !startupRelease.isCompleted) {
      startupRelease.complete();
    }
    _startupSlateRelease = null;
    final camera = _camera;
    _camera = null;
    _activeCameraName = null;
    if (camera?.value.isStreamingImages ?? false) {
      await _ignoreCleanup(camera!.stopImageStream(), 'camera image stream');
    }
    await _closeSocket(_videoSocket, 'video socket');
    await _closeSocket(_audioSocket, 'audio socket');
    await _ignoreCleanup(_videoServer?.close(), 'video server');
    await _ignoreCleanup(_audioServer?.close(), 'audio server');
    _videoSocket = null;
    _audioSocket = null;
    _videoServer = null;
    _audioServer = null;
  }

  Future<void> _closeSocket(Socket? socket, String resource) async {
    if (socket == null) return;
    try {
      await socket.close().timeout(FfmpegStreamEngine._cleanupTimeout);
    } on TimeoutException {
      logMessage(
        '[FFmpeg cleanup] $resource did not finish within '
        '${FfmpegStreamEngine._cleanupTimeout.inSeconds} seconds; forcing it closed.',
      );
      socket.destroy();
    } catch (error) {
      _recordTransportError(resource, error);
      socket.destroy();
    }
  }

  Future<void> _flushVideoFeed() async {
    final socket = _videoSocket;
    if (socket == null) return;
    try {
      await socket.flush().timeout(const Duration(seconds: 15));
    } on TimeoutException {
      logMessage(
        '[Splash] Video feed did not drain within 15 seconds; '
        'continuing shutdown.',
      );
    } catch (error) {
      logMessage('[Splash] Could not flush shutdown video: $error');
    }
  }

  Future<void> _ignoreCleanup(Future<void>? operation, String resource) async {
    if (operation == null) return;
    try {
      await operation.timeout(FfmpegStreamEngine._cleanupTimeout);
    } on TimeoutException {
      logMessage(
        '[FFmpeg cleanup] $resource did not finish within '
        '${FfmpegStreamEngine._cleanupTimeout.inSeconds} seconds; continuing shutdown.',
      );
    } catch (error) {
      _recordTransportError(resource, error);
    }
  }
}
