part of '../app.dart';

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
