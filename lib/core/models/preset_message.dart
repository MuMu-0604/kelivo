import 'package:uuid/uuid.dart';

class PresetMessage {
  final String id;
  final String role; // 'user' | 'assistant'
  final String content;

  PresetMessage({String? id, required this.role, required this.content})
    : id = id ?? const Uuid().v4();

  PresetMessage copyWith({String? id, String? role, String? content}) =>
      PresetMessage(
        id: id ?? this.id,
        role: role ?? this.role,
        content: content ?? this.content,
      );

  Map<String, dynamic> toJson() => {'id': id, 'role': role, 'content': content};

  static PresetMessage fromJson(Map<String, dynamic> json) => PresetMessage(
    id: (json['id'] as String?) ?? const Uuid().v4(),
    role: (json['role'] as String?) == 'assistant' ? 'assistant' : 'user',
    content: (json['content'] as String?) ?? '',
  );

  static List<PresetMessage> decodeList(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map(
            (e) => PresetMessage.fromJson(
              e.map((k, v) => MapEntry(k.toString(), v)),
            ),
          )
          .toList();
    }
    return const <PresetMessage>[];
  }

  static List<Map<String, dynamic>> encodeList(List<PresetMessage> list) =>
      list.map((e) => e.toJson()).toList();
}
