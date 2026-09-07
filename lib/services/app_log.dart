import 'package:flutter/foundation.dart';

void logMessage(String message) {
  final timestamp = DateTime.now().toUtc().toIso8601String();
  debugPrint('$timestamp $message');
}
