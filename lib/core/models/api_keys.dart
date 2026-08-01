import 'dart:math';

enum ApiKeyStatus { active, disabled, error, rateLimited }

class ApiKeyUsage {
  final int totalRequests;
  final int successfulRequests;
  final int failedRequests;
  final int consecutiveFailures;
  final int? lastUsed;

  const ApiKeyUsage({
    this.totalRequests = 0,
    this.successfulRequests = 0,
    this.failedRequests = 0,
    this.consecutiveFailures = 0,
    this.lastUsed,
  });

  ApiKeyUsage copyWith({
    int? totalRequests,
    int? successfulRequests,
    int? failedRequests,
    int? consecutiveFailures,
    int? lastUsed,
  }) => ApiKeyUsage(
    totalRequests: totalRequests ?? this.totalRequests,
    successfulRequests: successfulRequests ?? this.successfulRequests,
    failedRequests: failedRequests ?? this.failedRequests,
    consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
    lastUsed: lastUsed ?? this.lastUsed,
  );

  Map<String, dynamic> toJson() => {
    'totalRequests': totalRequests,
    'successfulRequests': successfulRequests,
    'failedRequests': failedRequests,
    'consecutiveFailures': consecutiveFailures,
    'lastUsed': lastUsed,
  };

  factory ApiKeyUsage.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ApiKeyUsage();
    return ApiKeyUsage(
      totalRequests: (json['totalRequests'] as int?) ?? 0,
      successfulRequests: (json['successfulRequests'] as int?) ?? 0,
      failedRequests: (json['failedRequests'] as int?) ?? 0,
      consecutiveFailures: (json['consecutiveFailures'] as int?) ?? 0,
      lastUsed: json['lastUsed'] as int?,
    );
  }
}

class ApiKeyConfig {
  final String id;
  final String key;
  final String? name;
  final bool isEnabled;
  final int priority; // 1-10, smaller means higher priority
  final int? maxRequestsPerMinute;
  final ApiKeyUsage usage;
  final ApiKeyStatus status;
  final String? lastError;
  final int createdAt;
  final int updatedAt;

  const ApiKeyConfig({
    required this.id,
    required this.key,
    this.name,
    this.isEnabled = true,
    this.priority = 5,
    this.maxRequestsPerMinute,
    this.usage = const ApiKeyUsage(),
    this.status = ApiKeyStatus.active,
    this.lastError,
    required this.createdAt,
    required this.updatedAt,
  });

  ApiKeyConfig copyWith({
    String? id,
    String? key,
    String? name,
    bool? isEnabled,
    int? priority,
    int? maxRequestsPerMinute,
    ApiKeyUsage? usage,
    ApiKeyStatus? status,
    String? lastError,
    int? createdAt,
    int? updatedAt,
  }) => ApiKeyConfig(
    id: id ?? this.id,
    key: key ?? this.key,
    name: name ?? this.name,
    isEnabled: isEnabled ?? this.isEnabled,
    priority: priority ?? this.priority,
    maxRequestsPerMinute: maxRequestsPerMinute ?? this.maxRequestsPerMinute,
    usage: usage ?? this.usage,
    status: status ?? this.status,
    lastError: lastError ?? this.lastError,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'key': key,
    'name': name,
    'isEnabled': isEnabled,
    'priority': priority,
    'maxRequestsPerMinute': maxRequestsPerMinute,
    'usage': usage.toJson(),
    'status': status.name,
    'lastError': lastError,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };

