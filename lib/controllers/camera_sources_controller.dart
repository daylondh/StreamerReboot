import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CameraSource {
  CameraSource({required this.description, this.controller, this.error});
  final CameraDescription description;
  CameraController? controller;
  String? error;
  int delayMs = 0;
  bool get isReady => controller?.value.isInitialized ?? false;
}

class CameraSourcesController extends ChangeNotifier {
  CameraSourcesController({
    Future<List<CameraDescription>> Function()? listCameras,
    CameraController Function(CameraDescription, ResolutionPreset)?
    createCamera,
  }) : _listCameras = listCameras ?? availableCameras,
       _createCamera = createCamera ?? _defaultCamera;

  final Future<List<CameraDescription>> Function() _listCameras;
  final CameraController Function(CameraDescription, ResolutionPreset)
  _createCamera;

  static CameraController _defaultCamera(
    CameraDescription description,
    ResolutionPreset preset,
  ) => CameraController(description, preset, enableAudio: true, fps: 30);

  static const _settingsKey = 'camera.feedDelays';
  final List<CameraSource> _sources = [];
  bool _isDiscovering = false;
  String? _discoveryError;
  Future<void> _saveChain = Future<void>.value();
  Map<String, dynamic> _persistedDelays = {};

  List<CameraSource> get sources => List.unmodifiable(_sources);
  bool get isDiscovering => _isDiscovering;
  String? get discoveryError => _discoveryError;

  void setDelay(CameraSource source, int delayMs) {
    source.delayMs = delayMs.clamp(0, 1000);
    notifyListeners();
    _saveDelays();
  }

  Future<void> discover() async {
    if (_isDiscovering) return;
    _isDiscovering = true;
    _discoveryError = null;
    notifyListeners();
    await _saveChain;
    await _disposeSources();
    try {
      final cameras = await _listCameras();
      _persistedDelays = await _loadDelays();
      _sources.addAll(
        cameras.map((camera) {
          final source = CameraSource(description: camera);
          final savedDelay = _persistedDelays[camera.name];
          if (savedDelay is num) {
            source.delayMs = savedDelay.round().clamp(0, 1000);
          }
          return source;
        }),
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

  Future<Map<String, dynamic>> _loadDelays() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_settingsKey);
    if (encoded == null) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(encoded);
      return decoded is Map<String, dynamic>
          ? Map<String, dynamic>.of(decoded)
          : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  void _saveDelays() {
    for (final source in _sources) {
      _persistedDelays[source.description.name] = source.delayMs;
    }
    final snapshot = Map<String, dynamic>.of(_persistedDelays);
    _saveChain = _saveChain.then((_) async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_settingsKey, jsonEncode(snapshot));
    });
  }

  Future<void> _initialize(CameraSource source) async {
    await _initializeWithPreset(source, ResolutionPreset.high);
    if (defaultTargetPlatform == TargetPlatform.windows &&
        (source.error?.contains('Failed to enumerate camera media types') ??
            false)) {
      // Some HDMI capture adapters expose only modes above the Windows
      // backend's 720p limit for `high`. `max` removes that height limit,
      // including for adapters that expose only 3840x2160 (4K) modes.
      await _initializeWithPreset(source, ResolutionPreset.max);
      if (source.error != null) {
        source.error =
            '${source.error}\nClose OBS and other camera apps, then choose '
            'Rescan. If this persists, the capture device may need a '
            'different Windows capture backend.';
      }
    }
    notifyListeners();
  }

  Future<void> _initializeWithPreset(
    CameraSource source,
    ResolutionPreset preset,
  ) async {
    source.error = null;
    final controller = _createCamera(source.description, preset);
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
    await _saveChain;
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
