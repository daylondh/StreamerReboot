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

const kAccentLime = Color(0xff00ff0f);
const kAccentBlue = Color(0xff00aeff);
const kAccentTeal = Color(0xff00de94);
const kAccentGreen = Color(0xff00ff52);

class ChurchStreamerApp extends StatelessWidget {
  const ChurchStreamerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Church Streamer',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: const ColorScheme.light(
        primary: kAccentBlue,
        onPrimary: Colors.black,
        secondary: kAccentTeal,
        onSecondary: Colors.black,
        tertiary: kAccentGreen,
        onTertiary: Colors.black,
        surface: Colors.white,
        onSurface: Colors.black,
        error: Colors.black,
        onError: Colors.black,
      ),
      scaffoldBackgroundColor: Colors.white,
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: Color(0x26000000)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: Color(0x26000000)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: kAccentBlue, width: 1.5),
        ),
        filled: true,
        fillColor: Color(0xfffafafa),
      ),
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 450),
        showDuration: Duration(seconds: 8),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        textStyle: TextStyle(color: Colors.white, fontSize: 13),
        decoration: BoxDecoration(
          color: Color(0xff252525),
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
      cardTheme: const CardThemeData(
        elevation: 1,
        shadowColor: Color(0x18000000),
        margin: EdgeInsets.zero,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Color(0x22000000)),
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
    ),
    home: const _StartupGate(),
  );
}

class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  StreamController? _controller;
  CameraSourcesController? _cameraSources;
  AudioSourcesController? _audioSources;
  FfmpegStreamEngine? _recordingEngine;
  YouTubeLiveService? _youtube;

  @override
  void initState() {
    super.initState();
    _prepareApp();
  }

  Future<void> _prepareApp() async {
    final cameraSources = CameraSourcesController();
    final audioSources = AudioSourcesController();
    final youtube = YouTubeLiveService();
    final recordingEngine = FfmpegStreamEngine(
      cameraForName: (cameraName) {
        for (final source in cameraSources.sources) {
          if (source.description.name == cameraName && source.isReady) {
            return source.controller;
          }
        }
        return null;
      },
      cameraDelayForName: (cameraName) {
        for (final source in cameraSources.sources) {
          if (source.description.name == cameraName) return source.delayMs;
        }
        return 0;
      },
      audioSources: audioSources,
      ingestionUrl: () => youtube.target?.ingestionUrl,
    );
    final controller = StreamController(
      YouTubeProvisioningStreamEngine(
        localRecording: recordingEngine,
        youtube: youtube,
      ),
      settingsStore: SharedPreferencesStreamSettingsStore(),
    );
    await Future.wait([
      controller.initialize(),
      recordingEngine.checkFfmpegAvailability(),
      youtube.initialize(),
      Future<void>.delayed(const Duration(milliseconds: 1200)),
    ]);
    if (!mounted) {
      controller.dispose();
      cameraSources.dispose();
      audioSources.dispose();
      recordingEngine.dispose();
      youtube.dispose();
      return;
    }
    setState(() {
      _controller = controller;
      _cameraSources = cameraSources;
      _audioSources = audioSources;
      _recordingEngine = recordingEngine;
      _youtube = youtube;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_controller != null) {
      return StreamDashboard(
        controller: _controller!,
        cameraSources: _cameraSources!,
        audioSources: _audioSources!,
        recordingEngine: _recordingEngine!,
        youtube: _youtube!,
      );
    }
    return const _LoadingSplash();
  }
}

