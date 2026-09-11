part of 'ffmpeg_stream_engine.dart';

extension _FfmpegVideoPipeline on FfmpegStreamEngine {
  void _writeVideoFrame(CameraImage frame) {
    final socket = _videoSocket;
    if (socket == null || frame.planes.isEmpty || _slateActive) return;
    final targetWidth = _frameWidth;
    final targetHeight = _frameHeight;
    final targetFormat = _pixelFormat;
    if (targetWidth == null || targetHeight == null || targetFormat == null) {
      return;
    }
    final plane = frame.planes.first;
    final cameraName = _activeCameraName;
    final videoDelay = Duration(
      milliseconds: cameraName == null ? 0 : cameraDelayForName(cameraName),
    );
    final rowBytes = frame.width * 4;
    try {
      final sourceFormat = _cameraPixelFormat(frame);
      Uint8List bytes;
      if (frame.width == targetWidth &&
          frame.height == targetHeight &&
          sourceFormat == targetFormat &&
          plane.bytesPerRow == rowBytes) {
        // Retaining the plane's Uint8List keeps its Dart-managed byte buffer
        // reachable until delivery. Avoid copying an entire BGRA frame here:
        // at 1080p that was an additional ~249 MB/s allocation/copy at 30 fps
        // before FFmpeg did any work.
        bytes = plane.bytes;
      } else {
        bytes = _normalizeFrame(
          frame,
          sourceFormat: sourceFormat,
          targetWidth: targetWidth,
          targetHeight: targetHeight,
          targetFormat: targetFormat,
        );
      }
      _videoQueue.add(
        _applyFade(bytes),
        videoDelay,
        socket,
        (error) => _recordTransportError('video', error),
        frameRate: _frameRate,
      );
    } catch (error) {
      _recordTransportError('video', error);
    }
  }

  Uint8List _normalizeFrame(
    CameraImage frame, {
    required String sourceFormat,
    required int targetWidth,
    required int targetHeight,
    required String targetFormat,
  }) {
    final source = frame.planes.first;
    final output = Uint8List(targetWidth * targetHeight * 4);
    final scale = math.min(
      targetWidth / frame.width,
      targetHeight / frame.height,
    );
    final scaledWidth = (frame.width * scale).round();
    final scaledHeight = (frame.height * scale).round();
    final left = (targetWidth - scaledWidth) ~/ 2;
    final top = (targetHeight - scaledHeight) ~/ 2;
    final swapRedBlue = sourceFormat != targetFormat;

    for (var y = 0; y < scaledHeight; y++) {
      final sourceY = y * frame.height ~/ scaledHeight;
      final sourceRow = sourceY * source.bytesPerRow;
      final targetRow = (top + y) * targetWidth * 4;
      for (var x = 0; x < scaledWidth; x++) {
        final sourceX = x * frame.width ~/ scaledWidth;
        final sourceOffset = sourceRow + sourceX * 4;
        final targetOffset = targetRow + (left + x) * 4;
        if (swapRedBlue) {
          output[targetOffset] = source.bytes[sourceOffset + 2];
          output[targetOffset + 1] = source.bytes[sourceOffset + 1];
          output[targetOffset + 2] = source.bytes[sourceOffset];
        } else {
          output[targetOffset] = source.bytes[sourceOffset];
          output[targetOffset + 1] = source.bytes[sourceOffset + 1];
          output[targetOffset + 2] = source.bytes[sourceOffset + 2];
        }
        output[targetOffset + 3] = source.bytes[sourceOffset + 3];
      }
    }
    return output;
  }
}
