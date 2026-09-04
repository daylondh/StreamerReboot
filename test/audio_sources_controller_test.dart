import 'package:flutter_test/flutter_test.dart';
import 'package:streamer_reboot/controllers/audio_sources_controller.dart';

void main() {
  test('converts dBFS into a linear meter level', () {
    expect(AudioSourcesController.meterLevel(0, 1), 1);
    expect(AudioSourcesController.meterLevel(-20, 1), closeTo(.1, .0001));
  });

  test('gain affects and clamps the displayed level', () {
    expect(AudioSourcesController.meterLevel(-20, 2), closeTo(.2, .0001));
    expect(AudioSourcesController.meterLevel(0, 2), 1);
    expect(AudioSourcesController.meterLevel(-20, 0), 0);
  });
}
