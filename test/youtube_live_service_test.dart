import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/youtube/v3.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:streamer_reboot/domain/stream_session.dart';
import 'package:streamer_reboot/services/youtube_live_service.dart';

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
    final service = YouTubeLiveService(credentialsFile: file);

    await service.initialize();

    expect(service.hasCredentials, isTrue);
    expect(service.status, YouTubeConnectionStatus.disconnected);
  });

  test('creates and binds a broadcast and RTMP stream', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/liveBroadcasts/bind')) {
        return _jsonResponse('{"id":"broadcast-1"}');
      }
      if (request.url.path.endsWith('/liveBroadcasts')) {
        return _jsonResponse('{"id":"broadcast-1"}');
      }
      if (request.url.path.endsWith('/liveStreams')) {
        return _jsonResponse(
          jsonEncode({
            'id': 'stream-1',
            'cdn': {
              'ingestionInfo': {
                'rtmpsIngestionAddress': 'rtmps://a.rtmps.youtube.com/live2',
                'streamName': 'secret-key',
              },
            },
          }),
        );
      }
      return http.Response('not found', 404);
    });
    final service = YouTubeLiveService(api: YouTubeApi(client));

    final target = await service.prepareBroadcast(
      const StreamSession(
        title: 'Sunday Worship',
        privacy: ServicePrivacy.unlisted,
      ),
    );

    expect(target.broadcastId, 'broadcast-1');
    expect(target.streamId, 'stream-1');
    expect(target.ingestionUrl, 'rtmps://a.rtmps.youtube.com/live2/secret-key');
    expect(requests, hasLength(3));
    final broadcastBody = jsonDecode(requests.first.body);
    expect(broadcastBody['snippet']['title'], 'Sunday Worship');
    expect(broadcastBody['status']['privacyStatus'], 'unlisted');
    expect(requests.last.url.queryParameters['streamId'], 'stream-1');
  });
}

http.Response _jsonResponse(String body) => http.Response(
  body,
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);
