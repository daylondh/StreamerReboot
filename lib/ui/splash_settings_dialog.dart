part of '../app.dart';

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
