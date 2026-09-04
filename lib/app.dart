import 'dart:async';

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
import 'services/stream_engine.dart';
import 'services/stream_settings_store.dart';
import 'services/youtube_live_service.dart';

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
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
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
  LocalRecordingStreamEngine? _recordingEngine;
  YouTubeLiveService? _youtube;

  @override
  void initState() {
    super.initState();
    _prepareApp();
  }

  Future<void> _prepareApp() async {
    final cameraSources = CameraSourcesController();
    final recordingEngine = LocalRecordingStreamEngine(
      recorderForCamera: (cameraName) {
        for (final source in cameraSources.sources) {
          if (source.description.name == cameraName && source.isReady) {
            return CameraVideoRecorder(source.controller!);
          }
        }
        return null;
      },
    );
    final youtube = YouTubeLiveService();
    final controller = StreamController(
      recordingEngine,
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
      recordingEngine.dispose();
      youtube.dispose();
      return;
    }
    setState(() {
      _controller = controller;
      _cameraSources = cameraSources;
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
    required this.recordingEngine,
    required this.youtube,
    super.key,
  });
  final StreamController controller;
  final CameraSourcesController cameraSources;
  final LocalRecordingStreamEngine recordingEngine;
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
    _audioSources = AudioSourcesController();
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
                const _Header(),
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
                              width: 285,
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
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _Header extends StatelessWidget {
  const _Header();

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
      _StatusPill(label: 'System ready', color: kAccentLime),
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
          TextField(
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
          const SizedBox(height: 16),
          SwitchListTile(
            key: const Key('startup-splash-enabled'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Startup splash'),
            subtitle: const Text('Show before the camera feed'),
            value: session.startupSplashEnabled,
            onChanged: session.isLive || session.isBusy
                ? null
                : controller.updateStartupSplashEnabled,
          ),
          TextField(
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
              helperText: 'Shown below the stream name on startup.',
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            key: const Key('shutdown-splash-enabled'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Shutdown splash'),
            subtitle: const Text('Show before ending the stream'),
            value: session.shutdownSplashEnabled,
            onChanged: session.isLive || session.isBusy
                ? null
                : controller.updateShutdownSplashEnabled,
          ),
          TextField(
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
              helperText: 'Shown alone when the stream ends.',
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
                Text(
                  session.recordingDirectory.isEmpty
                      ? 'Default Videos folder'
                      : session.recordingDirectory,
                  key: const Key('recording-directory'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
      YouTubeConnectionStatus.authorizing => (
        'YouTube',
        'Complete sign-in in your browser…',
      ),
      YouTubeConnectionStatus.connected => (
        youtube.channelTitle ?? 'YouTube',
        'Connected',
      ),
      YouTubeConnectionStatus.preparingBroadcast => (
        youtube.channelTitle ?? 'YouTube',
        'Creating broadcast…',
      ),
      YouTubeConnectionStatus.broadcastReady => (
        youtube.channelTitle ?? 'YouTube',
        'Broadcast ready',
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
    if (session.status == StreamStatus.preparing &&
        session.startupSplashEnabled) {
      return _StreamSlate(
        title: session.title,
        additionalText: session.startupText,
      );
    }
    if (session.status == StreamStatus.stopping &&
        session.shutdownSplashEnabled) {
      return _StreamSlate(additionalText: session.shutdownText);
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
            ),
          ),
        );
      },
    );
  }
}

class _StreamSlate extends StatelessWidget {
  const _StreamSlate({this.title, required this.additionalText});

  final String? title;
  final String additionalText;

  @override
  Widget build(BuildContext context) => Container(
    key: Key(title == null ? 'shutdown-slate' : 'startup-slate'),
    decoration: BoxDecoration(
      color: Colors.black,
      borderRadius: BorderRadius.circular(14),
    ),
    padding: const EdgeInsets.all(48),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset('assets/church_app_icon.svg', width: 72, height: 72),
          if (title != null) ...[
            const SizedBox(height: 24),
            Text(
              title!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (additionalText.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              additionalText.trim(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 18),
            ),
          ],
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
  });
  final CameraSource source;
  final int number;
  final bool isSelected;
  final bool isSwitching;
  final VoidCallback onSelect;

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
                  colors: [Colors.transparent, kAccentTeal],
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
                            color: Colors.black,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          source.description.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.black87,
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

    return Center(
      child: AspectRatio(
        // The camera backend reports the negotiated frame dimensions after
        // initialization. AspectRatio scales that frame down to fit the card
        // without stretching or cropping it.
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
  });
  final AudioSource source;
  final int number;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<double> onGainChanged;

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
                  Text(
                    source.device.label,
                    overflow: TextOverflow.ellipsis,
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
          Text(
            source.error!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
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
    children: [
      Icon(icon, size: 20, color: kAccentBlue),
      const SizedBox(width: 10),
      Expanded(child: Text(label)),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
    ],
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
  });
  final StreamController controller;
  final StreamSession session;
  final LocalRecordingStreamEngine recordingEngine;

  @override
  Widget build(BuildContext context) {
    final label = switch (session.status) {
      StreamStatus.preparing => 'Preparing…',
      StreamStatus.stopping => 'Stopping…',
      StreamStatus.live => 'End stream',
      _ => 'Go live',
    };
    return Row(
      children: [
        Expanded(
          child: ListenableBuilder(
            listenable: recordingEngine,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.title.isEmpty ? 'Untitled service' : session.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (recordingEngine.trace.isNotEmpty)
                  Text(
                    _traceLabel(recordingEngine.trace.last),
                    key: const Key('recording-lifecycle'),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
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
        SizedBox(
          width: 240,
          child: FilledButton.icon(
            key: const Key('go-live'),
            onPressed:
                session.isBusy ||
                    (!session.isLive &&
                        recordingEngine.ffmpegAvailability !=
                            FfmpegAvailability.available)
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
    );
  }

  String _traceLabel(RecordingLifecycleEvent event) => switch (event.stage) {
    RecordingLifecycleStage.starting => 'Opening ${event.detail}…',
    RecordingLifecycleStage.recording => 'Recording ${event.detail}',
    RecordingLifecycleStage.switchingCamera => 'Switching to ${event.detail}…',
    RecordingLifecycleStage.stopping => 'Finishing recording…',
    RecordingLifecycleStage.finalizing => 'Combining camera changes…',
    RecordingLifecycleStage.recordingSaved => 'Saved ${event.detail}',
    RecordingLifecycleStage.stopped => event.detail,
  };
}
