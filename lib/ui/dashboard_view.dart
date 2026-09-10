part of '../app.dart';

class _DashboardView extends StatelessWidget {
  const _DashboardView({
    required this.controller,
    required this.titleController,
    required this.startupTextController,
    required this.shutdownTextController,
    required this.cameraSources,
    required this.audioSources,
    required this.recordingEngine,
    required this.youtube,
    required this.permissionMessage,
    required this.requestingPermissions,
    required this.isQuitting,
    required this.onQuit,
    required this.onSettings,
    required this.onRequestPermissions,
  });

  final StreamController controller;
  final TextEditingController titleController;
  final TextEditingController startupTextController;
  final TextEditingController shutdownTextController;
  final CameraSourcesController cameraSources;
  final AudioSourcesController audioSources;
  final FfmpegStreamEngine recordingEngine;
  final YouTubeLiveService youtube;
  final String? permissionMessage;
  final bool requestingPermissions;
  final bool isQuitting;
  final Future<void> Function() onQuit;
  final Future<void> Function() onSettings;
  final Future<void> Function() onRequestPermissions;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final session = controller.session;
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(
                  onQuit: onQuit,
                  onSettings: onSettings,
                  isQuitting: isQuitting,
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
                                controller: controller,
                                titleController: titleController,
                                startupTextController: startupTextController,
                                shutdownTextController: shutdownTextController,
                                youtube: youtube,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _CameraPanel(
                                cameraSources: cameraSources,
                                streamController: controller,
                                permissionMessage: permissionMessage,
                                requestingPermissions: requestingPermissions,
                                onRequestPermissions: onRequestPermissions,
                              ),
                            ),
                            const SizedBox(width: 16),
                            SizedBox(
                              width: 310,
                              child: _AudioPanel(audioSources: audioSources),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _GoLiveBar(
                  controller: controller,
                  session: session,
                  recordingEngine: recordingEngine,
                  youtube: youtube,
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
