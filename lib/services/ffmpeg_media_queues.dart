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
    // Recorder callbacks commonly batch several 20 ms blocks. Trimming every
    // instantaneous surplus discards the next tick's valid audio and then
    // inserts silence, which sounds like low-frequency buffeting. Allow three
    // mixer blocks of callback jitter, then correct genuine clock drift one
    // 16-bit PCM sample per tick so the adjustment remains inaudible.
    final jitterHeadroomBytes = count * 3;
    final excess = _length - delayBytes - count - jitterHeadroomBytes;
    if (excess >= 2) _discard(2);
    final availableWithoutConsumingDelay = math.max(_length - delayBytes, 0);
    final available = math.min(count, availableWithoutConsumingDelay);
    if (available == count) return take(count);
    final output = Uint8List(count);
    if (available > 0) {
      output.setRange(0, available, take(available));
    }
    return output;
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

@visibleForTesting
class DelayedVideoQueue {
  DelayedVideoQueue({DateTime Function()? now})
    : _now = now ?? _createMonotonicClock();

  static DateTime Function() _createMonotonicClock() {
    final origin = DateTime.now();
    final stopwatch = Stopwatch()..start();
    return () => origin.add(stopwatch.elapsed);
  }

  final DateTime Function() _now;
  final Queue<_DelayedVideoFrame> _frames = Queue<_DelayedVideoFrame>();
  Timer? _timer;
  DateTime? _nextAcceptedAt;
  Uint8List? _lastOutput;
  Duration _delay = Duration.zero;
  IOSink? _sink;
  void Function(Object error)? _onError;
  int? _frameRate;
  DateTime? _clockStartedAt;
  int _framesWritten = 0;

  @visibleForTesting
  int get bufferedFrameCount => _frames.length;

  @visibleForTesting
  int get framesWritten => _framesWritten;

  @visibleForTesting
  void pumpClock() => _pumpClock();

  void add(
    Uint8List bytes,
    Duration delay,
    IOSink sink,
    void Function(Object error) onError, {
    required int frameRate,
  }) {
    final now = _now();
    final frameInterval = Duration(
      microseconds: (Duration.microsecondsPerSecond / frameRate).round(),
    );
    _delay = delay;
    _sink = sink;
    _onError = onError;
    if (_frameRate != frameRate) {
      _timer?.cancel();
      _timer = null;
      _frameRate = frameRate;
    }
    final nextAcceptedAt = _nextAcceptedAt;
    // Camera callbacks can arrive faster than the configured output rate. If
    // every callback is retained, the count-based bound below continually
    // evicts the oldest frame before its delay expires and no video is ever
    // delivered. Sample at the output rate, but allow ordinary capture-clock
    // jitter so a nominal 30 fps camera arriving just under every 33.33 ms
    // does not get accidentally reduced to 15 fps.
    final earlyTolerance = Duration(
      microseconds: frameInterval.inMicroseconds ~/ 5,
    );
    if (nextAcceptedAt != null &&
        now.isBefore(nextAcceptedAt.subtract(earlyTolerance))) {
      return;
    }
    _nextAcceptedAt =
        nextAcceptedAt == null || now.difference(nextAcceptedAt) > frameInterval
        ? now.add(frameInterval)
        : nextAcceptedAt.add(frameInterval);
    _frames.add(_DelayedVideoFrame(bytes, now));
    // Retain enough frames for the selected delay, plus two frames of
    // scheduling headroom. Using the configured output rate is important here:
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
    _startClock(frameInterval);
  }

  void _startClock(Duration frameInterval) {
    if (_timer != null) return;
    _clockStartedAt = _now();
    _framesWritten = 0;
    _emitFrame();
    _framesWritten = 1;
    _timer = Timer.periodic(frameInterval, (_) => _pumpClock());
  }

  void _pumpClock() {
    final startedAt = _clockStartedAt;
    final frameRate = _frameRate;
    if (startedAt == null || frameRate == null) return;
    final elapsed = _now().difference(startedAt).inMicroseconds;
    final targetFrames =
        1 +
        (math.max(elapsed, 0) * frameRate ~/ Duration.microsecondsPerSecond);
    final maxCatchUpFrames = math.max(1, (frameRate / 5).ceil());
    if (targetFrames - _framesWritten > maxCatchUpFrames) {
      _framesWritten = targetFrames - maxCatchUpFrames;
    }
    while (_framesWritten < targetFrames) {
      _emitFrame();
      _framesWritten++;
    }
  }

  void _emitFrame() {
    final sink = _sink;
    final onError = _onError;
    if (sink == null || onError == null) return;
    final targetCaptureTime = _now().subtract(_delay);
    Uint8List? selected;
    while (_frames.isNotEmpty &&
        !_frames.first.capturedAt.isAfter(targetCaptureTime)) {
      selected = _frames.removeFirst().bytes;
    }
    if (selected != null) _lastOutput = selected;
    final output =
        _lastOutput ??
        (_frames.isEmpty ? null : Uint8List(_frames.first.bytes.length));
    if (output == null) return;
    _writeFrame(sink, output, onError);
  }

  void _writeFrame(
    IOSink sink,
    Uint8List bytes,
    void Function(Object error) onError,
  ) {
    try {
      sink.add(bytes);
    } catch (error) {
      onError(error);
    }
  }

  void clear({bool preserveLastOutput = false}) {
    _timer?.cancel();
    _timer = null;
    _frames.clear();
    _nextAcceptedAt = null;
    if (!preserveLastOutput) _lastOutput = null;
    _sink = null;
    _onError = null;
    _frameRate = null;
    _clockStartedAt = null;
    _framesWritten = 0;
  }
}

class _DelayedVideoFrame {
  const _DelayedVideoFrame(this.bytes, this.capturedAt);
  final Uint8List bytes;
  final DateTime capturedAt;
}