class _LoadingSplash extends StatelessWidget {
  const _LoadingSplash();

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            'Lutherrose.svg',
            width: 240,
            height: 240,
            semanticsLabel: 'Luther rose',
          ),
          const SizedBox(height: 30),
          const SizedBox(
            width: 180,
            child: LinearProgressIndicator(
              minHeight: 5,
              color: kAccentTeal,
              backgroundColor: Color(0x16000000),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Preparing Church Streamer…',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final session = widget.controller.session;
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(
                  onQuit: _quit,
                  onSettings: _showSettings,
                  isQuitting: _isQuitting,
                  settingsEnabled: !session.isLive && !session.isBusy,
                ),
                const SizedBox(height: 10),
                _SupportContactBanner(session: session),
                const SizedBox(height: 18),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: constraints.maxWidth < 1050
                            ? 1050
                            : constraints.maxWidth,
                        height: constraints.maxHeight,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: 400,
                              child: _SettingsPanel(
                                controller: widget.controller,
                                titleController: _titleController,
                                startupTextController: _startupTextController,
                                shutdownTextController: _shutdownTextController,
                                youtube: widget.youtube,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _CameraPanel(
                                cameraSources: _cameraSources,
                                streamController: widget.controller,
                                permissionMessage: _permissionMessage,
                                requestingPermissions: _requestingPermissions,
                                onRequestPermissions: _initializeMediaAccess,
                              ),
                            ),
                            const SizedBox(width: 16),
                            SizedBox(
                              width: 310,
                              child: _AudioPanel(audioSources: _audioSources),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _GoLiveBar(
                  controller: widget.controller,
                  session: session,
                  recordingEngine: widget.recordingEngine,
                  youtube: widget.youtube,
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _SupportContactBanner extends StatelessWidget {
  const _SupportContactBanner({required this.session});

  final StreamSession session;

  @override
  Widget build(BuildContext context) {
    final name = session.supportContactName.isEmpty
        ? '<name>'
        : session.supportContactName;
    final phone = session.supportContactPhone.isEmpty
        ? '<phone number>'
        : session.supportContactPhone;
    return Semantics(
      label: 'Software support contact',
      child: Text(
        'If you have any problems with this software, contact $name at $phone',
        key: const Key('support-contact-message'),
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: Colors.black54),
      ),
    );
  }
}

enum _SettingsPage { root, streamQuality, devices, splashScreen }

class _ApplicationSettingsDialog extends StatefulWidget {
  const _ApplicationSettingsDialog({required this.controller});
  final StreamController controller;

  @override
  State<_ApplicationSettingsDialog> createState() =>
      _ApplicationSettingsDialogState();
}

class _ApplicationSettingsDialogState
    extends State<_ApplicationSettingsDialog> {
  _SettingsPage _page = _SettingsPage.root;

  void _showPage(_SettingsPage page) => setState(() => _page = page);

  @override
  Widget build(BuildContext context) => switch (_page) {
    _SettingsPage.root => _SettingsHomeDialog(
      session: widget.controller.session,
      onOpen: _showPage,
    ),
    _SettingsPage.streamQuality => _StreamQualityDialog(
      controller: widget.controller,
      onBack: () => _showPage(_SettingsPage.root),
    ),
    _SettingsPage.devices => _DeviceSettingsDialog(
      controller: widget.controller,
      onBack: () => _showPage(_SettingsPage.root),
    ),
    _SettingsPage.splashScreen => _SplashSettingsDialog(
      controller: widget.controller,
      onBack: () => _showPage(_SettingsPage.root),
    ),
  };
}

class _SettingsHomeDialog extends StatelessWidget {
  const _SettingsHomeDialog({required this.session, required this.onOpen});
  final StreamSession session;
  final ValueChanged<_SettingsPage> onOpen;

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.settings_outlined, size: 36),
    title: const Text('Application settings'),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const Key('stream-quality-settings'),
            leading: const Icon(Icons.high_quality_outlined),
            title: const Text('Stream quality'),
            subtitle: Text(
              '${session.outputResolution.label} · '
              '${session.videoBitrate.label}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onOpen(_SettingsPage.streamQuality),
          ),
          ListTile(
            key: const Key('device-settings'),
            leading: const Icon(Icons.videocam_outlined),
            title: const Text('Devices'),
            subtitle: Text(
              '${session.captureResolution.label} · ${session.frameRate.label}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onOpen(_SettingsPage.devices),
          ),
          ListTile(
            key: const Key('splash-settings'),
            leading: const Icon(Icons.slideshow_outlined),
            title: const Text('Preferences'),
            subtitle: Text(
              '${session.startupSplashEnabled ? 'Startup on' : 'Startup off'} · '
              '${session.shutdownSplashEnabled ? 'Shutdown on' : 'Shutdown off'}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onOpen(_SettingsPage.splashScreen),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}

class _StreamQualityDialog extends StatefulWidget {
  const _StreamQualityDialog({required this.controller, required this.onBack});
  final StreamController controller;
  final VoidCallback onBack;

  @override
  State<_StreamQualityDialog> createState() => _StreamQualityDialogState();
}

class _StreamQualityDialogState extends State<_StreamQualityDialog> {
  late StreamOutputResolution _resolution;
  late StreamVideoBitrate _bitrate;

  @override
  void initState() {
    super.initState();
    _resolution = widget.controller.session.outputResolution;
    _bitrate = widget.controller.session.videoBitrate;
  }

  void _save() {
    widget.controller.updateOutputResolution(_resolution);
    widget.controller.updateVideoBitrate(_bitrate);
    widget.onBack();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.high_quality_outlined, size: 36),
    title: const Text('Stream quality'),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<StreamOutputResolution>(
            key: const Key('output-resolution'),
            initialValue: _resolution,
            decoration: const InputDecoration(
              labelText: 'Output resolution',
              helperText: 'FFmpeg produces an exact 16:9 output size.',
            ),
            items: StreamOutputResolution.values
                .map(
                  (value) =>
                      DropdownMenuItem(value: value, child: Text(value.label)),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _resolution = value);
            },
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<StreamVideoBitrate>(
            key: const Key('video-bitrate'),
            initialValue: _bitrate,
            decoration: const InputDecoration(
              labelText: 'Video bitrate',
              helperText: 'Higher values need a faster, steadier connection.',
            ),
            items: StreamVideoBitrate.values
                .map(
                  (value) =>
                      DropdownMenuItem(value: value, child: Text(value.label)),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _bitrate = value);
            },
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: widget.onBack, child: const Text('Back')),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );
}

class _DeviceSettingsDialog extends StatefulWidget {
  const _DeviceSettingsDialog({required this.controller, required this.onBack});
  final StreamController controller;
  final VoidCallback onBack;

  @override
  State<_DeviceSettingsDialog> createState() => _DeviceSettingsDialogState();
}

class _DeviceSettingsDialogState extends State<_DeviceSettingsDialog> {
  late CameraCaptureResolution _captureResolution;
  late StreamFrameRate _frameRate;
  late VideoEncoderPreference _encoder;

  @override
  void initState() {
    super.initState();
    final session = widget.controller.session;
    _captureResolution = session.captureResolution;
    _frameRate = session.frameRate;
    _encoder = session.encoderPreference;
  }

  void _save() {
    widget.controller.updateCaptureResolution(_captureResolution);
    widget.controller.updateFrameRate(_frameRate);
    widget.controller.updateEncoderPreference(_encoder);
    widget.onBack();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.videocam_outlined, size: 36),
    title: const Text('Devices'),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<CameraCaptureResolution>(
            key: const Key('capture-resolution'),
            initialValue: _captureResolution,
            decoration: const InputDecoration(
              labelText: 'Camera capture resolution',
              helperText: 'Takes effect on the next camera scan or app launch.',
            ),
            items: CameraCaptureResolution.values
                .map(
                  (value) =>
                      DropdownMenuItem(value: value, child: Text(value.label)),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _captureResolution = value);
            },
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<StreamFrameRate>(
            key: const Key('frame-rate'),
            initialValue: _frameRate,
            decoration: const InputDecoration(
              labelText: 'Frame rate',
              helperText: '60 fps uses substantially more processing power.',
            ),
            items: StreamFrameRate.values
                .map(
                  (value) =>
                      DropdownMenuItem(value: value, child: Text(value.label)),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _frameRate = value);
            },
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<VideoEncoderPreference>(
            key: const Key('video-encoder'),
            initialValue: _encoder,
            decoration: const InputDecoration(
              labelText: 'Video encoder',
              helperText: 'Automatic chooses the best platform encoder.',
            ),
            items: VideoEncoderPreference.values
                .map(
                  (value) =>
                      DropdownMenuItem(value: value, child: Text(value.label)),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _encoder = value);
            },
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: widget.onBack, child: const Text('Back')),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );
}

class _SplashSettingsDialog extends StatefulWidget {
  const _SplashSettingsDialog({required this.controller, required this.onBack});
  final StreamController controller;
  final VoidCallback onBack;

  @override
  State<_SplashSettingsDialog> createState() => _SplashSettingsDialogState();
}

class _SplashSettingsDialogState extends State<_SplashSettingsDialog> {
  static const _durations = [3, 5, 10, 15];
  static const _imageTypes = XTypeGroup(
    label: 'Images',
    extensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp'],
  );

  late bool _startupEnabled;
  late bool _shutdownEnabled;
  late bool _startupShowTitle;
  late bool _shutdownShowTitle;
  late int _startupDuration;
  late int _shutdownDuration;
  late String _startupBackground;
  late String _shutdownBackground;
  late TextEditingController _youtubeDescriptionController;
  late TextEditingController _supportContactNameController;
  late TextEditingController _supportContactPhoneController;

  @override
  void initState() {
    super.initState();
    final session = widget.controller.session;
    _startupEnabled = session.startupSplashEnabled;
    _shutdownEnabled = session.shutdownSplashEnabled;
    _startupShowTitle = session.startupSplashShowTitle;
    _shutdownShowTitle = session.shutdownSplashShowTitle;
    _startupDuration = session.startupSplashDurationSeconds;
    _shutdownDuration = session.shutdownSplashDurationSeconds;
    _startupBackground = session.startupSplashBackgroundPath;
    _shutdownBackground = session.shutdownSplashBackgroundPath;
    _youtubeDescriptionController = TextEditingController(
      text: session.youtubeDescription,
    );
    _supportContactNameController = TextEditingController(
      text: session.supportContactName,
    );
    _supportContactPhoneController = TextEditingController(
      text: session.supportContactPhone,
    );
  }

  @override
  void dispose() {
    _youtubeDescriptionController.dispose();
    _supportContactNameController.dispose();
    _supportContactPhoneController.dispose();
    super.dispose();
  }

  Future<void> _chooseBackground({required bool startup}) async {
    final image = await openFile(acceptedTypeGroups: const [_imageTypes]);
    if (image == null || !mounted) return;
    setState(() {
      if (startup) {
        _startupBackground = image.path;
      } else {
        _shutdownBackground = image.path;
      }
    });
  }

  void _save() {
    widget.controller.updateSplashSettings(
      startupEnabled: _startupEnabled,
      shutdownEnabled: _shutdownEnabled,
      startupShowTitle: _startupShowTitle,
      shutdownShowTitle: _shutdownShowTitle,
      startupDurationSeconds: _startupDuration,
      shutdownDurationSeconds: _shutdownDuration,
      startupBackgroundPath: _startupBackground,
      shutdownBackgroundPath: _shutdownBackground,
      youtubeDescription: _youtubeDescriptionController.text,
      supportContactName: _supportContactNameController.text.trim(),
      supportContactPhone: _supportContactPhoneController.text.trim(),
    );
    widget.onBack();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.slideshow_outlined, size: 36),
    title: const Text('Preferences'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('support-contact-name'),
              controller: _supportContactNameController,
              decoration: const InputDecoration(
                labelText: 'Support contact name',
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              key: const Key('support-contact-phone'),
              controller: _supportContactPhoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Support contact phone number',
                helperText: 'Shown at the top of the main screen.',
              ),
            ),
            const Divider(height: 32),
            TextField(
              key: const Key('youtube-description'),
              controller: _youtubeDescriptionController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'YouTube stream description',
                helperText:
                    'Included in the description of each YouTube stream.',
                alignLabelWithHint: true,
              ),
            ),
            const Divider(height: 32),
            _SplashSection(
              title: 'Startup splash',
              enabled: _startupEnabled,
              showTitle: _startupShowTitle,
              duration: _startupDuration,
              backgroundPath: _startupBackground,
              durations: _durations,
              onEnabledChanged: (value) =>
                  setState(() => _startupEnabled = value),
              onShowTitleChanged: (value) =>
                  setState(() => _startupShowTitle = value),
              onDurationChanged: (value) =>
                  setState(() => _startupDuration = value),
              onChooseBackground: () => _chooseBackground(startup: true),
              onClearBackground: () => setState(() => _startupBackground = ''),
            ),
            const Divider(height: 32),
            _SplashSection(
              title: 'Shutdown splash',
              enabled: _shutdownEnabled,
              showTitle: _shutdownShowTitle,
              duration: _shutdownDuration,
              backgroundPath: _shutdownBackground,
              durations: _durations,
              onEnabledChanged: (value) =>
                  setState(() => _shutdownEnabled = value),
              onShowTitleChanged: (value) =>
                  setState(() => _shutdownShowTitle = value),
              onDurationChanged: (value) =>
                  setState(() => _shutdownDuration = value),
              onChooseBackground: () => _chooseBackground(startup: false),
              onClearBackground: () => setState(() => _shutdownBackground = ''),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: widget.onBack, child: const Text('Back')),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );
}

