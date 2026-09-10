part of '../app.dart';

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
