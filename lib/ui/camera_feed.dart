part of '../app.dart';

class _CameraFeed extends StatelessWidget {
  const _CameraFeed({
    required this.source,
    required this.number,
    required this.isSelected,
    required this.isSwitching,
    required this.onSelect,
    required this.onDelayChanged,
  });
  final CameraSource source;
  final int number;
  final bool isSelected;
  final bool isSwitching;
  final VoidCallback onSelect;
  final ValueChanged<int> onDelayChanged;

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
                  colors: [Colors.transparent, Color(0xb3000000)],
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
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        _OverflowTooltipText(
                          source.description.name,
                          style: const TextStyle(
                            color: Colors.white70,
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
            Positioned(
              top: 10,
              right: 10,
              child: _DelayControl(
                delayMs: source.delayMs,
                onChanged: onDelayChanged,
                dark: true,
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

    return Align(
      alignment: Alignment.topCenter,
      child: AspectRatio(
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
