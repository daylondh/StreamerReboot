part of '../app.dart';

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
