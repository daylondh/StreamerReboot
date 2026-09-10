import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:file_selector/file_selector.dart';
import 'package:url_launcher/url_launcher.dart';
import 'controllers/audio_sources_controller.dart';
import 'controllers/camera_sources_controller.dart';
import 'controllers/stream_controller.dart';
import 'domain/stream_session.dart';
import 'services/media_permission_service.dart';
import 'services/app_log.dart';
import 'services/ffmpeg_stream_engine.dart';
import 'services/stream_engine.dart';
import 'services/stream_settings_store.dart';
import 'services/youtube_live_service.dart';
import 'services/youtube_provisioning_stream_engine.dart';
import 'ui/app_theme.dart';

part 'ui/startup_gate.dart';
part 'ui/settings_dialog.dart';
part 'ui/splash_settings_dialog.dart';
part 'ui/support_contact_banner.dart';
part 'ui/audio_panel.dart';
part 'ui/camera_feed.dart';
part 'ui/camera_panel.dart';
part 'ui/dashboard_controls.dart';
part 'ui/dashboard_view.dart';
part 'ui/go_live_bar.dart';
part 'ui/shared_widgets.dart';
part 'ui/youtube_destination.dart';

class ChurchStreamerApp extends StatelessWidget {
  const ChurchStreamerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Church Streamer',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: const _StartupGate(),
  );
}

class StreamDashboard extends StatefulWidget {
  const StreamDashboard({
    required this.controller,
    required this.cameraSources,
    required this.audioSources,
    required this.recordingEngine,
    required this.youtube,
    super.key,
  });
  final StreamController controller;
  final CameraSourcesController cameraSources;
  final AudioSourcesController audioSources;
  final FfmpegStreamEngine recordingEngine;
  final YouTubeLiveService youtube;

  @override
  State<StreamDashboard> createState() => _StreamDashboardState();
}

class _StreamDashboardState extends State<StreamDashboard> {
  late final TextEditingController _titleController;
  late final TextEditingController _startupTextController;
  late final TextEditingController _shutdownTextController;
  late final CameraSourcesController _cameraSources;
  late final AudioSourcesController _audioSources;
  final MediaPermissionService _permissions = MediaPermissionService();
  String? _permissionMessage;
  bool _requestingPermissions = false;
  bool _isQuitting = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.controller.session.title,
    );
    _startupTextController = TextEditingController(
      text: widget.controller.session.startupText,
    );
    _shutdownTextController = TextEditingController(
      text: widget.controller.session.shutdownText,
    );
    widget.controller.addListener(_syncTextFromSession);
    _cameraSources = widget.cameraSources;
    _audioSources = widget.audioSources;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _initializeMediaAccess(),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _startupTextController.dispose();
    _shutdownTextController.dispose();
    widget.controller.removeListener(_syncTextFromSession);
    _cameraSources.dispose();
    widget.recordingEngine.dispose();
    widget.youtube.dispose();
    _audioSources.dispose();
    widget.controller.dispose();
    super.dispose();
  }

  void _syncTextFromSession() {
    _syncController(_titleController, widget.controller.session.title);
    _syncController(
      _startupTextController,
      widget.controller.session.startupText,
    );
    _syncController(
      _shutdownTextController,
      widget.controller.session.shutdownText,
    );
  }

  void _syncController(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  Future<void> _initializeMediaAccess() async {
    if (_requestingPermissions) return;
    setState(() {
      _requestingPermissions = true;
      _permissionMessage = null;
    });
    try {
      final status = await _permissions.check();
      if (!mounted) return;
      if (status.allGranted) {
        await _discoverMedia();
      } else if (status.hasDenied) {
        _showDenied(status);
      } else if (status.needsRequest) {
        setState(() => _requestingPermissions = false);
        await _requestMediaAccess();
        return;
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() {
          _permissionMessage =
              error.message ?? 'Could not check media permissions.';
        });
      }
    } finally {
      if (mounted) setState(() => _requestingPermissions = false);
    }
  }

  Future<void> _requestMediaAccess() async {
    if (_requestingPermissions) return;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.perm_camera_mic_outlined, size: 36),
        title: const Text('Allow camera and microphone access?'),
        content: const Text(
          'Church Streamer needs cameras for live video previews and microphones for service audio. Media stays on this computer unless you start a stream.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (accepted != true) {
      setState(() {
        _permissionMessage =
            'Camera and microphone access is required to preview and broadcast a service.';
      });
      return;
    }

    setState(() {
      _requestingPermissions = true;
      _permissionMessage = null;
    });
    try {
      final result = await _permissions.request();
      if (!mounted) return;
      if (!result.allGranted) {
        _showDenied(result);
        return;
      }
      await _discoverMedia();
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() {
          _permissionMessage =
              error.message ??
              'The operating system could not request media access.';
        });
      }
    } finally {
      if (mounted) setState(() => _requestingPermissions = false);
    }
  }

  Future<void> _discoverMedia() async {
    final session = widget.controller.session;
    _cameraSources.configure(
      captureResolution: session.captureResolution,
      frameRate: session.frameRate,
    );
    await Future.wait([_cameraSources.discover(), _audioSources.discover()]);
    if (!mounted) return;
    final selectedName = widget.controller.session.cameraName;
    final readySources = _cameraSources.sources.where(
      (source) => source.isReady,
    );
    if (readySources.isEmpty) return;
    if (selectedName == null ||
        !readySources.any(
          (source) => source.description.name == selectedName,
        )) {
      await widget.controller.selectCamera(readySources.first.description.name);
    }
  }

  void _showDenied(MediaPermissionResult result) {
    final denied = [
      if (result.camera == MediaAuthorization.denied) 'camera',
      if (result.microphone == MediaAuthorization.denied) 'microphone',
    ].join(' and ');
    setState(() {
      _permissionMessage =
          '$denied access is blocked. Enable it for Church Streamer in System Settings, then check again.';
    });
  }

  Future<void> _quit() async {
    if (_isQuitting) return;
    setState(() => _isQuitting = true);

    try {
      await widget.controller.shutdown();
    } catch (error) {
      logMessage('Stream cleanup during quit failed: $error');
    }
    try {
      await Future.wait([_cameraSources.release(), _audioSources.release()]);
    } catch (error) {
      logMessage('Media resource cleanup during quit failed: $error');
    }

    await SystemNavigator.pop();
    exit(0);
  }

  Future<void> _showSettings() async {
    await showDialog<void>(
      context: context,
      builder: (context) =>
          _ApplicationSettingsDialog(controller: widget.controller),
    );
  }

  @override
  Widget build(BuildContext context) => _DashboardView(
    controller: widget.controller,
    titleController: _titleController,
    startupTextController: _startupTextController,
    shutdownTextController: _shutdownTextController,
    cameraSources: _cameraSources,
    audioSources: _audioSources,
    recordingEngine: widget.recordingEngine,
    youtube: widget.youtube,
    permissionMessage: _permissionMessage,
    requestingPermissions: _requestingPermissions,
    isQuitting: _isQuitting,
    onQuit: _quit,
    onSettings: _showSettings,
    onRequestPermissions: _initializeMediaAccess,
  );
}
