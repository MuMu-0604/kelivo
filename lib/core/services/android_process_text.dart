import 'dart:async';
import 'package:flutter/services.dart';

class AndroidProcessText {
  static const MethodChannel _channel = MethodChannel('app.process_text');
  static final StreamController<String> _controller =
      StreamController.broadcast();
  static bool _initialized = false;

  static void ensureInitialized() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onProcessText') return;
      final raw = call.arguments?.toString() ?? '';
      final text = raw.trim();
      if (text.isNotEmpty) {
        _controller.add(text);
      }
    });
  }

  static Stream<String> get stream => _controller.stream;

  static Future<String?> getInitialText() async {
    try {
      final res = await _channel.invokeMethod<String>('getInitialText');
      final text = res?.trim();
      if (text == null || text.isEmpty) return null;
      return text;
    } catch (_) {
      return null;
    }
  }
}
