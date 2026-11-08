import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'app_log.dart';

enum UpdateStatus {
  unsupported,
  checking,
  current,
  available,
  downloading,
  ready,
  error,
}

class AppUpdateService extends ChangeNotifier {
  AppUpdateService({
    required this.currentVersion,
    required this.stateDirectory,
    http.Client? client,
    this.isWindows = false,
  }) : _client = client ?? http.Client();

  static const latestReleaseUri =
      'https://api.github.com/repos/daylondh/StreamerReboot/releases/latest';
  static const windowsAssetName = 'ChurchStreamer-Windows-x64.zip';

  final String currentVersion;
  final Directory stateDirectory;
  final http.Client _client;
  final bool isWindows;

  UpdateStatus status = UpdateStatus.checking;
  String? availableVersion;
  String? message;
  double? downloadProgress;
  File? _stagedArchive;
  Uri? _downloadUri;
  String? _expectedDigest;
  bool _downloadsAllowed = true;
  bool _disposed = false;

  bool get updateReady =>
      status == UpdateStatus.ready && _stagedArchive != null;

  Future<void> initialize() async {
    if (!isWindows) {
      status = UpdateStatus.unsupported;
      _notify();
      return;
    }
    await checkForUpdates();
  }

  void setDownloadsAllowed(bool allowed) {
    _downloadsAllowed = allowed;
    if (allowed && status == UpdateStatus.available) {
      unawaited(downloadAvailableUpdate());
    }
  }

  Future<void> checkForUpdates() async {
    if (!isWindows) return;
    status = UpdateStatus.checking;
    message = null;
    _notify();
    try {
      final response = await _client.get(
        Uri.parse(latestReleaseUri),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      );
      if (response.statusCode == 404) {
        status = UpdateStatus.current;
        message = 'No published updates yet.';
        _notify();
        return;
      }
      if (response.statusCode != 200) {
        throw HttpException('GitHub returned ${response.statusCode}.');
      }

      final release = jsonDecode(response.body) as Map<String, dynamic>;
      final latestVersion = _normalizedVersion(release['tag_name'] as String?);
      if (latestVersion == null) {
        throw const FormatException('Invalid release tag.');
      }
      if (_compareVersions(latestVersion, currentVersion) <= 0) {
        status = UpdateStatus.current;
        message = 'Church Streamer is up to date.';
        _notify();
        return;
      }

      final assets = release['assets'] as List<dynamic>? ?? const [];
      final asset = assets.cast<Map<String, dynamic>>().where(
        (candidate) => candidate['name'] == windowsAssetName,
      );
      if (asset.isEmpty) {
        throw const FormatException('Windows update asset is missing.');
      }
      final selected = asset.first;
      final digest = selected['digest'] as String?;
      final downloadUrl = selected['browser_download_url'] as String?;
      if (digest == null || !digest.startsWith('sha256:')) {
        throw const FormatException('Windows update digest is missing.');
      }
      if (downloadUrl == null) {
        throw const FormatException('Windows update URL is missing.');
      }

      availableVersion = latestVersion;
      _downloadUri = Uri.parse(downloadUrl);
      _expectedDigest = digest.substring('sha256:'.length).toLowerCase();
      status = UpdateStatus.available;
      message = 'Version $latestVersion is available.';
      _notify();
      if (_downloadsAllowed) await downloadAvailableUpdate();
    } catch (error) {
      status = UpdateStatus.error;
      message = 'Could not check for updates: $error';
      logMessage(message!);
      _notify();
    }
  }

  Future<void> downloadAvailableUpdate() async {
    final uri = _downloadUri;
    final version = availableVersion;
    if (!_downloadsAllowed || uri == null || version == null) return;
    status = UpdateStatus.downloading;
    downloadProgress = null;
    message = 'Downloading version $version…';
    _notify();

    await stateDirectory.create(recursive: true);
    final archive = File(
      '${stateDirectory.path}${Platform.pathSeparator}$windowsAssetName',
    );
    IOSink? sink;
    try {
      final request = http.Request('GET', uri);
      final response = await _client.send(request);
      if (response.statusCode != 200) {
        throw HttpException('GitHub returned ${response.statusCode}.');
      }
      final total = response.contentLength;
      var received = 0;
      sink = archive.openWrite();
      await for (final chunk in response.stream) {
        if (!_downloadsAllowed) throw const _DownloadPaused();
        sink.add(chunk);
        received += chunk.length;
        downloadProgress = total == null || total == 0
            ? null
            : received / total;
        _notify();
      }
      await sink.flush();
      await sink.close();
      sink = null;

      final digest = await sha256.bind(archive.openRead()).first;
      if (digest.toString().toLowerCase() != _expectedDigest) {
        throw const FormatException('Downloaded update failed verification.');
      }
      _stagedArchive = archive;
      status = UpdateStatus.ready;
      downloadProgress = 1;
      message = 'Version $version is ready and will install when you quit.';
      _notify();
    } on _DownloadPaused {
      await sink?.close();
      sink = null;
      if (await archive.exists()) await archive.delete();
      status = UpdateStatus.available;
      downloadProgress = null;
      message = 'Update paused while streaming.';
      _notify();
    } catch (error) {
      await sink?.close();
      sink = null;
      if (await archive.exists()) await archive.delete();
      status = UpdateStatus.error;
      downloadProgress = null;
      message = 'Could not download the update: $error';
      logMessage(message!);
      _notify();
    }
  }

  Future<bool> launchInstallerOnExit() async {
    final archive = _stagedArchive;
    final version = availableVersion;
    if (!isWindows ||
        archive == null ||
        version == null ||
        !await archive.exists()) {
      return false;
    }
    try {
      await stateDirectory.create(recursive: true);
      final script = File(
        '${stateDirectory.path}${Platform.pathSeparator}Install-StagedUpdate.ps1',
      );
      await script.writeAsString(
        await rootBundle.loadString('assets/Install-StagedUpdate.ps1'),
        flush: true,
      );
      await Process.start('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        script.path,
        '-Archive',
        archive.path,
        '-Destination',
        File(Platform.resolvedExecutable).parent.path,
        '-WaitForProcessId',
        '$pid',
        '-ExpectedVersion',
        version,
        '-StateDirectory',
        stateDirectory.path,
      ], mode: ProcessStartMode.detached);
      return true;
    } catch (error) {
      logMessage('Could not launch the staged update: $error');
      return false;
    }
  }

  static String? _normalizedVersion(String? version) {
    if (version == null) return null;
    final match = RegExp(
      r'^v?(\d+\.\d+\.\d+)(?:[-+].*)?$',
    ).firstMatch(version.trim());
    return match?.group(1);
  }

  static int _compareVersions(String left, String right) {
    final a = left.split('.').map(int.parse).toList();
    final b = right.split('.').map(int.parse).toList();
    for (var index = 0; index < 3; index++) {
      final comparison = a[index].compareTo(b[index]);
      if (comparison != 0) return comparison;
    }
    return 0;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _client.close();
    super.dispose();
  }
}

class _DownloadPaused implements Exception {
  const _DownloadPaused();
}
