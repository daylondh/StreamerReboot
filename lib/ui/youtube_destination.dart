part of '../app.dart';

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
