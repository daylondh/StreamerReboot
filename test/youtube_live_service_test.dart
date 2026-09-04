import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/youtube/v3.dart';
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:streamer_reboot/domain/stream_session.dart';
import 'package:streamer_reboot/services/youtube_live_service.dart';

class MemoryCredentialStore implements YouTubeCredentialStore {
  MemoryCredentialStore([this.value]);
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;

  @override
  Future<void> delete() async => value = null;
}

class FailingCredentialStore implements YouTubeCredentialStore {
  @override
  Future<String?> read() => throw StateError('keyring unavailable');

  @override
  Future<void> write(String value) => throw StateError('keyring unavailable');

  @override
  Future<void> delete() => throw StateError('keyring unavailable');
}

void main() {
  test('recognizes a configured desktop OAuth credentials file', () async {
    final directory = await Directory.systemTemp.createTemp('youtube-oauth-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/client_secrets.json');
    await file.writeAsString(
      jsonEncode({
        'installed': {
          'client_id': 'test.apps.googleusercontent.com',
          'client_secret': 'not-a-real-secret',
        },
      }),
    );
    final service = YouTubeLiveService(
      credentialsFile: file,
      credentialStore: MemoryCredentialStore(),
    );

    await service.initialize();

    expect(service.hasCredentials, isTrue);
    expect(service.status, YouTubeConnectionStatus.disconnected);
  });

  test('reconnects the last YouTube channel during initialization', () async {
    final directory = await Directory.systemTemp.createTemp('youtube-oauth-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/client_secrets.json');
    await file.writeAsString(
      jsonEncode({
        'installed': {
          'client_id': 'test.apps.googleusercontent.com',
          'client_secret': 'not-a-real-secret',
        },
      }),
    );
    final savedCredentials = AccessCredentials(
      AccessToken(
        'Bearer',
        'access-token',
        DateTime.now().toUtc().add(const Duration(hours: 1)),
      ),
      'refresh-token',
      [YouTubeApi.youtubeForceSslScope],
    );
    final store = MemoryCredentialStore(jsonEncode(savedCredentials.toJson()));
    final statuses = <YouTubeConnectionStatus>[];
    final service = YouTubeLiveService(
      credentialsFile: file,
      credentialStore: store,
      httpClientFactory: () => MockClient(
        (_) async =>
            _jsonResponse('{"items":[{"snippet":{"title":"Grace Church"}}]}'),
      ),
    );
    service.addListener(() => statuses.add(service.status));

    await service.initialize();

    expect(service.isConnected, isTrue);
    expect(service.channelTitle, 'Grace Church');
    expect(statuses, contains(YouTubeConnectionStatus.reconnecting));
    expect(statuses.last, YouTubeConnectionStatus.connected);
  });

  test('reports unavailable secure credential storage', () async {
    final directory = await Directory.systemTemp.createTemp('youtube-oauth-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/client_secrets.json');
    await file.writeAsString('{"installed":{"client_id":"test"}}');
    final service = YouTubeLiveService(
      credentialsFile: file,
      credentialStore: FailingCredentialStore(),
    );

    await service.initialize();

    expect(service.status, YouTubeConnectionStatus.error);
    expect(service.error, contains('credential storage'));
  });

  test('creates and binds a broadcast and RTMP stream', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/liveBroadcasts/transition')) {
        return _jsonResponse(
          jsonEncode({
            'id': 'broadcast-1',
            'status': {
              'lifeCycleStatus': request.url.queryParameters['broadcastStatus'],
            },
          }),
        );
      }
      if (request.url.path.endsWith('/liveBroadcasts/bind')) {
        return _jsonResponse('{"id":"broadcast-1"}');
      }
      if (request.url.path.endsWith('/liveBroadcasts')) {
        return _jsonResponse('{"id":"broadcast-1"}');
      }
      if (request.method == 'GET' &&
          request.url.path.endsWith('/liveStreams')) {
        return _jsonResponse(
          '{"items":[{"id":"stream-1","status":{"streamStatus":"active",'
          '"healthStatus":{"status":"good"}}}]}',
        );
      }
      if (request.url.path.endsWith('/liveStreams')) {
        return _jsonResponse(
          jsonEncode({
            'id': 'stream-1',
            'cdn': {
              'ingestionInfo': {
                'rtmpsIngestionAddress': 'rtmps://a.rtmps.youtube.com/live2',
                'ingestionAddress': 'rtmp://a.rtmp.youtube.com/live2',
                'streamName': 'secret-key',
              },
            },
          }),
        );
      }
      return http.Response('not found', 404);
    });
    final service = YouTubeLiveService(api: YouTubeApi(client));
    final statuses = <YouTubeConnectionStatus>[];
    service.addListener(() => statuses.add(service.status));

    final target = await service.prepareBroadcast(
      const StreamSession(
        title: 'Sunday Worship',
        privacy: ServicePrivacy.unlisted,
      ),
    );

    expect(target.broadcastId, 'broadcast-1');
    expect(target.streamId, 'stream-1');
    expect(
      target.ingestionUrl,
      'rtmps://a.rtmps.youtube.com:443/live2/secret-key',
    );
    expect(
      target.fallbackIngestionUrl,
      'rtmp://a.rtmp.youtube.com/live2/secret-key',
    );
    expect(service.useFallbackIngestion(), isTrue);
    expect(
      service.target?.ingestionUrl,
      'rtmp://a.rtmp.youtube.com/live2/secret-key',
    );
    expect(requests, hasLength(3));
    final broadcastBody = jsonDecode(requests.first.body);
    expect(broadcastBody['snippet']['title'], 'Sunday Worship');
    expect(broadcastBody['status']['privacyStatus'], 'unlisted');
    expect(requests.last.url.queryParameters['streamId'], 'stream-1');
    expect(statuses, [
      YouTubeConnectionStatus.creatingBroadcast,
      YouTubeConnectionStatus.creatingStream,
      YouTubeConnectionStatus.bindingBroadcast,
      YouTubeConnectionStatus.broadcastReady,
    ]);

    await service.startBroadcast();
    expect(service.status, YouTubeConnectionStatus.live);
    expect(
      requests.where(
        (request) =>
            request.url.path.endsWith('/liveBroadcasts/transition') &&
            request.url.queryParameters['broadcastStatus'] == 'live',
      ),
      hasLength(1),
    );

    await service.finishBroadcast();
    expect(requests.where((request) => request.method == 'DELETE'), isEmpty);
    expect(service.status, YouTubeConnectionStatus.connected);
  });

  test('never deletes a broadcast left by interrupted setup', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/liveBroadcasts/transition')) {
        return http.Response('{"error":"not live"}', 400);
      }
      if (request.url.path.endsWith('/liveBroadcasts')) {
        return _jsonResponse('{"id":"broadcast-partial"}');
      }
      if (request.url.path.endsWith('/liveStreams')) {
        return http.Response('{"error":"stream setup failed"}', 500);
      }
      return http.Response('not found', 404);
    });
    final service = YouTubeLiveService(api: YouTubeApi(client));

    await expectLater(
      service.prepareBroadcast(
        const StreamSession(title: 'Interrupted service'),
      ),
      throwsA(anything),
    );
    await expectLater(service.finishBroadcast(), throwsA(anything));

    expect(requests.where((request) => request.method == 'DELETE'), isEmpty);
    expect(service.target, isNull);
    expect(service.status, YouTubeConnectionStatus.error);
  });
}

http.Response _jsonResponse(String body) => http.Response(
  body,
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);
