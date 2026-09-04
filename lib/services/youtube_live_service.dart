import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:googleapis/youtube/v3.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../domain/stream_session.dart';

abstract interface class YouTubeCredentialStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

class SecureYouTubeCredentialStore implements YouTubeCredentialStore {
  const SecureYouTubeCredentialStore();
  static const _key = 'youtube.oauth.accessCredentials';
  static const _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}

enum YouTubeConnectionStatus {
  checkingCredentials,
  credentialsMissing,
  disconnected,
  reconnecting,
  authorizing,
  connected,
  creatingBroadcast,
  creatingStream,
  bindingBroadcast,
  broadcastReady,
  waitingForIngest,
  ingestActive,
  transitioningLive,
  live,
  completing,
  error,
}

class YouTubeLiveTarget {
  const YouTubeLiveTarget({
    required this.broadcastId,
    required this.streamId,
    required this.ingestionUrl,
    this.fallbackIngestionUrl,
  });

  final String broadcastId;
  final String streamId;

  /// Contains the secret stream name. Never log or display this value.
  final String ingestionUrl;
  final String? fallbackIngestionUrl;

  Uri get watchUrl => Uri.parse('https://www.youtube.com/watch?v=$broadcastId');
}

class YouTubeLiveService extends ChangeNotifier {
  YouTubeLiveService({
    File? credentialsFile,
    YouTubeApi? api,
    YouTubeCredentialStore? credentialStore,
    http.Client Function()? httpClientFactory,
    this.ingestPollInterval = const Duration(seconds: 2),
    this.ingestTimeout = const Duration(seconds: 45),
    this.completionDrainTimeout = const Duration(seconds: 20),
  }) : _configuredCredentialsFile = credentialsFile,
       _credentialStore =
           credentialStore ?? const SecureYouTubeCredentialStore(),
       _httpClientFactory = httpClientFactory ?? http.Client.new,
       _api = api,
       _status = api == null
           ? YouTubeConnectionStatus.checkingCredentials
           : YouTubeConnectionStatus.connected;

  static const credentialsFileName = 'client_secrets.json';
  final File? _configuredCredentialsFile;
  final YouTubeCredentialStore _credentialStore;
  final http.Client Function() _httpClientFactory;
  final Duration ingestPollInterval;
  final Duration ingestTimeout;
  final Duration completionDrainTimeout;
  File? _credentialsFile;
  AutoRefreshingAuthClient? _client;
  YouTubeApi? _api;
  YouTubeConnectionStatus _status;
  String? _channelTitle;
  String? _error;
  YouTubeLiveTarget? _target;
  String? _broadcastId;
  String? _streamId;
  int _startGeneration = 0;

  YouTubeConnectionStatus get status => _status;
  String? get channelTitle => _channelTitle;
  String? get error => _error;
  YouTubeLiveTarget? get target => _target;
  bool get hasCredentials => _credentialsFile != null;
  bool get isConnected => _api != null;
  bool get canUseFallbackIngestion => _target?.fallbackIngestionUrl != null;
  String get statusMessage => switch (_status) {
    YouTubeConnectionStatus.checkingCredentials =>
      'YouTube: checking credentials…',
    YouTubeConnectionStatus.credentialsMissing =>
      'YouTube: client_secrets.json is missing',
    YouTubeConnectionStatus.disconnected => 'YouTube: not connected',
    YouTubeConnectionStatus.reconnecting =>
      'YouTube: reconnecting last channel…',
    YouTubeConnectionStatus.authorizing =>
      'YouTube: waiting for browser authorization…',
    YouTubeConnectionStatus.connected =>
      'YouTube: connected to ${_channelTitle ?? 'channel'}',
    YouTubeConnectionStatus.creatingBroadcast => 'YouTube: creating broadcast…',
    YouTubeConnectionStatus.creatingStream =>
      'YouTube: creating ingest stream…',
    YouTubeConnectionStatus.bindingBroadcast =>
      'YouTube: binding broadcast to stream…',
    YouTubeConnectionStatus.broadcastReady =>
      'YouTube: broadcast created; media publisher not started',
    YouTubeConnectionStatus.waitingForIngest =>
      'YouTube: waiting for incoming video…',
    YouTubeConnectionStatus.ingestActive => 'YouTube: incoming video detected',
    YouTubeConnectionStatus.transitioningLive => 'YouTube: starting broadcast…',
    YouTubeConnectionStatus.live => 'YouTube: live',
    YouTubeConnectionStatus.completing => 'YouTube: ending broadcast…',
    YouTubeConnectionStatus.error => 'YouTube: ${_error ?? 'unknown error'}',
  };

