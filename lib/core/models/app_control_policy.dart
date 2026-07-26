class AppControlTargetPolicy {
  const AppControlTargetPolicy({
    this.enabled = true,
    this.approvalRequired = true,
  });

  final bool enabled;
  final bool approvalRequired;

  AppControlTargetPolicy copyWith({bool? enabled, bool? approvalRequired}) {
    return AppControlTargetPolicy(
      enabled: enabled ?? this.enabled,
      approvalRequired: approvalRequired ?? this.approvalRequired,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'approvalRequired': approvalRequired,
  };

  factory AppControlTargetPolicy.fromJson(Map<String, dynamic> json) {
    return AppControlTargetPolicy(
      enabled: json['enabled'] as bool? ?? true,
      approvalRequired: json['approvalRequired'] as bool? ?? true,
    );
  }
}

class AppControlPolicy {
  const AppControlPolicy({
    this.enabled = true,
    this.targets = const <String, AppControlTargetPolicy>{},
  });

  static const String currentAssistantSettings = 'current_assistant.settings';
  static const String currentAssistantSystemPrompt =
      'current_assistant.system_prompt';
  static const String currentAssistantMemory = 'current_assistant.memory';
  static const String currentAssistantSkills = 'current_assistant.skills';
  static const String currentAssistantLocalTools =
      'current_assistant.local_tools';
  static const String currentAssistantMcp = 'current_assistant.mcp';
  static const String quickPhrase = 'quick_phrase';
  static const String instructionInjection = 'instruction_injection';
  static const String worldBook = 'world_book';
  static const String mcpServer = 'mcp_server';
  static const String searchSettings = 'search_settings';
  static const String appBundle = 'app_bundle';
  static const String auditLog = 'audit_log';

  static const List<String> targetIds = <String>[
    currentAssistantSettings,
    currentAssistantSystemPrompt,
    currentAssistantMemory,
    currentAssistantSkills,
    currentAssistantLocalTools,
    currentAssistantMcp,
    quickPhrase,
    instructionInjection,
    worldBook,
    mcpServer,
    searchSettings,
    appBundle,
    auditLog,
  ];

  static const Set<String> forceApprovalTargets = <String>{
    currentAssistantSettings,
    currentAssistantSystemPrompt,
    instructionInjection,
    mcpServer,
    appBundle,
  };

  static const Set<String> forceApprovalOperations = <String>{
    'overwrite',
    'delete',
    'delete_entry',
    'import_json',
    'set_approval',
  };

  final bool enabled;
  final Map<String, AppControlTargetPolicy> targets;

  factory AppControlPolicy.safeDefault({bool enabled = false}) {
    return AppControlPolicy(enabled: enabled, targets: _defaultTargets());
  }

  factory AppControlPolicy.fullAccess({bool enabled = true}) {
    return AppControlPolicy(
      enabled: enabled,
      targets: {
        for (final id in targetIds)
          id: AppControlTargetPolicy(
            enabled: true,
            approvalRequired: id != quickPhrase && id != auditLog,
          ),
      },
    );
  }

  factory AppControlPolicy.fromJson(Map<String, dynamic>? json) {
    if (json == null) return AppControlPolicy.safeDefault();
    final rawTargets = json['targets'];
    final parsed = <String, AppControlTargetPolicy>{};
    if (rawTargets is Map) {
      rawTargets.forEach((key, value) {
        if (value is Map) {
          parsed[key.toString()] = AppControlTargetPolicy.fromJson(
            value.cast<String, dynamic>(),
          );
        }
      });
    }
    return AppControlPolicy(
      enabled: json['enabled'] as bool? ?? false,
      targets: _mergeWithDefaults(parsed),
    );
  }

  AppControlPolicy forRuntime({required bool legacyEnabled}) {
    final merged = _mergeWithDefaults(targets);
    return AppControlPolicy(enabled: legacyEnabled, targets: merged);
  }

  AppControlPolicy copyWith({
    bool? enabled,
    Map<String, AppControlTargetPolicy>? targets,
  }) {
    return AppControlPolicy(
      enabled: enabled ?? this.enabled,
      targets: targets ?? this.targets,
    );
  }

  AppControlPolicy setTargetEnabled(String target, bool value) {
    final merged = _mergeWithDefaults(targets);
    final current = merged[target] ?? const AppControlTargetPolicy();
    return copyWith(
      targets: {
        ...merged,
        target: current.copyWith(enabled: value),
      },
    );
  }

  AppControlPolicy setTargetApprovalRequired(String target, bool value) {
    final merged = _mergeWithDefaults(targets);
    final current = merged[target] ?? const AppControlTargetPolicy();
    return copyWith(
      targets: {
        ...merged,
        target: current.copyWith(approvalRequired: value),
      },
    );
  }

  bool isTargetEnabled(String target) {
    if (!enabled) return false;
    return (_mergeWithDefaults(targets)[target] ??
            const AppControlTargetPolicy())
        .enabled;
  }

  bool approvalRequiredFor(String target, String operation) {
    if (forceApprovalTargets.contains(target) ||
        forceApprovalOperations.contains(operation)) {
      return true;
    }
    return (_mergeWithDefaults(targets)[target] ??
            const AppControlTargetPolicy())
        .approvalRequired;
  }

  bool get approvalRequiredForUndo => enabled;

  int get enabledTargetCount =>
      _mergeWithDefaults(targets).values.where((p) => p.enabled).length;

  int get approvalRequiredTargetCount => _mergeWithDefaults(
    targets,
  ).values.where((p) => p.enabled && p.approvalRequired).length;

  List<String> get enabledTargets => _mergeWithDefaults(targets).entries
      .where((entry) => entry.value.enabled)
      .map((entry) => entry.key)
      .toList(growable: false);

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'targets': {
      for (final entry in _mergeWithDefaults(targets).entries)
        entry.key: entry.value.toJson(),
    },
  };

  static Map<String, AppControlTargetPolicy> _defaultTargets() {
    return {
      for (final id in targetIds)
        id: AppControlTargetPolicy(
          enabled: true,
          approvalRequired: id != quickPhrase && id != auditLog,
        ),
    };
  }

  static Map<String, AppControlTargetPolicy> _mergeWithDefaults(
    Map<String, AppControlTargetPolicy> values,
  ) {
    return {..._defaultTargets(), ...values};
  }
}
