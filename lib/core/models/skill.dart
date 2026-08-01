import 'dart:convert';

class SkillVersion {
  final String id;
  final String name;
  final String description;
  final String content;
  final List<String> triggerKeywords;
  final int priority;
  final DateTime createdAt;

  const SkillVersion({
    required this.id,
    required this.name,
    this.description = '',
    required this.content,
    this.triggerKeywords = const <String>[],
    this.priority = 0,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'content': content,
    'triggerKeywords': triggerKeywords,
    'priority': priority,
    'createdAt': createdAt.toIso8601String(),
  };

  factory SkillVersion.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return SkillVersion(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      content: (json['content'] as String?) ?? '',
      triggerKeywords:
          (json['triggerKeywords'] as List?)?.cast<String>() ??
          const <String>[],
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      createdAt: json['createdAt'] is String
          ? DateTime.tryParse(json['createdAt'] as String) ?? now
          : now,
    );
  }
}

class Skill {
  final String id;
  final String name;
  final String description;
  final String content;
  final bool enabled;
  final List<String> triggerKeywords;
  final int priority;
  final String? sourcePath;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<SkillVersion> versions;

  const Skill({
    required this.id,
    required this.name,
    this.description = '',
    required this.content,
    this.enabled = true,
    this.triggerKeywords = const <String>[],
    this.priority = 0,
    this.sourcePath,
    required this.createdAt,
    required this.updatedAt,
    this.versions = const <SkillVersion>[],
  });

  Skill copyWith({
    String? id,
    String? name,
    String? description,
    String? content,
    bool? enabled,
    List<String>? triggerKeywords,
    int? priority,
    String? sourcePath,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<SkillVersion>? versions,
    bool clearSourcePath = false,
  }) {
    return Skill(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      content: content ?? this.content,
      enabled: enabled ?? this.enabled,
      triggerKeywords: triggerKeywords ?? this.triggerKeywords,
      priority: priority ?? this.priority,
      sourcePath: clearSourcePath ? null : (sourcePath ?? this.sourcePath),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      versions: versions ?? this.versions,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'content': content,
    'enabled': enabled,
    'triggerKeywords': triggerKeywords,
    'priority': priority,
    'sourcePath': sourcePath,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'versions': versions.map((e) => e.toJson()).toList(),
  };

  factory Skill.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    DateTime parseDate(dynamic raw) {
      if (raw is String) return DateTime.tryParse(raw) ?? now;
      return now;
    }

    return Skill(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      content: (json['content'] as String?) ?? '',
      enabled: json['enabled'] as bool? ?? true,
      triggerKeywords:
          (json['triggerKeywords'] as List?)?.cast<String>() ??
          const <String>[],
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      sourcePath: json['sourcePath'] as String?,
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
      versions:
          (json['versions'] as List?)
              ?.whereType<Map>()
              .map((e) => SkillVersion.fromJson(e.cast<String, dynamic>()))
              .where((version) => version.id.isNotEmpty)
              .toList(growable: false) ??
          const <SkillVersion>[],
    );
  }

  static String encodeList(List<Skill> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());

  static List<Skill> decodeList(String raw) {
    try {
      final arr = jsonDecode(raw) as List<dynamic>;
      return [
        for (final e in arr)
          if (e is Map) Skill.fromJson(e.cast<String, dynamic>()),
      ];
    } catch (_) {
      return const <Skill>[];
    }
  }
}