class _SplashSection extends StatelessWidget {
  const _SplashSection({
    required this.title,
    required this.enabled,
    required this.showTitle,
    required this.duration,
    required this.backgroundPath,
    required this.durations,
    required this.onEnabledChanged,
    required this.onShowTitleChanged,
    required this.onDurationChanged,
    required this.onChooseBackground,
    required this.onClearBackground,
  });

  final String title;
  final bool enabled;
  final bool showTitle;
  final int duration;
  final String backgroundPath;
  final List<int> durations;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<bool> onShowTitleChanged;
  final ValueChanged<int> onDurationChanged;
  final VoidCallback onChooseBackground;
  final VoidCallback onClearBackground;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Enable splash screen'),
        value: enabled,
        onChanged: onEnabledChanged,
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Show stream name'),
        value: showTitle,
        onChanged: enabled ? onShowTitleChanged : null,
      ),
      DropdownButtonFormField<int>(
        initialValue: duration,
        decoration: const InputDecoration(labelText: 'Duration'),
        items: durations
            .map(
              (seconds) => DropdownMenuItem(
                value: seconds,
                child: Text('$seconds seconds'),
              ),
            )
            .toList(),
        onChanged: enabled
            ? (value) {
                if (value != null) onDurationChanged(value);
              }
            : null,
      ),
      const SizedBox(height: 12),
      InputDecorator(
        decoration: const InputDecoration(labelText: 'Background image'),
        child: Row(
          children: [
            Expanded(
              child: _OverflowTooltipText(
                backgroundPath.isEmpty
                    ? 'Default dark background'
                    : File(backgroundPath).uri.pathSegments.last,
              ),
            ),
            TextButton(
              onPressed: enabled ? onChooseBackground : null,
              child: Text(backgroundPath.isEmpty ? 'Choose' : 'Replace'),
            ),
            if (backgroundPath.isNotEmpty)
              IconButton(
                tooltip: 'Remove background image',
                onPressed: enabled ? onClearBackground : null,
                icon: const Icon(Icons.close),
              ),
          ],
        ),
      ),
    ],
  );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.onQuit,
    required this.onSettings,
    required this.isQuitting,
    required this.settingsEnabled,
  });

  final Future<void> Function() onQuit;
  final Future<void> Function() onSettings;
  final bool isQuitting;
  final bool settingsEnabled;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SvgPicture.asset(
        'assets/church_app_icon.svg',
        width: 44,
        height: 44,
        semanticsLabel: 'Church Streamer',
      ),
      const SizedBox(width: 12),
      const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Church Streamer',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          Text(
            'Manage your church streams',
            style: TextStyle(color: Colors.black54),
          ),
        ],
      ),
      const Spacer(),
      Column(
        children: [
          Row(
            children: [
              IconButton(
                key: const Key('application-settings'),
                tooltip: settingsEnabled
                    ? 'Application settings'
                    : 'Settings are unavailable while streaming',
                onPressed: settingsEnabled && !isQuitting ? onSettings : null,
                icon: const Icon(Icons.settings_outlined),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: isQuitting ? null : onQuit,
                style: ButtonStyle(
                  foregroundColor: WidgetStateProperty.all(kAccentBlue),
                  backgroundColor: WidgetStateProperty.all(Colors.black54),
                ),
                child: isQuitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: kAccentBlue,
                        ),
                      )
                    : const Text('Quit'),
              ),
            ],
          ),
          SizedBox(height: 12.0),
          const _StatusPill(label: 'System ready', color: kAccentLime),
        ],
      ),
    ],
  );
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.controller,
    required this.titleController,
    required this.startupTextController,
    required this.shutdownTextController,
    required this.youtube,
  });
  final StreamController controller;
  final TextEditingController titleController;
  final TextEditingController startupTextController;
  final TextEditingController shutdownTextController;
  final YouTubeLiveService youtube;

  Future<void> _chooseRecordingDirectory() async {
    final path = await getDirectoryPath(
      confirmButtonText: 'Choose recording folder',
    );
    if (path != null) controller.updateRecordingDirectory(path);
  }

  @override
  Widget build(BuildContext context) {
    final session = controller.session;
    return _Panel(
      title: 'Service settings',
      icon: Icons.tune,
      child: ListView(
        children: [
          Tooltip(
            // Empty tooltips remove their wrapper, recreating the focused field.
            message: titleController.text.isEmpty
                ? 'Stream name'
                : titleController.text,
            child: TextField(
              key: const Key('service-title'),
              controller: titleController,
              enabled: !session.isLive && !session.isBusy,
              onChanged: controller.updateTitle,
              decoration: InputDecoration(
                labelText: 'Stream name',
                helperText: 'Editable; this exact name is used when streaming.',
                suffixIcon: IconButton(
                  tooltip: 'Refresh suggested name',
                  onPressed: session.isLive || session.isBusy
                      ? null
                      : controller.refreshSuggestedTitle,
                  icon: const Icon(Icons.refresh),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Tooltip(
            message: startupTextController.text.isEmpty
                ? 'Additional startup text'
                : startupTextController.text,
            child: TextField(
              key: const Key('startup-text'),
              controller: startupTextController,
              enabled:
                  session.startupSplashEnabled &&
                  !session.isLive &&
                  !session.isBusy,
              minLines: 2,
              maxLines: 3,
              onChanged: controller.updateStartupText,
              decoration: const InputDecoration(
                labelText: 'Additional startup text',
                hintText: 'Our service will begin shortly.',
                helperText: 'Shown on the startup splash screen.',
              ),
            ),
          ),
          const SizedBox(height: 16),
          Tooltip(
            message: shutdownTextController.text.isEmpty
                ? 'Additional shutdown text'
                : shutdownTextController.text,
            child: TextField(
              key: const Key('shutdown-text'),
              controller: shutdownTextController,
              enabled:
                  session.shutdownSplashEnabled &&
                  !session.isLive &&
                  !session.isBusy,
              minLines: 2,
              maxLines: 3,
              onChanged: controller.updateShutdownText,
              decoration: const InputDecoration(
                labelText: 'Additional shutdown text',
                hintText: 'Thank you for joining us.',
                helperText: 'Shown on the shutdown splash screen.',
              ),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<ServicePrivacy>(
            key: const Key('privacy'),
            initialValue: session.privacy,
            decoration: const InputDecoration(labelText: 'YouTube visibility'),
            items: ServicePrivacy.values
                .map(
                  (value) => DropdownMenuItem(
                    value: value,
                    child: Text(
                      '${value.name[0].toUpperCase()}${value.name.substring(1)}',
                    ),
                  ),
                )
                .toList(),
            onChanged: session.isLive || session.isBusy
                ? null
                : (value) {
                    if (value != null) controller.updatePrivacy(value);
                  },
          ),
          const SizedBox(height: 18),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Local recording'),
            subtitle: const Text('Save a full-quality archive'),
            value: session.recordLocally,
            onChanged: session.isLive || session.isBusy
                ? null
                : controller.updateRecording,
          ),
          const SizedBox(height: 8),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Saved file destination',
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _OverflowTooltipText(
                  session.recordingDirectory.isEmpty
                      ? 'Default Videos folder'
                      : session.recordingDirectory,
                  key: const Key('recording-directory'),
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('choose-recording-directory'),
                        onPressed:
                            session.recordLocally &&
                                !session.isLive &&
                                !session.isBusy
                            ? _chooseRecordingDirectory
                            : null,
                        icon: const Icon(Icons.folder_open_outlined),
                        label: const Text('Choose folder'),
                      ),
                    ),
                    if (session.recordingDirectory.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Use default Videos folder',
                        onPressed:
                            session.recordLocally &&
                                !session.isLive &&
                                !session.isBusy
                            ? () => controller.updateRecordingDirectory('')
                            : null,
                        icon: const Icon(Icons.restart_alt),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 32),
          const _SettingRow(
            icon: Icons.schedule,
            label: 'Schedule',
            value: 'Start now',
          ),
          const SizedBox(height: 14),
          ListenableBuilder(
            listenable: youtube,
            builder: (context, _) => _YouTubeDestination(youtube: youtube),
          ),
          if (session.error != null) ...[
            const SizedBox(height: 18),
            Text(
              session.error!,
              key: const Key('error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _YouTubeDestination extends StatelessWidget {
  const _YouTubeDestination({required this.youtube});
  final YouTubeLiveService youtube;

  @override
  Widget build(BuildContext context) {
    final busy = youtube.status == YouTubeConnectionStatus.authorizing;
    final (label, detail) = switch (youtube.status) {
      YouTubeConnectionStatus.checkingCredentials => (
        'YouTube',
        'Checking credentials…',
      ),
      YouTubeConnectionStatus.credentialsMissing => (
        'YouTube setup required',
        'Add client_secrets.json to the project folder.',
      ),
      YouTubeConnectionStatus.disconnected => ('YouTube', 'Ready to connect'),
      YouTubeConnectionStatus.reconnecting => (
        'YouTube',
        'Reconnecting last channel…',
      ),
      YouTubeConnectionStatus.authorizing => (
        'YouTube',
        'Complete sign-in in your browser…',
      ),
      YouTubeConnectionStatus.connected => (
        youtube.channelTitle ?? 'YouTube',
        'Connected',
      ),
      YouTubeConnectionStatus.creatingBroadcast => (
        youtube.channelTitle ?? 'YouTube',
        'Creating broadcast…',
      ),
      YouTubeConnectionStatus.creatingStream => (
        youtube.channelTitle ?? 'YouTube',
        'Creating ingest stream…',
      ),
      YouTubeConnectionStatus.bindingBroadcast => (
        youtube.channelTitle ?? 'YouTube',
        'Binding broadcast…',
      ),
      YouTubeConnectionStatus.broadcastReady => (
        youtube.channelTitle ?? 'YouTube',
        'Broadcast ready',
      ),
      YouTubeConnectionStatus.waitingForIngest => (
        youtube.channelTitle ?? 'YouTube',
        'Waiting for video',
      ),
      YouTubeConnectionStatus.ingestActive => (
        youtube.channelTitle ?? 'YouTube',
        'Video received',
      ),
      YouTubeConnectionStatus.transitioningLive => (
        youtube.channelTitle ?? 'YouTube',
        'Starting broadcast…',
      ),
      YouTubeConnectionStatus.live => (
        youtube.channelTitle ?? 'YouTube',
        'Live',
      ),
      YouTubeConnectionStatus.completing => (
        youtube.channelTitle ?? 'YouTube',
        'Ending broadcast…',
      ),
      YouTubeConnectionStatus.error => (
        'YouTube error',
        youtube.error ?? 'Could not connect.',
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingRow(icon: Icons.cloud_outlined, label: label, value: detail),
        if (youtube.hasCredentials && !youtube.isConnected) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const Key('connect-youtube'),
            onPressed: busy ? null : youtube.connect,
            icon: busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login),
            label: const Text('Connect YouTube'),
          ),
        ],
      ],
    );
  }
}

class _CameraPanel extends StatelessWidget {
  const _CameraPanel({
    required this.cameraSources,
    required this.streamController,
    required this.onRequestPermissions,
    this.permissionMessage,
    this.requestingPermissions = false,
  });
  final CameraSourcesController cameraSources;
  final StreamController streamController;
  final String? permissionMessage;
  final bool requestingPermissions;
  final VoidCallback onRequestPermissions;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([cameraSources, streamController]),
    builder: (context, _) => _Panel(
      title: 'Camera feeds',
      icon: Icons.videocam_outlined,
      trailing: OutlinedButton.icon(
        onPressed: cameraSources.isDiscovering ? null : cameraSources.discover,
        icon: cameraSources.isDiscovering
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh, size: 18),
        label: const Text('Rescan'),
      ),
      child: _cameraList(),
    ),
  );

  Widget _cameraList() {
    final session = streamController.session;
    if (session.status == StreamStatus.preparing) {
      return const _StreamOperationBlock(
        icon: Icons.play_circle_outline,
        label: 'Starting Stream',
      );
    }
    if (session.status == StreamStatus.stopping) {
      return const _StreamOperationBlock(
        icon: Icons.stop_circle_outlined,
        label: 'Stopping Stream',
      );
    }
    if (requestingPermissions) {
      return const Center(child: CircularProgressIndicator());
    }
    if (permissionMessage != null) {
      return _CameraPermissionMessage(
        detail: permissionMessage!,
        onTryAgain: onRequestPermissions,
      );
    }
    if (cameraSources.isDiscovering && cameraSources.sources.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text('Looking for cameras…'),
          ],
        ),
      );
    }
    if (cameraSources.discoveryError != null) {
      return _CameraMessage(
        icon: Icons.no_photography_outlined,
        title: 'Camera access failed',
        detail: cameraSources.discoveryError!,
      );
    }
    if (cameraSources.sources.isEmpty) {
      return const _CameraMessage(
        icon: Icons.videocam_off_outlined,
        title: 'No cameras found',
        detail: 'Connect a camera, then choose Rescan.',
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = cameraSources.sources.length;
        final cardHeight = count == 1
            ? constraints.maxHeight
            : ((constraints.maxHeight - 14) / 2).clamp(190.0, 340.0);
        return ListView.separated(
          itemCount: count,
          separatorBuilder: (_, _) => const SizedBox(height: 14),
          itemBuilder: (context, index) => SizedBox(
            height: cardHeight,
            child: _CameraFeed(
              source: cameraSources.sources[index],
              number: index + 1,
              isSelected:
                  streamController.session.cameraName ==
                  cameraSources.sources[index].description.name,
              isSwitching: streamController.isSwitchingCamera,
              onSelect: () => streamController.selectCamera(
                cameraSources.sources[index].description.name,
              ),
              onDelayChanged: (delay) =>
                  cameraSources.setDelay(cameraSources.sources[index], delay),
            ),
          ),
        );
      },
    );
  }
}

class _StreamOperationBlock extends StatelessWidget {
  const _StreamOperationBlock({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    key: Key(
      label == 'Starting Stream' ? 'starting-stream' : 'stopping-stream',
    ),
    decoration: BoxDecoration(
      color: Colors.black,
      borderRadius: BorderRadius.circular(14),
    ),
    padding: const EdgeInsets.all(48),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: Colors.white),
          const SizedBox(height: 20),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
          const CircularProgressIndicator(color: kAccentLime),
        ],
      ),
    ),
  );
}

