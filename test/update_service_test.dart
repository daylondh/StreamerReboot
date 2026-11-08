import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:streamer_reboot/services/update_service.dart';

void main() {
  late Directory stateDirectory;

  setUp(() async {
    stateDirectory = await Directory.systemTemp.createTemp(
      'church-update-test-',
    );
  });

  tearDown(() async {
    if (await stateDirectory.exists()) {
      await stateDirectory.delete(recursive: true);
    }
  });

  test('reports the installed version as current', () async {
    final service = AppUpdateService(
      currentVersion: '0.5.0',
      stateDirectory: stateDirectory,
      isWindows: true,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'tag_name': 'v0.5.0', 'assets': <Object>[]}),
          200,
        ),
      ),
    );
    addTearDown(service.dispose);

    await service.initialize();

    expect(service.status, UpdateStatus.current);
    expect(service.updateReady, isFalse);
  });

  test('downloads and verifies a newer Windows release', () async {
    final archiveBytes = utf8.encode('test release archive');
    final digest = sha256.convert(archiveBytes);
    final service = AppUpdateService(
      currentVersion: '0.5.0',
      stateDirectory: stateDirectory,
      isWindows: true,
      client: MockClient((request) async {
        if (request.url.toString() == AppUpdateService.latestReleaseUri) {
          return http.Response(
            jsonEncode({
              'tag_name': 'v0.5.1',
              'assets': [
                {
                  'name': AppUpdateService.windowsAssetName,
                  'digest': 'sha256:$digest',
                  'browser_download_url': 'https://example.test/update.zip',
                },
              ],
            }),
            200,
          );
        }
        return http.Response.bytes(archiveBytes, 200);
      }),
    );
    addTearDown(service.dispose);

    await service.initialize();

    expect(service.status, UpdateStatus.ready);
    expect(service.availableVersion, '0.5.1');
    expect(service.updateReady, isTrue);
    expect(
      File(
        '${stateDirectory.path}${Platform.pathSeparator}${AppUpdateService.windowsAssetName}',
      ).readAsBytes(),
      completion(archiveBytes),
    );
  });

  test('rejects a download that does not match the release digest', () async {
    final service = AppUpdateService(
      currentVersion: '0.5.0',
      stateDirectory: stateDirectory,
      isWindows: true,
      client: MockClient((request) async {
        if (request.url.toString() == AppUpdateService.latestReleaseUri) {
          return http.Response(
            jsonEncode({
              'tag_name': 'v0.6.0',
              'assets': [
                {
                  'name': AppUpdateService.windowsAssetName,
                  'digest': 'sha256:${'0' * 64}',
                  'browser_download_url': 'https://example.test/update.zip',
                },
              ],
            }),
            200,
          );
        }
        return http.Response.bytes(utf8.encode('tampered'), 200);
      }),
    );
    addTearDown(service.dispose);

    await service.initialize();

    expect(service.status, UpdateStatus.error);
    expect(service.updateReady, isFalse);
    expect(service.message, contains('failed verification'));
  });
}
