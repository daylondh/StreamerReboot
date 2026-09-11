part of 'ffmpeg_stream_engine.dart';

/// A bounded PCM buffer used between recorder callbacks and the 20 ms mixer.
///
/// Recorder callbacks and Dart timers do not run at perfectly matching rates.
/// Keeping every surplus byte makes a tiny clock mismatch grow for the entire
/// stream, and `Queue<int>` magnifies that into substantial heap pressure. Store
/// whole chunks and discard the oldest audio once the useful delay window plus
/// jitter headroom has been exceeded.
@visibleForTesting
class PcmQueue {
  PcmQueue({this.maxBufferBytes = 192000});

  final int maxBufferBytes;
  final Queue<Uint8List> _chunks = Queue<Uint8List>();
  int _headOffset = 0;
  int _length = 0;
  int _bufferedDelayBytes = 0;

  int get length => _length;

  void add(Uint8List bytes) {
    if (bytes.isEmpty) return;
    _chunks.add(bytes);
    _length += bytes.length;
    _discard(_length - maxBufferBytes);
  }

  Uint8List take(int count) {
    final output = Uint8List(count);
    var outputOffset = 0;
    while (outputOffset < count && _chunks.isNotEmpty) {
      final chunk = _chunks.first;
      final available = chunk.length - _headOffset;
      final copied = math.min(count - outputOffset, available);
      output.setRange(outputOffset, outputOffset + copied, chunk, _headOffset);
      outputOffset += copied;
      _headOffset += copied;
      _length -= copied;
      if (_headOffset == chunk.length) {
        _chunks.removeFirst();
        _headOffset = 0;
      }
    }
    return output;
  }

  Uint8List takeDelayed(int count, int delayBytes) {
    if (delayBytes < _bufferedDelayBytes) {
      _discard(_bufferedDelayBytes - delayBytes);
      _bufferedDelayBytes = delayBytes;
    } else if (delayBytes > _bufferedDelayBytes) {
      // Emit silence only while intentionally growing the delay buffer. Once
      // primed, consume whatever capture supplied this tick, just as the
      // original non-delayed mixer did, instead of converting input jitter to
      // repeated 20 ms gaps.
      if (_length < delayBytes + count) return Uint8List(count);
      _bufferedDelayBytes = delayBytes;
    }
    return take(count);
  }

  void _discard(int count) {
    var remaining = math.min(math.max(count, 0), _length);
    while (remaining > 0 && _chunks.isNotEmpty) {
      final chunk = _chunks.first;
      final available = chunk.length - _headOffset;
      final discarded = math.min(remaining, available);
      _headOffset += discarded;
      _length -= discarded;
      remaining -= discarded;
      if (_headOffset == chunk.length) {
        _chunks.removeFirst();
        _headOffset = 0;
      }
    }
  }
}

class _DelayedVideoQueue {
  final Queue<_DelayedVideoFrame> _frames = Queue<_DelayedVideoFrame>();
  Timer? _timer;
  Future<void>? _pendingWrite;

  void add(
    Uint8List bytes,
    Duration delay,
    Socket socket,
    void Function(Object error) onError, {
    required int frameRate,
  }) {
    _frames.add(_DelayedVideoFrame(bytes, DateTime.now().add(delay)));
    // Retain enough frames for the selected delay, plus two frames of
    // scheduling headroom. Using the actual capture rate is important here:
    // eight unnecessary 4K BGRA frames consume roughly 265 MB.
    final maxFrames = math.max(
      2,
      (delay.inMicroseconds * frameRate / Duration.microsecondsPerSecond)
              .ceil() +
          2,
    );
    while (_frames.length > maxFrames) {
      _frames.removeFirst();
    }
    _schedule(socket, onError);
  }

  void _schedule(Socket socket, void Function(Object error) onError) {
    _timer?.cancel();
    _timer = null;
    if (_pendingWrite != null) return;
    if (_frames.isEmpty) return;
    final wait = _frames.first.sendAt.difference(DateTime.now());
    if (wait.isNegative || wait == Duration.zero) {
      _writeNextDueFrame(socket, onError);
    } else {
      _timer = Timer(wait, () => _writeNextDueFrame(socket, onError));
    }
  }

  void _writeNextDueFrame(Socket socket, void Function(Object error) onError) {
    if (_pendingWrite != null || _frames.isEmpty) return;
    final now = DateTime.now();
    if (_frames.first.sendAt.isAfter(now)) {
      _schedule(socket, onError);
      return;
    }
    var frame = _frames.removeFirst();
    // Once a write has taken longer than a frame interval, replaying every
    // overdue frame only creates another stall and gives rawvideo misleading
    // arrival timestamps. Keep the newest frame whose requested delay has
    // elapsed; CFR output will duplicate the preceding frame for any missed
    // interval instead of playing a burst of stale pictures.
    while (_frames.isNotEmpty && !_frames.first.sendAt.isAfter(now)) {
      frame = _frames.removeFirst();
    }
    late final Future<void> write;
    write = _writeFrame(socket, frame.bytes, onError).whenComplete(() {
      if (identical(_pendingWrite, write)) _pendingWrite = null;
      _schedule(socket, onError);
    });
    _pendingWrite = write;
    unawaited(write);
  }

  Future<void> _writeFrame(
    Socket socket,
    Uint8List bytes,
    void Function(Object error) onError,
  ) async {
    try {
      socket.add(bytes);
      await socket.flush();
    } catch (error) {
      onError(error);
    }
  }

  void clear() {
    _timer?.cancel();
    _timer = null;
    _frames.clear();
  }
}

class _DelayedVideoFrame {
  const _DelayedVideoFrame(this.bytes, this.sendAt);
  final Uint8List bytes;
  final DateTime sendAt;
}
