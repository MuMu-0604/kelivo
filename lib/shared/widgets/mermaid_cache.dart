class MermaidHeightCache {
  // Simple LRU-ish cache with max size; evict oldest insert when over limit.
  static final Map<String, double> _map = <String, double>{};
  static int _maxSize = 200;

  static void configure({int? maxSize}) {
    if (maxSize != null && maxSize > 0) _maxSize = maxSize;
  }

  static double? get(String code) {
    final v = _map[code];
    if (v != null) {
      // Touch entry to refresh recency: remove and reinsert
      _map.remove(code);
      _map[code] = v;
    }
    return v;
  }

  static void put(String code, double height) {
    // Basic guard: store sensible heights only
    final h = height.isFinite ? height.clamp(60, 4000).toDouble() : 160.0;
    if (_map.containsKey(code)) {
      _map.remove(code);
      _map[code] = h;
    } else {
      if (_map.length >= _maxSize) {
        // Evict first/oldest entry
        final firstKey = _map.keys.isNotEmpty ? _map.keys.first : null;
        if (firstKey != null) _map.remove(firstKey);
      }
      _map[code] = h;
    }
  }
}
