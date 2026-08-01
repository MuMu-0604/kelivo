class UnicodeSanitizer {
  static const int _replacementChar = 0xFFFD;

  static String sanitize(String input) {
    if (input.isEmpty) return input;

    StringBuffer? out;
    final len = input.length;
    int i = 0;
    while (i < len) {
      final cu = input.codeUnitAt(i);

      if (_isHighSurrogate(cu)) {
        if (i + 1 < len) {
          final next = input.codeUnitAt(i + 1);
          if (_isLowSurrogate(next)) {
            if (out != null) {
              out.writeCharCode(_codePointFromSurrogates(cu, next));
            }
            i += 2;
            continue;
          }

          // Common corruption pattern observed in some PDF text extraction:
          // the low surrogate may have its high nibble stripped, turning e.g.
          // 0xDCE1 into U+0CE1 (0x0CE1). Repair when it looks like this.
          if (_looksLikeStrippedLowSurrogate(next)) {
            final repairedLow = 0xD000 | next;
            if (_isLowSurrogate(repairedLow)) {
              out ??= StringBuffer(input.substring(0, i));
              out.writeCharCode(_codePointFromSurrogates(cu, repairedLow));
              i += 2;
              continue;
            }
          }
        }

        out ??= StringBuffer(input.substring(0, i));
        out.writeCharCode(_replacementChar);
        i += 1;
        continue;
      }

      if (_isLowSurrogate(cu)) {
        out ??= StringBuffer(input.substring(0, i));
        out.writeCharCode(_replacementChar);
        i += 1;
        continue;
      }

      if (out != null) out.writeCharCode(cu);
      i += 1;
    }

    return out?.toString() ?? input;
  }

  static bool _isHighSurrogate(int codeUnit) =>
      codeUnit >= 0xD800 && codeUnit <= 0xDBFF;
  static bool _isLowSurrogate(int codeUnit) =>
      codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;
  static bool _looksLikeStrippedLowSurrogate(int codeUnit) =>
      codeUnit >= 0x0C00 && codeUnit <= 0x0FFF;

  static int _codePointFromSurrogates(int high, int low) {
    return 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00);
  }
}
