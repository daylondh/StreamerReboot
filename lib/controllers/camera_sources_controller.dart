import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

class CameraSource {
  CameraSource({required this.description, this.controller, this.error});
  final CameraDescription description;
  CameraController? controller;
  String? error;
  bool get isReady => controller?.value.isInitialized ?? false;
}

class CameraSourcesController extends ChangeNotifier {
  final List<CameraSource> _sources = [];
  bool _isDiscovering = false;
  String? _discoveryError;

  List<CameraSource> get sources => List.unmodifiable(_sources);
  bool get isDiscovering => _isDiscovering;
  String? get discoveryError => _discoveryError;

  Future<void> discover() async {
    if (_isDiscovering) return;
    _isDiscovering = true;
    _discoveryError = null;
    notifyListeners();
    await _disposeSources();
    try {
      final cameras = await availableCameras();
      _sources.addAll(
        cameras.map((camera) => CameraSource(description: camera)),
      );
      notifyListeners();
      // Sequential initialization is friendlier to bandwidth-limited USB hubs.
      for (final source in _sources) {
        await _initialize(source);
      }
    } on CameraException catch (error) {
      _discoveryError = error.description ?? error.code;
    } catch (error) {
      _discoveryError = error.toString();
    } finally {
      _isDiscovering = false;
      notifyListeners();
    }
  }

  Future<void> _initialize(CameraSource source) async {
    final controller = CameraController(
      source.description,
      ResolutionPreset.high,
      // The local recording backend uses the camera package's native A/V
      // writer. Preview remains silent, while recorded files include audio.
      enableAudio: true,
      fps: 30,
    );
    source.controller = controller;
    try {
      await controller.initialize();
    } on CameraException catch (error) {
      source.error = error.description ?? error.code;
      await controller.dispose();
      source.controller = null;
    } catch (error) {
      source.error = error.toString();
      await controller.dispose();
      source.controller = null;
    }
    notifyListeners();
  }

  Future<void> _disposeSources() async {
    // Detach previews before disposing their controllers. CameraController
    // notifies listeners during disposal, and a still-mounted CameraPreview
    // would otherwise try to render the already-disposed controller.
    final sources = List<CameraSource>.of(_sources);
    _sources.clear();
    notifyListeners();
    for (final source in sources) {
      await source.controller?.dispose();
    }
  }

  Future<void> release() async {
    await _disposeSources();
    notifyListeners();
  }

  @override
  void dispose() {
    for (final source in _sources) {
      source.controller?.dispose();
    }
    super.dispose();
  }
}
