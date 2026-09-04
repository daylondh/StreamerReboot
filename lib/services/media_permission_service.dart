import 'dart:io';
import 'package:flutter/services.dart';

enum MediaAuthorization { granted, denied, notDetermined }

class MediaPermissionResult {
  const MediaPermissionResult({required this.camera, required this.microphone});
  final MediaAuthorization camera;
  final MediaAuthorization microphone;

  bool get allGranted =>
      camera == MediaAuthorization.granted &&
      microphone == MediaAuthorization.granted;
  bool get hasDenied =>
      camera == MediaAuthorization.denied ||
      microphone == MediaAuthorization.denied;
  bool get needsRequest =>
      camera == MediaAuthorization.notDetermined ||
      microphone == MediaAuthorization.notDetermined;
}

class MediaPermissionService {
  static const _channel = MethodChannel('church_streamer/media_permissions');

  Future<MediaPermissionResult> check() => _read('status');
  Future<MediaPermissionResult> request() => _read('request');

  Future<MediaPermissionResult> _read(String method) async {
    if (Platform.isMacOS) {
      final result = await _channel.invokeMapMethod<String, String>(method);
      return MediaPermissionResult(
        camera: _parse(result?['camera']),
        microphone: _parse(result?['microphone']),
      );
    }
    // Windows uses global desktop-app privacy controls. Linux uses device or
    // sandbox permissions. Device opening is the native access check there.
    return const MediaPermissionResult(
      camera: MediaAuthorization.granted,
      microphone: MediaAuthorization.granted,
    );
  }

  MediaAuthorization _parse(String? value) => switch (value) {
    'granted' => MediaAuthorization.granted,
    'denied' => MediaAuthorization.denied,
    _ => MediaAuthorization.notDetermined,
  };
}