class _CameraPermissionMessage extends StatelessWidget {
  const _CameraPermissionMessage({
    required this.detail,
    required this.onTryAgain,
  });
  final String detail;
  final VoidCallback onTryAgain;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline, size: 44, color: kAccentBlue),
          const SizedBox(height: 12),
          const Text(
            'Media access needed',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onTryAgain,
            icon: const Icon(Icons.perm_camera_mic_outlined),
            label: const Text('Check again'),
          ),
        ],
      ),
    ),
  );
}

class _CameraFeed extends StatelessWidget {
  const _CameraFeed({
    required this.source,
    required this.number,
    required this.isSelected,
    required this.isSwitching,
    required this.onSelect,
    required this.onDelayChanged,
  });
  final CameraSource source;
  final int number;
  final bool isSelected;
  final bool isSwitching;
  final VoidCallback onSelect;
  final ValueChanged<int> onDelayChanged;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      key: Key('camera-feed-$number'),
      onTap: source.isReady && !isSwitching ? onSelect : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? kAccentLime : Colors.transparent,
            width: 4,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (source.isReady)
              _CameraPreview(controller: source.controller!)
            else
              Center(
                child: source.error == null
                    ? const CircularProgressIndicator(color: kAccentBlue)
                    : Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          source.error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: kAccentBlue),
                        ),
                      ),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.center,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xb3000000)],
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Camera $number',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        _OverflowTooltipText(
                          source.description.name,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    _StatusPill(
                      label: isSwitching ? 'Switching…' : 'On air',
                      color: kAccentLime,
                    )
                  else
                    FilledButton.tonalIcon(
                      onPressed: source.isReady && !isSwitching
                          ? onSelect
                          : null,
                      icon: const Icon(Icons.switch_video, size: 18),
                      label: const Text('Select'),
                    ),
                ],
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: _DelayControl(
                delayMs: source.delayMs,
                onChanged: onDelayChanged,
                dark: true,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CameraPreview extends StatelessWidget {
  const _CameraPreview({required this.controller});
  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null || previewSize.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: kAccentBlue));
    }

    return Align(
      alignment: Alignment.topCenter,
      child: AspectRatio(
        aspectRatio: previewSize.width / previewSize.height,
        child: controller.buildPreview(),
      ),
    );
  }
}

