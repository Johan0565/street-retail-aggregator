import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class ApiConfig {
  static const String _override = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (_override.isNotEmpty) return _override;

    if (!kIsWeb && Platform.isAndroid) {
      return 'http://10.0.2.2:8080';
    }
    return 'http://127.0.0.1:8080';
  }

  static String get apiUrl => '$baseUrl/api';

  static String get wsUrl {
    final base = baseUrl;
    if (base.startsWith('https://')) {
      return 'wss://${base.substring(8)}/ws';
    }
    return 'ws://${base.substring(7)}/ws';
  }
}
