import 'dart:async';
import 'package:flutter/services.dart';

class ClipboardImages {
  static const MethodChannel _channel = MethodChannel('app.clipboard');

  static Future<List<String>> getImagePaths() async {
    try {
      final res = await _channel.invokeMethod<List<dynamic>>(
        'getClipboardImages',
      );
      if (res == null) return const [];
      return res.map((e) => e.toString()).toList();
    } catch (_) {
      return const [];
    }
  }

  // Set an image to the system clipboard from a file path (desktop only).
  static Future<bool> setImagePath(String path) async {
    try {
      final res = await _channel.invokeMethod<dynamic>(
        'setClipboardImage',
        path,
      );
      if (res is bool) return res;
      return res == true;
    } catch (_) {
      return false;
    }
  }

  // Get file paths from system clipboard (desktop only).
  // Returns absolute file system paths for items copied in Finder/Explorer/Files.
  static Future<List<String>> getFilePaths() async {
    try {
      final res = await _channel.invokeMethod<List<dynamic>>(
        'getClipboardFiles',
      );
      if (res == null) return const [];
      return res.map((e) => e.toString()).toList();
    } catch (_) {
      return const [];
    }
  }
}
