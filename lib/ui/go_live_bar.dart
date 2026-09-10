part of '../app.dart';

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
