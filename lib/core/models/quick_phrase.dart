class QuickPhrase {
  final String id;
  final String title;
  final String content;
  final bool isGlobal; // true = global, false = assistant-specific
  final String? assistantId; // null for global phrases

  const QuickPhrase({
    required this.id,
    required this.title,
    required this.content,
    this.isGlobal = true,
    this.assistantId,
  });

  QuickPhrase copyWith({
    String? id,
    String? title,
    String? content,
    bool? isGlobal,
    String? assistantId,
  }) {
    return QuickPhrase(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      isGlobal: isGlobal ?? this.isGlobal,
      assistantId: assistantId ?? this.assistantId,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'isGlobal': isGlobal,
    'assistantId': assistantId,
  };

  static QuickPhrase fromJson(Map<String, dynamic> json) => QuickPhrase(
    id: json['id'] as String,
    title: (json['title'] as String?) ?? '',
    content: (json['content'] as String?) ?? '',
    isGlobal: json['isGlobal'] as bool? ?? true,
    assistantId: json['assistantId'] as String?,
  );
}