  factory ApiKeyConfig.fromJson(Map<String, dynamic> json) {
    final statusStr = (json['status'] as String?) ?? 'active';
    final st = ApiKeyStatus.values.firstWhere(
      (e) => e.name == statusStr,
      orElse: () => ApiKeyStatus.active,
    );
    return ApiKeyConfig(
      id: (json['id'] as String?) ?? _generateKeyId(),
      key: (json['key'] as String?) ?? '',
      name: json['name'] as String?,
      isEnabled: (json['isEnabled'] as bool?) ?? true,
      priority: (json['priority'] as int?) ?? 5,
      maxRequestsPerMinute: json['maxRequestsPerMinute'] as int?,
      usage: ApiKeyUsage.fromJson(json['usage'] as Map<String, dynamic>?),
      status: st,
      lastError: json['lastError'] as String?,
      createdAt:
          (json['createdAt'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
      updatedAt:
          (json['updatedAt'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  // Ensure high probability of uniqueness even under fast batch inserts
  static final Random _rng = Random();
  static int _ctr = 0;
  static String _generateKeyId() {
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final r = _rng.nextInt(0x7fffffff).toRadixString(36);
    // Monotonic counter to guard against same-timestamp collisions
    _ctr = (_ctr + 1) & 0x7fffffff;
    final c = _ctr.toRadixString(36);
    return 'key_${ts}_${r}_$c';
  }

  static ApiKeyConfig create(String key, {String? name, int priority = 5}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return ApiKeyConfig(
      id: _generateKeyId(),
      key: key,
      name: name,
      isEnabled: true,
      priority: priority,
      usage: const ApiKeyUsage(),
      status: ApiKeyStatus.active,
      createdAt: now,
      updatedAt: now,
    );
  }
}

enum LoadBalanceStrategy { roundRobin, priority, leastUsed, random }

class KeyManagementConfig {
  final LoadBalanceStrategy strategy;
  final int maxFailuresBeforeDisable;
  final int failureRecoveryTimeMinutes;
  final bool enableAutoRecovery;
  final int? roundRobinIndex; // optional persisted pointer

  const KeyManagementConfig({
    this.strategy = LoadBalanceStrategy.roundRobin,
    this.maxFailuresBeforeDisable = 3,
    this.failureRecoveryTimeMinutes = 5,
    this.enableAutoRecovery = true,
    this.roundRobinIndex,
  });

  KeyManagementConfig copyWith({
    LoadBalanceStrategy? strategy,
    int? maxFailuresBeforeDisable,
    int? failureRecoveryTimeMinutes,
    bool? enableAutoRecovery,
    int? roundRobinIndex,
  }) => KeyManagementConfig(
    strategy: strategy ?? this.strategy,
    maxFailuresBeforeDisable:
        maxFailuresBeforeDisable ?? this.maxFailuresBeforeDisable,
    failureRecoveryTimeMinutes:
        failureRecoveryTimeMinutes ?? this.failureRecoveryTimeMinutes,
    enableAutoRecovery: enableAutoRecovery ?? this.enableAutoRecovery,
    roundRobinIndex: roundRobinIndex ?? this.roundRobinIndex,
  );

  Map<String, dynamic> toJson() => {
    'strategy': strategy.name,
    'maxFailuresBeforeDisable': maxFailuresBeforeDisable,
    'failureRecoveryTimeMinutes': failureRecoveryTimeMinutes,
    'enableAutoRecovery': enableAutoRecovery,
    'roundRobinIndex': roundRobinIndex,
  };

  factory KeyManagementConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const KeyManagementConfig();
    final s = (json['strategy'] as String?) ?? 'roundRobin';
    final strat = LoadBalanceStrategy.values.firstWhere(
      (e) => e.name.toLowerCase() == s.toLowerCase(),
      orElse: () => LoadBalanceStrategy.roundRobin,
    );
    return KeyManagementConfig(
      strategy: strat,
      maxFailuresBeforeDisable: (json['maxFailuresBeforeDisable'] as int?) ?? 3,
      failureRecoveryTimeMinutes:
          (json['failureRecoveryTimeMinutes'] as int?) ?? 5,
      enableAutoRecovery: (json['enableAutoRecovery'] as bool?) ?? true,
      roundRobinIndex: json['roundRobinIndex'] as int?,
    );
  }
}
