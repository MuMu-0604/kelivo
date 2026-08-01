import 'dart:typed_data';

class MermaidImageCache {
  static final Map<String, Uint8List> _map = <String, Uint8List>{};
  static int _maxSize = 120;

  static String _normalize(String code) {
    return code.replaceAll('\r\n', '\n').trim();
  }

  static void configure({int? maxSize}) {
    if (maxSize != null && maxSize > 0) _maxSize = maxSize;
  }

  static Uint8List? get(String code) => _map[_normalize(code)];

  static void put(String code, Uint8List bytes) {
    final key = _normalize(code);
    if (_map.containsKey(key)) {
      _map.remove(key);
      _map[key] = bytes;
      return;
    }
    if (_map.length >= _maxSize) {
      final first = _map.keys.isNotEmpty ? _map.keys.first : null;
      if (first != null) _map.remove(first);
    }
    _map[key] = bytes;
  }

  static void clear() => _map.clear();
}
