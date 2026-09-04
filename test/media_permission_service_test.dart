import 'package:flutter_test/flutter_test.dart';
import 'package:streamer_reboot/services/media_permission_service.dart';

void main() {
  test('recognizes previously granted access', () {
    const result = MediaPermissionResult(
      camera: MediaAuthorization.granted,
      microphone: MediaAuthorization.granted,
    );
    expect(result.allGranted, isTrue);
    expect(result.needsRequest, isFalse);
    expect(result.hasDenied, isFalse);
  });

  test('distinguishes first-run and denied states', () {
    const firstRun = MediaPermissionResult(
      camera: MediaAuthorization.notDetermined,
      microphone: MediaAuthorization.granted,
    );
    expect(firstRun.needsRequest, isTrue);

    const denied = MediaPermissionResult(
      camera: MediaAuthorization.denied,
      microphone: MediaAuthorization.granted,
    );
    expect(denied.hasDenied, isTrue);
    expect(denied.needsRequest, isFalse);
  });
}