class _CameraMessage extends StatelessWidget {
  const _CameraMessage({
    required this.icon,
    required this.title,
    required this.detail,
  });
  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 44, color: kAccentBlue),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 5),
        Text(
          detail,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black54),
        ),
      ],
    ),
  );
}

class _AudioPanel extends StatelessWidget {
  const _AudioPanel({required this.audioSources});
  final AudioSourcesController audioSources;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: audioSources,
    builder: (context, _) => _Panel(
      title: 'Audio inputs',
      icon: Icons.graphic_eq,
      trailing: IconButton(
        onPressed: audioSources.isDiscovering ? null : audioSources.discover,
        tooltip: 'Rescan audio inputs',
        icon: audioSources.isDiscovering
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh),
      ),
      child: _buildInputs(),
    ),
  );

  Widget _buildInputs() {
    if (audioSources.isDiscovering && audioSources.sources.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (audioSources.discoveryError != null) {
      return _CameraMessage(
        icon: Icons.mic_off_outlined,
        title: 'Audio access failed',
        detail: audioSources.discoveryError!,
      );
    }
    if (audioSources.sources.isEmpty) {
      return const _CameraMessage(
        icon: Icons.mic_off_outlined,
        title: 'No audio inputs found',
        detail: 'Connect an input, then choose Rescan.',
      );
    }
    return ListView.separated(
      itemCount: audioSources.sources.length,
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (context, index) => _AudioInput(
        source: audioSources.sources[index],
        number: index + 1,
        onEnabledChanged: (enabled) =>
            audioSources.setEnabled(audioSources.sources[index], enabled),
        onGainChanged: (gain) =>
            audioSources.setGain(audioSources.sources[index], gain),
        onDelayChanged: (delay) =>
            audioSources.setDelay(audioSources.sources[index], delay),
      ),
    );
  }
}

