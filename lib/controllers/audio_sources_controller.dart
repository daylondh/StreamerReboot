import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

class AudioSource {
  AudioSource({required this.device, required this.recorder});

  final InputDevice device;
  final AudioRecorder recorder;
  bool enabled = true;
  double gain = 1;
  double level = 0;
  String? error;
  StreamSubscription<Amplitude>? amplitudeSubscription;
  StreamSubscription<Uint8List>? dataSubscription;
  final StreamController<Uint8List> mixedAudio =
      StreamController<Uint8List>.broadcast();
}

class AudioSourcesController extends ChangeNotifier {
  final List<AudioSource> _sources = [];
  bool _isDiscovering = false;
  String? _discoveryError;

  List<AudioSource> get sources => List.unmodifiable(_sources);
  bool get isDiscovering => _isDiscovering;
  String? get discoveryError => _discoveryError;

  static double meterLevel(double dbfs, double gain) =>
      (math.pow(10, dbfs / 20).toDouble() * gain).clamp(0, 1);

  Future<void> discover() async {
    if (_isDiscovering) return;
    _isDiscovering = true;
    _discoveryError = null;
    notifyListeners();
    await _disposeSources();

    final enumerator = AudioRecorder();
    try {
      if (!await enumerator.hasPermission()) {
        _discoveryError = 'Microphone access was denied.';
        return;
      }
      final devices = await enumerator.listInputDevices();
      for (final device in devices) {
        final source = AudioSource(device: device, recorder: AudioRecorder());
        _sources.add(source);
        notifyListeners();
        await _start(source);
      }
    } catch (error) {
      _discoveryError = error.toString();
    } finally {
      await enumerator.dispose();
      _isDiscovering = false;
      notifyListeners();
    }
  }

  Future<void> setEnabled(AudioSource source, bool enabled) async {
    if (source.enabled == enabled) return;
    source.enabled = enabled;
    source.error = null;
    source.level = 0;
    notifyListeners();
    if (enabled) {
      await _start(source);
    } else {
      await _stop(source);
    }
  }

  void setGain(AudioSource source, double gain) {
    source.gain = gain;
    notifyListeners();
  }

  Future<void> _start(AudioSource source) async {
    try {
      final data = await source.recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 48000,
          numChannels: 1,
          device: source.device,
          autoGain: false,
          echoCancel: false,
          noiseSuppress: false,
        ),
      );
      source.dataSubscription = data.listen((chunk) {
        source.mixedAudio.add(_applyGain(chunk, source.gain));
      });
      source.amplitudeSubscription = source.recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((amplitude) {
            // Convert dBFS to a 0–1 linear meter, then apply the software gain
            // that will also feed the eventual stream mixer.
            source.level = meterLevel(amplitude.current, source.gain);
            notifyListeners();
          });
    } catch (error) {
      source.error = error.toString();
      source.enabled = false;
      source.level = 0;
      notifyListeners();
    }
  }

  Uint8List _applyGain(Uint8List input, double gain) {
    if (gain == 1) return input;
    final output = Uint8List(input.length);
    final inputData = ByteData.sublistView(input);
    final outputData = ByteData.sublistView(output);
    for (var offset = 0; offset + 1 < input.length; offset += 2) {
      final sample = inputData.getInt16(offset, Endian.little);
      final adjusted = (sample * gain).round().clamp(-32768, 32767);
      outputData.setInt16(offset, adjusted, Endian.little);
    }
    return output;
  }

  Future<void> _stop(AudioSource source) async {
    await source.amplitudeSubscription?.cancel();
    await source.dataSubscription?.cancel();
    source.amplitudeSubscription = null;
    source.dataSubscription = null;
    try {
      await source.recorder.stop();
    } catch (_) {
      // The backend may already be stopped after a device disconnect.
    }
  }

  Future<void> _disposeSources() async {
    for (final source in _sources) {
      await _disposeSource(source);
    }
    _sources.clear();
  }

  Future<void> release() async {
    await _disposeSources();
    notifyListeners();
  }

  Future<void> _disposeSource(AudioSource source) async {
    await _stop(source);
    await source.recorder.dispose();
    await source.mixedAudio.close();
  }

  @override
  void dispose() {
    for (final source in _sources) {
      unawaited(_disposeSource(source));
    }
    super.dispose();
  }
}
