part of '../app.dart';

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