class _AudioInput extends StatelessWidget {
  const _AudioInput({
    required this.source,
    required this.number,
    required this.onEnabledChanged,
    required this.onGainChanged,
    required this.onDelayChanged,
  });
  final AudioSource source;
  final int number;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<double> onGainChanged;
  final ValueChanged<int> onDelayChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: kAccentBlue, width: 1.5),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: kAccentTeal,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.mic_none, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Input $number',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  _OverflowTooltipText(
                    source.device.label,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
            Switch(value: source.enabled, onChanged: onEnabledChanged),
          ],
        ),
        const SizedBox(height: 16),
        _LevelMeter(level: source.enabled ? source.level : 0),
        if (source.error != null) ...[
          const SizedBox(height: 8),
          _OverflowTooltipText(
            source.error!,
            maxLines: 2,
            style: const TextStyle(fontSize: 11, color: Colors.black),
          ),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            Icon(
              source.enabled
                  ? Icons.volume_up_outlined
                  : Icons.volume_off_outlined,
              size: 19,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Slider(
                value: source.gain,
                min: 0,
                max: 2,
                divisions: 40,
                label: '${(source.gain * 100).round()}%',
                onChanged: source.enabled ? onGainChanged : null,
              ),
            ),
            SizedBox(
              width: 42,
              child: Text(
                '${(source.gain * 100).round()}%',
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _DelayControl(delayMs: source.delayMs, onChanged: onDelayChanged),
      ],
    ),
  );
}

