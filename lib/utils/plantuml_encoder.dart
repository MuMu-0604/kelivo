import 'dart:convert';
import 'package:archive/archive.dart';

// References https://plantuml.com/zh/text-encoding
class PlantUmlEncoder {
  static const String _mapping =
      "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_";

  static String encode(String text) {
    List<int> bytes = utf8.encode(text);
    // Use Deflate algorithm
    List<int> compressed = Deflate(bytes).getBytes();
    return _encode64(compressed);
  }

  static String _encode64(List<int> data) {
    StringBuffer r = StringBuffer();
    for (int i = 0; i < data.length; i += 3) {
      if (i + 2 == data.length) {
        r.write(_append3bytes(data[i], data[i + 1], 0).substring(0, 3));
      } else if (i + 1 == data.length) {
        r.write(_append3bytes(data[i], 0, 0).substring(0, 2));
      } else {
        r.write(_append3bytes(data[i], data[i + 1], data[i + 2]));
      }
    }
    return r.toString();
  }

  static String _append3bytes(int b1, int b2, int b3) {
    int c1 = b1 >> 2;
    int c2 = ((b1 & 0x3) << 4) | (b2 >> 4);
    int c3 = ((b2 & 0xF) << 2) | (b3 >> 6);
    int c4 = b3 & 0x3F;
    StringBuffer r = StringBuffer();
    r.write(_mapping[c1 & 0x3F]);
    r.write(_mapping[c2 & 0x3F]);
    r.write(_mapping[c3 & 0x3F]);
    r.write(_mapping[c4 & 0x3F]);
    return r.toString();
  }
}
