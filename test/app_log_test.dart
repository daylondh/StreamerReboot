import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamer_reboot/services/app_log.dart';

void main() {
  test('diagnostic messages include a UTC timestamp', () {
    final originalDebugPrint = debugPrint;
    String? output;
    debugPrint = (message, {wrapWidth}) => output = message;
    addTearDown(() => debugPrint = originalDebugPrint);

    logMessage('[Test] message');

    expect(
      output,
      matches(
        RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+Z \[Test\] message$'),
      ),
    );
  });
}
