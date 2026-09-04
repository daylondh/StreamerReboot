import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:googleapis/youtube/v3.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/stream_session.dart';

enum YouTubeConnectionStatus {
  checkingCredentials,
  credentialsMissing,
  disconnected,
  authorizing,
  connected,
  preparingBroadcast,
  broadcastReady,
  error,
}

class YouTubeLiveTarget {
  const YouTubeLiveTarget({
    required this.broadcastId,
    required this.streamId,
    required this.ingestionUrl,
  });

  final String broadcastId;
  final String streamId;

  /// Contains the secret stream name. Never log or display this value.
  final String ingestionUrl;

  Uri get watchUrl => Uri.parse('https://www.youtube.com/watch?v=$broadcastId');
}

class YouTubeLiveService extends ChangeNotifier {
  YouTubeLiveService({File? credentialsFile, YouTubeApi? api})
    : _configuredCredentialsFile = credentialsFile,
      _api = api,
      _status = api == null
          ? YouTubeConnectionStatus.checkingCredentials
          : YouTubeConnectionStatus.connected;

  static const credentialsFileName = 'client_secrets.json';
  final File? _configuredCredentialsFile;
  File? _credentialsFile;
  AutoRefreshingAuthClient? _client;
  YouTubeApi? _api;
  YouTubeConnectionStatus _status;
  String? _channelTitle;
  String? _error;
  YouTubeLiveTarget? _target;

  YouTubeConnectionStatus get status => _status;
  String? get channelTitle => _channelTitle;
  String? get error => _error;
  YouTubeLiveTarget? get target => _target;
  bool get hasCredentials => _credentialsFile != null;
  bool get isConnected => _api != null;

  Future<void> initialize() async {
    _credentialsFile =
        _configuredCredentialsFile ?? await _findCredentialsFile();
    _setStatus(
      _credentialsFile == null
          ? YouTubeConnectionStatus.credentialsMissing
          : YouTubeConnectionStatus.disconnected,
    );
  }

  Future<void> connect() async {
    final file = _credentialsFile;
    if (file == null) {
      _setError(
        'Add $credentialsFileName to the project folder, then restart the app.',
      );
      return;
    }
    _setStatus(YouTubeConnectionStatus.authorizing);
    try {
      final clientId = await _readClientId(file);
      _client = await clientViaUserConsent(
        clientId,
        [YouTubeApi.youtubeForceSslScope],
        (authorizationUrl) async {
          final opened = await launchUrl(
            Uri.parse(authorizationUrl),
            mode: LaunchMode.externalApplication,
          );
          if (!opened) {
            throw StateError('Could not open the Google sign-in page.');
          }
        },
      );
      final api = YouTubeApi(_client!);
      final channels = await api.channels.list(['snippet'], mine: true);
      if (channels.items == null || channels.items!.isEmpty) {
        throw StateError('This Google account has no YouTube channel.');
      }
      _api = api;
      _channelTitle = channels.items!.first.snippet?.title ?? 'YouTube channel';
      _setStatus(YouTubeConnectionStatus.connected);
    } catch (error) {
      await disconnect();
      _setError(_friendlyError(error));
    }
  }

  /// Creates and binds the YouTube resources required by an RTMP publisher.
  Future<YouTubeLiveTarget> prepareBroadcast(StreamSession session) async {
    final api = _api;
    if (api == null) throw StateError('Connect a YouTube channel first.');
    _setStatus(YouTubeConnectionStatus.preparingBroadcast);
    try {
      final broadcast = await api.liveBroadcasts.insert(
        LiveBroadcast(
          snippet: LiveBroadcastSnippet(
            title: session.title,
            scheduledStartTime: DateTime.now().toUtc(),
          ),
          status: LiveBroadcastStatus(
            privacyStatus: session.privacy.name,
            selfDeclaredMadeForKids: false,
          ),
          contentDetails: LiveBroadcastContentDetails(
            enableAutoStart: true,
            enableAutoStop: true,
            enableDvr: true,
            recordFromStart: true,
          ),
        ),
        ['snippet', 'status', 'contentDetails'],
      );
      final stream = await api.liveStreams.insert(
        LiveStream(
          snippet: LiveStreamSnippet(title: session.title),
          cdn: CdnSettings(
            ingestionType: 'rtmp',
            resolution: '720p',
            frameRate: '30fps',
          ),
        ),
        ['snippet', 'cdn', 'status'],
      );
      final broadcastId = broadcast.id;
      final streamId = stream.id;
      final ingestion = stream.cdn?.ingestionInfo;
      final address =
          ingestion?.rtmpsIngestionAddress ?? ingestion?.ingestionAddress;
      final streamName = ingestion?.streamName;
      if (broadcastId == null ||
          streamId == null ||
          address == null ||
          streamName == null) {
        throw StateError('YouTube did not return complete ingest settings.');
      }
      await api.liveBroadcasts.bind(broadcastId, [
        'id',
        'contentDetails',
      ], streamId: streamId);
      _target = YouTubeLiveTarget(
        broadcastId: broadcastId,
        streamId: streamId,
        ingestionUrl: '${address.replaceFirst(RegExp(r'/+$'), '')}/$streamName',
      );
      _setStatus(YouTubeConnectionStatus.broadcastReady);
      return _target!;
    } catch (error) {
      _setError(_friendlyError(error));
      rethrow;
    }
  }

  Future<void> disconnect() async {
    _client?.close();
    _client = null;
    _api = null;
    _channelTitle = null;
    _target = null;
    if (_status != YouTubeConnectionStatus.error) {
      _setStatus(
        hasCredentials
            ? YouTubeConnectionStatus.disconnected
            : YouTubeConnectionStatus.credentialsMissing,
      );
    }
  }

  static Future<ClientId> _readClientId(File file) async {
    final json = jsonDecode(await file.readAsString());
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Credentials must contain a JSON object.');
    }
    final section = json['installed'];
    if (section is! Map<String, dynamic>) {
      throw const FormatException(
        'Use an OAuth client configured as a Desktop app.',
      );
    }
    final identifier = section['client_id'];
    final secret = section['client_secret'];
    if (identifier is! String || identifier.isEmpty) {
      throw const FormatException('Credentials are missing client_id.');
    }
    return ClientId(identifier, secret is String ? secret : null);
  }

  static Future<File?> _findCredentialsFile() async {
    final executableDirectory = File(Platform.resolvedExecutable).parent;
    final candidates = [
      File('${Directory.current.path}/$credentialsFileName'),
      File('${executableDirectory.path}/$credentialsFileName'),
      if (Platform.isMacOS)
        File(
          '${executableDirectory.parent.path}/Resources/$credentialsFileName',
        ),
    ];
    for (final candidate in candidates) {
      if (await candidate.exists()) return candidate;
    }
    return null;
  }

  String _friendlyError(Object error) => error.toString().replaceFirst(
    RegExp(r'^(Exception|StateError|FormatException):\s*'),
    '',
  );

  void _setStatus(YouTubeConnectionStatus value) {
    _status = value;
    _error = null;
    notifyListeners();
  }

  void _setError(String message) {
    _status = YouTubeConnectionStatus.error;
    _error = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _client?.close();
    super.dispose();
  }
}