class _DelayControl extends StatelessWidget {
  const _DelayControl({
    required this.delayMs,
    required this.onChanged,
    this.dark = false,
  });
  final int delayMs;
  final ValueChanged<int> onChanged;
  final bool dark;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: dark ? Colors.black87 : const Color(0x0F000000),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      mainAxisSize: dark ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Icon(Icons.sync, size: 16, color: dark ? Colors.white : null),
        const SizedBox(width: 6),
        Text('Delay', style: TextStyle(color: dark ? Colors.white : null)),
        const SizedBox(width: 8),
        if (dark)
          SizedBox(
            width: 115,
            child: Slider(
              value: delayMs.toDouble(),
              min: 0,
              max: 1000,
              divisions: 20,
              label: '$delayMs ms',
              onChanged: (value) => onChanged(value.round()),
            ),
          )
        else
          Expanded(
            child: Slider(
              value: delayMs.toDouble(),
              min: 0,
              max: 1000,
              divisions: 20,
              label: '$delayMs ms',
              onChanged: (value) => onChanged(value.round()),
            ),
          ),
        SizedBox(
          width: 50,
          child: Text(
            '$delayMs ms',
            textAlign: TextAlign.end,
            style: TextStyle(fontSize: 11, color: dark ? Colors.white : null),
          ),
        ),
      ],
    ),
  );
}

