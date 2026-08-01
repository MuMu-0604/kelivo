import 'dart:convert';

class AssistantTag {
  final String id;
  final String name;

  const AssistantTag({required this.id, required this.name});

  AssistantTag copyWith({String? id, String? name}) =>
      AssistantTag(id: id ?? this.id, name: name ?? this.name);

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  static AssistantTag fromJson(Map<String, dynamic> json) => AssistantTag(
    id: (json['id'] ?? '').toString(),
    name: (json['name'] ?? '').toString(),
  );

  static String encodeList(List<AssistantTag> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());
  static List<AssistantTag> decodeList(String raw) {
    try {
      final arr = jsonDecode(raw) as List<dynamic>;
      return [
        for (final e in arr) AssistantTag.fromJson(e as Map<String, dynamic>),
      ];
    } catch (_) {
      return const <AssistantTag>[];
    }
  }
}