  Future<void> initialize() async {
    _credentialsFile =
        _configuredCredentialsFile ?? await _findCredentialsFile();
    final file = _credentialsFile;
    if (file == null) {
      _setStatus(YouTubeConnectionStatus.credentialsMissing);
      return;
    }
    _setStatus(YouTubeConnectionStatus.disconnected);
    await _reconnect(file);
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
      await _credentialStore.write(jsonEncode(_client!.credentials.toJson()));
      _persistCredentialUpdates(_client!);
      await _validateClient(_client!);
    } catch (error) {
      await disconnect();
      _setError(_friendlyError(error));
    }
  }

  Future<void> _reconnect(File file) async {
    String? stored;
    try {
      stored = await _credentialStore.read();
    } catch (error) {
      _setError(
        Platform.isLinux
            ? 'Secure credential storage is unavailable. Install libsecret and start a Secret Service keyring.'
            : 'Secure credential storage is unavailable: ${_friendlyError(error)}',
      );
      return;
    }
    if (stored == null) return;
    _setStatus(YouTubeConnectionStatus.reconnecting);
    try {
      final clientId = await _readClientId(file);
      final decoded = jsonDecode(stored);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Saved authorization is invalid.');
      }
      final client = autoRefreshingClient(
        clientId,
        AccessCredentials.fromJson(decoded),
        _httpClientFactory(),
      );
      _client = client;
      _persistCredentialUpdates(client);
      await _validateClient(client);
      await _credentialStore.write(jsonEncode(client.credentials.toJson()));
    } catch (_) {
      _client?.close();
      _client = null;
      _api = null;
      _channelTitle = null;
      try {
        await _credentialStore.delete();
      } catch (_) {
        // The connection can still fall back even if secure-store cleanup fails.
      }
      _setStatus(YouTubeConnectionStatus.disconnected);
    }
  }

  Future<void> _validateClient(AutoRefreshingAuthClient client) async {
    final api = YouTubeApi(client);
    final channels = await api.channels.list(['snippet'], mine: true);
    if (channels.items == null || channels.items!.isEmpty) {
      throw StateError('This Google account has no YouTube channel.');
    }
    _api = api;
    _channelTitle = channels.items!.first.snippet?.title ?? 'YouTube channel';
    _setStatus(YouTubeConnectionStatus.connected);
  }

  void _persistCredentialUpdates(AutoRefreshingAuthClient client) {
    client.credentialUpdates.listen((credentials) {
      unawaited(
        _credentialStore.write(jsonEncode(credentials.toJson())).catchError((
          Object error,
          StackTrace stackTrace,
        ) {
          debugPrint('Could not persist refreshed YouTube credentials: $error');
        }),
      );
    });
  }

  /// Creates and binds the YouTube resources required by an RTMP publisher.
  Future<YouTubeLiveTarget> prepareBroadcast(StreamSession session) async {
    final api = _api;
    if (api == null) throw StateError('Connect a YouTube channel first.');
    _setStatus(YouTubeConnectionStatus.creatingBroadcast);
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
            enableAutoStart: false,
            enableAutoStop: false,
            enableDvr: true,
            recordFromStart: true,
            monitorStream: MonitorStreamInfo(enableMonitorStream: false),
          ),
        ),
        ['snippet', 'status', 'contentDetails'],
      );
      _broadcastId = broadcast.id;
      _setStatus(YouTubeConnectionStatus.creatingStream);
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
      _streamId = stream.id;
      final broadcastId = broadcast.id;
      final streamId = stream.id;
      final ingestion = stream.cdn?.ingestionInfo;
      final secureAddress = ingestion?.rtmpsIngestionAddress;
      final standardAddress = ingestion?.ingestionAddress;
      // This FFmpeg/VideoToolbox environment consistently receives Apple's
      // errSSLClosedAbort (-9806) over RTMPS. Prefer YouTube's API-provided
      // standard RTMP endpoint and retain RTMPS as a one-time alternate.
      final address = standardAddress ?? secureAddress;
      final streamName = ingestion?.streamName;
      if (broadcastId == null ||
          streamId == null ||
          address == null ||
          streamName == null) {
        throw StateError('YouTube did not return complete ingest settings.');
      }
      _setStatus(YouTubeConnectionStatus.bindingBroadcast);
      await api.liveBroadcasts.bind(broadcastId, [
        'id',
        'contentDetails',
      ], streamId: streamId);
      _target = YouTubeLiveTarget(
        broadcastId: broadcastId,
        streamId: streamId,
        ingestionUrl:
            '${_withExplicitRtmpsPort(address).replaceFirst(RegExp(r'/+$'), '')}'
            '/$streamName',
        fallbackIngestionUrl: secureAddress != null && standardAddress != null
            ? '${_withExplicitRtmpsPort(secureAddress).replaceFirst(RegExp(r'/+$'), '')}/$streamName'
            : null,
      );
      _setStatus(YouTubeConnectionStatus.broadcastReady);
      return _target!;
    } catch (error) {
      _setError(_friendlyError(error));
      rethrow;
    }
  }

  bool useFallbackIngestion() {
    final target = _target;
    final fallback = target?.fallbackIngestionUrl;
    if (target == null || fallback == null) return false;
    _target = YouTubeLiveTarget(
      broadcastId: target.broadcastId,
      streamId: target.streamId,
      ingestionUrl: fallback,
    );
    if (_status != YouTubeConnectionStatus.broadcastReady) {
      _setStatus(YouTubeConnectionStatus.broadcastReady);
    }
    return true;
  }

  /// Waits until YouTube confirms receipt of encoded media, then explicitly
  /// transitions the bound broadcast to live.
  Future<void> startBroadcast() async {
    final api = _api;
    final target = _target;
    if (api == null || target == null) {
      throw StateError('The YouTube broadcast is not ready.');
    }

    final generation = ++_startGeneration;
    _setStatus(YouTubeConnectionStatus.waitingForIngest);
    final stopwatch = Stopwatch()..start();
    try {
      while (stopwatch.elapsed < ingestTimeout) {
        if (generation != _startGeneration) {
          throw StateError('YouTube live transition was cancelled.');
        }
        final response = await api.liveStreams.list(
          ['status'],
          id: [target.streamId],
        );
        final streamStatus = response.items?.firstOrNull?.status;
        if (streamStatus?.streamStatus == 'active') {
          _setStatus(YouTubeConnectionStatus.ingestActive);
          while (stopwatch.elapsed < ingestTimeout) {
            if (generation != _startGeneration) {
              throw StateError('YouTube live transition was cancelled.');
            }
            final broadcasts = await api.liveBroadcasts.list(
              ['status'],
              id: [target.broadcastId],
            );
            final lifeCycle =
                broadcasts.items?.firstOrNull?.status?.lifeCycleStatus;
            debugPrint('[YouTube lifecycle] ${lifeCycle ?? 'unknown'}');
            switch (lifeCycle) {
              case 'live':
                _setStatus(YouTubeConnectionStatus.live);
                return;
              case 'ready':
              case 'testing':
                _setStatus(YouTubeConnectionStatus.transitioningLive);
                await api.liveBroadcasts.transition(
                  'live',
                  target.broadcastId,
                  ['id', 'status'],
                );
                _setStatus(YouTubeConnectionStatus.live);
                return;
              case 'complete':
              case 'revoked':
                throw StateError(
                  'YouTube broadcast entered the $lifeCycle state before '
                  'going live.',
                );
              default:
                await Future<void>.delayed(ingestPollInterval);
            }
          }
        }
        if (streamStatus?.streamStatus == 'error') {
          final health = streamStatus?.healthStatus?.status;
          throw StateError(
            health == null
                ? 'YouTube rejected the incoming media.'
                : 'YouTube ingest health is $health.',
          );
        }
        await Future<void>.delayed(ingestPollInterval);
      }
      throw TimeoutException(
        'YouTube did not detect incoming video within '
        '${ingestTimeout.inSeconds} seconds.',
      );
    } catch (error) {
      if (generation == _startGeneration) {
        _setError(_friendlyError(error));
      }
      rethrow;
    }
  }

  void cancelPendingStart() => _startGeneration++;

  void reportPublisherError(Object error) {
    final message = _friendlyError(error);
    debugPrint('[YouTube publisher] $message');
    _setError(message);
  }

  /// Completes an active broadcast without deleting its YouTube resources.
  /// This is intentionally safe to call more than once.
  Future<void> finishBroadcast() async {
    cancelPendingStart();
    final api = _api;
    final broadcastId = _broadcastId;
    final streamId = _streamId;
    if (api == null || (broadcastId == null && _streamId == null)) return;

    final wasLive = _status == YouTubeConnectionStatus.live;
    _setStatus(YouTubeConnectionStatus.completing);
    Object? cleanupError;
    if (broadcastId != null) {
      try {
        if (wasLive && streamId != null) {
          await _waitForIngestDrain(api, streamId);
        }
        // Completing retains the archive. If YouTube rejects the transition,
        // preserve every remote resource rather than risk destroying a video.
        await api.liveBroadcasts.transition('complete', broadcastId, [
          'status',
        ]);
      } catch (error) {
        cleanupError = error;
      }
    }

    _target = null;
    _broadcastId = null;
    _streamId = null;
    if (cleanupError != null) {
      _setError(
        'Could not finalize the YouTube broadcast: '
        '${_friendlyError(cleanupError)}',
      );
      throw cleanupError;
    }
    _setStatus(YouTubeConnectionStatus.connected);
  }

  Future<void> _waitForIngestDrain(YouTubeApi api, String streamId) async {
    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < completionDrainTimeout) {
      final response = await api.liveStreams.list(['status'], id: [streamId]);
      final status = response.items?.firstOrNull?.status?.streamStatus;
      debugPrint('[YouTube ingest drain] ${status ?? 'unknown'}');
      if (status != 'active') return;
      await Future<void>.delayed(ingestPollInterval);
    }
    debugPrint(
      '[YouTube ingest drain] Timed out after '
      '${completionDrainTimeout.inSeconds}s; completing broadcast.',
    );
  }

  Future<void> disconnect() async {
    _client?.close();
    _client = null;
    _api = null;
    _channelTitle = null;
    _target = null;
    _broadcastId = null;
    _streamId = null;
    try {
      await _credentialStore.delete();
    } catch (error) {
      _setError(
        Platform.isLinux
            ? 'Could not access the system keyring. Install libsecret and start a Secret Service keyring.'
            : 'Could not clear secure credentials: ${_friendlyError(error)}',
      );
      return;
    }
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

  static String _withExplicitRtmpsPort(String address) {
    final uri = Uri.parse(address);
    if (uri.scheme == 'rtmps' && !uri.hasPort) {
      return uri.replace(port: 443).toString();
    }
    return address;
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