class _LevelMeter extends StatelessWidget {
  const _LevelMeter({required this.level});
  final double level;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(4),
    child: LinearProgressIndicator(
      value: level,
      minHeight: 8,
      backgroundColor: const Color(0x16000000),
      color: level > .82 ? kAccentLime : kAccentTeal,
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 21),
              const SizedBox(width: 9),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              ?trailing,
            ],
          ),
          const SizedBox(height: 18),
          Expanded(child: child),
        ],
      ),
    ),
  );
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Icon(icon, size: 20, color: kAccentBlue),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _OverflowTooltipText(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            _OverflowTooltipText(
              value,
              maxLines: 2,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    ],
  );
}

/// Keeps compact desktop layouts tidy while exposing the complete value on
/// hover (or a long press on touch devices).
class _OverflowTooltipText extends StatelessWidget {
  const _OverflowTooltipText(
    this.text, {
    super.key,
    this.style,
    this.maxLines = 1,
  });

  final String text;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: text,
    child: Text(
      text,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: style,
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      children: [
        const Icon(Icons.circle, size: 9, color: Colors.black),
        const SizedBox(width: 7),
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
      ],
    ),
  );
}

class _GoLiveBar extends StatelessWidget {
  const _GoLiveBar({
    required this.controller,
    required this.session,
    required this.recordingEngine,
    required this.youtube,
  });
  final StreamController controller;
  final StreamSession session;
  final FfmpegStreamEngine recordingEngine;
  final YouTubeLiveService youtube;

  @override
  Widget build(BuildContext context) {
    final label = switch (session.status) {
      StreamStatus.preparing => 'Preparing…',
      StreamStatus.stopping => 'Stopping…',
      StreamStatus.live => 'End stream',
      _ => 'Go live',
    };
    return ListenableBuilder(
      listenable: youtube,
      builder: (context, _) => Row(
        children: [
          Expanded(
            child: ListenableBuilder(
              listenable: recordingEngine,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _OverflowTooltipText(
                    session.title.isEmpty ? 'Untitled service' : session.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (recordingEngine.trace.isNotEmpty)
                    _OverflowTooltipText(
                      _traceLabel(recordingEngine.trace.last),
                      key: const Key('recording-lifecycle'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  _OverflowTooltipText(
                    youtube.statusMessage,
                    key: const Key('youtube-lifecycle'),
                    style: TextStyle(
                      fontSize: 12,
                      color: youtube.status == YouTubeConnectionStatus.error
                          ? Colors.red
                          : Colors.black54,
                    ),
                  ),
                  if (recordingEngine.ffmpegAvailability ==
                      FfmpegAvailability.unavailable)
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          'FFmpeg is required before you can go live.',
                          key: Key('ffmpeg-missing'),
                          style: TextStyle(fontSize: 12, color: Colors.red),
                        ),
                        TextButton(
                          key: const Key('ffmpeg-download'),
                          onPressed: () => launchUrl(
                            Uri.parse('https://ffmpeg.org/download.html'),
                          ),
                          child: const Text('Get FFmpeg'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 20),
          _StreamRuntime(startedAt: session.startedAt),
          const SizedBox(width: 20),
          SizedBox(
            width: 240,
            child: FilledButton.icon(
              key: const Key('go-live'),
              onPressed:
                  session.isBusy ||
                      (!session.isLive &&
                          (recordingEngine.ffmpegAvailability !=
                                  FfmpegAvailability.available ||
                              !youtube.isConnected))
                  ? null
                  : controller.toggleLive,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: session.isLive ? kAccentBlue : kAccentGreen,
                textStyle: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              icon: session.isBusy
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : Icon(
                      session.isLive
                          ? Icons.stop_rounded
                          : Icons.podcasts_rounded,
                    ),
              label: Text(label),
            ),
          ),
        ],
      ),
    );
  }

  String _traceLabel(RecordingLifecycleEvent event) => switch (event.stage) {
    RecordingLifecycleStage.starting => 'Opening ${event.detail}…',
    RecordingLifecycleStage.recording => 'Recording ${event.detail}',
    RecordingLifecycleStage.switchingCamera => 'Switching to ${event.detail}…',
    RecordingLifecycleStage.stopping => 'Finishing recording…',
    RecordingLifecycleStage.finalizing => 'Finalizing stream and recording…',
    RecordingLifecycleStage.recordingSaved => 'Saved ${event.detail}',
    RecordingLifecycleStage.stopped => event.detail,
  };
}

class _StreamRuntime extends StatefulWidget {
  const _StreamRuntime({required this.startedAt});
  final DateTime? startedAt;

  @override
  State<_StreamRuntime> createState() => _StreamRuntimeState();
}

class _StreamRuntimeState extends State<_StreamRuntime> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(_StreamRuntime oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startedAt != widget.startedAt) _syncTimer();
  }

  void _syncTimer() {
    _timer?.cancel();
    _timer = widget.startedAt == null
        ? null
        : Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) setState(() {});
          });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final startedAt = widget.startedAt;
    final elapsed = startedAt == null
        ? null
        : DateTime.now().difference(startedAt);
    return Container(
      key: const Key('stream-runtime'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x0f000000),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.timer_outlined,
            size: 20,
            color: startedAt == null ? Colors.black45 : Colors.black,
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Stream runtime',
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
              Text(
                elapsed == null ? '--:--:--' : _formatDuration(elapsed),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.isNegative ? 0 : duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = totalSeconds.remainder(3600) ~/ 60;
    final seconds = totalSeconds.remainder(60);
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}
