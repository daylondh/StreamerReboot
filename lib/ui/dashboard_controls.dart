part of '../app.dart';

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
    required this.updateService,
  });
  final StreamController controller;
  final TextEditingController titleController;
  final TextEditingController startupTextController;
  final TextEditingController shutdownTextController;
  final YouTubeLiveService youtube;
  final AppUpdateService? updateService;

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
              maxLines: 2,
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
          if (updateService != null) ...[
            const Divider(height: 32),
            _UpdateStatusCard(updateService: updateService!),
          ],
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

class _UpdateStatusCard extends StatelessWidget {
  const _UpdateStatusCard({required this.updateService});

  final AppUpdateService updateService;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: updateService,
    builder: (context, _) {
      final status = updateService.status;
      final busy =
          status == UpdateStatus.checking || status == UpdateStatus.downloading;
      final icon = switch (status) {
        UpdateStatus.ready => Icons.system_update_alt,
        UpdateStatus.error => Icons.cloud_off_outlined,
        UpdateStatus.current => Icons.check_circle_outline,
        _ => Icons.cloud_download_outlined,
      };
      final message =
          updateService.message ??
          switch (status) {
            UpdateStatus.checking => 'Checking for updates…',
            UpdateStatus.unsupported =>
              'Automatic updates are available on Windows.',
            _ => 'Church Streamer ${updateService.currentVersion}',
          };
      return Semantics(
        key: const Key('update-status'),
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (busy)
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(icon, size: 22, color: kAccentTeal),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'App updates · ${updateService.currentVersion}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(message, style: const TextStyle(color: Colors.black54)),
                  if (status == UpdateStatus.downloading &&
                      updateService.downloadProgress != null) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: updateService.downloadProgress,
                    ),
                  ],
                  if (status == UpdateStatus.error) ...[
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: updateService.checkForUpdates,
                      child: const Text('Try again'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
