import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mcp_client/mcp_client.dart' as mcp;
import '../services/mcp/in_memory_mcp_server.dart';
import '../services/mcp/kelivo_fetch/kelivo_fetch_server.dart';
import '../services/mcp/kelivo_files/kelivo_files_server.dart';
import '../services/mcp/kelivo_github/github_api_client.dart';
import '../services/mcp/kelivo_github/kelivo_github_server.dart';
import '../services/mcp/kelivo_images/kelivo_images_server.dart';
import '../services/mcp/stdio_command_resolver.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Transport type: SSE, Streamable HTTP, and STDIO (desktop-only).
enum McpTransportType { sse, http, stdio, inmemory }

/// Connection status for an MCP server.
enum McpStatus { idle, connecting, connected, error }

enum McpCallLogStatus { running, success, error }

class McpCallLogEntry {
  const McpCallLogEntry({
    required this.id,
    required this.serverId,
    required this.serverName,
    required this.toolName,
    required this.startedAt,
    required this.status,
    required this.argumentsPreview,
    this.finishedAt,
    this.durationMs,
    this.resultPreview,
    this.error,
    this.retried = false,
  });

  final String id;
  final String serverId;
  final String serverName;
  final String toolName;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final int? durationMs;
  final McpCallLogStatus status;
  final String argumentsPreview;
  final String? resultPreview;
  final String? error;
  final bool retried;

  McpCallLogEntry copyWith({
    DateTime? finishedAt,
    int? durationMs,
    McpCallLogStatus? status,
    String? resultPreview,
    String? error,
    bool? retried,
  }) => McpCallLogEntry(
    id: id,
    serverId: serverId,
    serverName: serverName,
    toolName: toolName,
    startedAt: startedAt,
    finishedAt: finishedAt ?? this.finishedAt,
    durationMs: durationMs ?? this.durationMs,
    status: status ?? this.status,
    argumentsPreview: argumentsPreview,
    resultPreview: resultPreview ?? this.resultPreview,
    error: error ?? this.error,
    retried: retried ?? this.retried,
  );
}

class McpParamSpec {
  final String name;
  final bool required;
  final String? type;
  final dynamic defaultValue;

  McpParamSpec({
    required this.name,
    required this.required,
    this.type,
    this.defaultValue,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'required': required,
    'type': type,
    'default': defaultValue,
  };

  factory McpParamSpec.fromJson(Map<String, dynamic> json) => McpParamSpec(
    name: json['name'] as String? ?? '',
    required: json['required'] as bool? ?? false,
    type: json['type'] as String?,
    defaultValue: json['default'],
  );
}

class McpToolConfig {
  final bool enabled;
  final String name;
  final String? description;
  final List<McpParamSpec> params;
  // Raw JSON schema for parameters, if provided by the server
  final Map<String, dynamic>? schema;

  /// Whether this tool requires user approval before execution.
  final bool needsApproval;

  McpToolConfig({
    required this.enabled,
    required this.name,
    this.description,
    this.params = const [],
    this.schema,
    this.needsApproval = false,
  });

  McpToolConfig copyWith({
    bool? enabled,
    String? name,
    String? description,
    List<McpParamSpec>? params,
    Map<String, dynamic>? schema,
    bool? needsApproval,
  }) => McpToolConfig(
    enabled: enabled ?? this.enabled,
    name: name ?? this.name,
    description: description ?? this.description,
    params: params ?? this.params,
    schema: schema ?? this.schema,
    needsApproval: needsApproval ?? this.needsApproval,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'name': name,
    'description': description,
    'params': params.map((e) => e.toJson()).toList(),
    if (schema != null) 'schema': schema,
    if (needsApproval) 'needsApproval': true,
  };

  factory McpToolConfig.fromJson(Map<String, dynamic> json) => McpToolConfig(
    enabled: json['enabled'] as bool? ?? true,
    name: json['name'] as String? ?? '',
    description: json['description'] as String?,
    params:
        (json['params'] as List?)
            ?.map(
              (e) => McpParamSpec.fromJson((e as Map).cast<String, dynamic>()),
            )
            .toList() ??
        const [],
    schema: (json['schema'] is Map)
        ? (json['schema'] as Map).cast<String, dynamic>()
        : null,
    needsApproval: json['needsApproval'] as bool? ?? false,
  );
}

class McpServerConfig {
  final String id; // stable id
  final bool enabled;
  final String name;
  final McpTransportType transport;
  // For SSE/HTTP
  final String url; // SSE endpoint or HTTP base URL
  final List<McpToolConfig> tools;
  final Map<String, String> headers; // custom HTTP headers
  // For STDIO (desktop-only)
  final String? command;
  final List<String> args;
  final Map<String, String> env;
  final String? workingDirectory;

  McpServerConfig({
    required this.id,
    required this.enabled,
    required this.name,
    required this.transport,
    this.url = '',
    this.tools = const [],
    this.headers = const {},
    this.command,
    this.args = const [],
    this.env = const {},
    this.workingDirectory,
  });

  McpServerConfig copyWith({
    String? id,
    bool? enabled,
    String? name,
    McpTransportType? transport,
    String? url,
    List<McpToolConfig>? tools,
    Map<String, String>? headers,
    String? command,
    List<String>? args,
    Map<String, String>? env,
    String? workingDirectory,
    bool clearWorkingDirectory = false,
  }) => McpServerConfig(
    id: id ?? this.id,
    enabled: enabled ?? this.enabled,
    name: name ?? this.name,
    transport: transport ?? this.transport,
    url: url ?? this.url,
    tools: tools ?? this.tools,
    headers: headers ?? this.headers,
    command: command ?? this.command,
    args: args ?? this.args,
    env: env ?? this.env,
    workingDirectory: clearWorkingDirectory
        ? null
        : (workingDirectory ?? this.workingDirectory),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'enabled': enabled,
    'name': name,
    'transport': transport.name,
    if (transport != McpTransportType.stdio &&
        transport != McpTransportType.inmemory)
      'url': url,
    'tools': tools.map((e) => e.toJson()).toList(),
    if (transport != McpTransportType.stdio &&
        transport != McpTransportType.inmemory)
      'headers': headers,
    if (transport == McpTransportType.stdio) 'command': command,
    if (transport == McpTransportType.stdio) 'args': args,
    if (transport == McpTransportType.stdio) 'env': env,
    if (transport == McpTransportType.stdio && workingDirectory != null)
      'workingDirectory': workingDirectory,
  };

  factory McpServerConfig.fromJson(Map<String, dynamic> json) {
    final tRaw = (json['transport'] as String?) ?? '';
    final t = tRaw == 'http'
        ? McpTransportType.http
        : (tRaw == 'stdio'
              ? McpTransportType.stdio
              : (tRaw == 'inmemory'
                    ? McpTransportType.inmemory
                    : McpTransportType.sse));
    final tools =
        (json['tools'] as List?)
            ?.map(
              (e) => McpToolConfig.fromJson((e as Map).cast<String, dynamic>()),
            )
            .toList() ??
        const <McpToolConfig>[];
    if (t == McpTransportType.stdio) {
      final argsAny = json['args'];
      final envAny = json['env'];
      return McpServerConfig(
        id: json['id'] as String? ?? const Uuid().v4(),
        enabled: json['enabled'] as bool? ?? true,
        name: json['name'] as String? ?? '',
        transport: McpTransportType.stdio,
        tools: tools,
        command: (json['command'] as String?)?.trim(),
        args: argsAny is List
            ? argsAny.map((e) => e.toString()).toList()
            : const <String>[],
        env: envAny is Map
            ? envAny.map((k, v) => MapEntry(k.toString(), v.toString()))
            : const <String, String>{},
        workingDirectory: (json['workingDirectory'] as String?)?.trim(),
      );
    } else if (t == McpTransportType.inmemory) {
      return McpServerConfig(
        id: json['id'] as String? ?? const Uuid().v4(),
        enabled: json['enabled'] as bool? ?? true,
        name: json['name'] as String? ?? '',
        transport: McpTransportType.inmemory,
        tools: tools,
      );
    } else {
      return McpServerConfig(
        id: json['id'] as String? ?? const Uuid().v4(),
        enabled: json['enabled'] as bool? ?? true,
        name: json['name'] as String? ?? '',
        transport: t,
        url: json['url'] as String? ?? '',
        tools: tools,
        headers:
            ((json['headers'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), v.toString()),
            )) ??
            const {},
      );
    }
  }
}

class McpProvider extends ChangeNotifier {
  static const String _prefsKey = 'mcp_servers_v1';
  static const String _prefsTimeoutKey = 'mcp_request_timeout_ms_v1';
  static const String _githubTokenPrefsKey = 'mcp_github_token_v1';
  static const String _builtinFetchId = 'kelivo_fetch';
  static const String _builtinFetchName = '@kelivo/fetch';
  static const String _builtinFilesId = 'kelivo_files';
  static const String _builtinFilesName = '@kelivo/files';
  static const String _builtinGithubId = 'kelivo_github';
  static const String _builtinGithubName = '@kelivo/github';
  static const String _builtinImagesId = 'kelivo_images';
  static const String _builtinImagesName = '@kelivo/images';
  static const Set<String> _builtinFileWriteToolNames = {
    'kelivo_create_directory',
    'kelivo_create_text_file',
    'kelivo_write_text_file',
    'kelivo_write_file_base64',
    'kelivo_append_text_file',
    'kelivo_delete_file',
    'kelivo_delete_files',
    'kelivo_move_file',
    'kelivo_copy_file',
    'kelivo_zip_files',
    'kelivo_unzip_file',
  };
  static const Set<String> _builtinGithubWriteToolNames = {
    'github_repository_write',
    'github_issue_write',
    'github_pull_request_write',
    'github_release_write',
    'github_actions_write',
    'github_secrets_write',
    'github_create_branch',
    'github_create_or_update_file',
    'github_delete_file',
    'github_create_issue',
    'github_update_issue',
    'github_create_issue_comment',
    'github_create_pull_request',
    'github_create_repository',
    'github_update_repository',
    'github_delete_repository',
    'github_fork_repository',
    'github_update_pull_request',
    'github_create_pr_review',
    'github_create_pr_review_comment',
    'github_merge_pull_request',
    'github_delete_branch',
    'github_create_release',
    'github_update_release',
    'github_delete_release',
    'github_dispatch_workflow',
    'github_rerun_workflow_run',
    'github_cancel_workflow_run',
    'github_put_repo_secret',
    'github_delete_repo_secret',
    'github_create_or_update_repo_variable',
    'github_delete_repo_variable',
  };
  static const int _maxCallLogEntries = 80;

  final Map<String, mcp.Client> _clients = {};
  final Map<String, McpStatus> _status = {}; // id -> status
  final Map<String, String> _errors = {}; // id -> last error
  List<McpServerConfig> _servers = [];
  // Reconnect bookkeeping to avoid duplicate concurrent retries
  final Set<String> _reconnecting = <String>{};
  // Heartbeat timers for live-connection health checks
  final Map<String, Timer> _heartbeats = <String, Timer>{};
  final List<McpCallLogEntry> _callLogs = <McpCallLogEntry>[];
  Duration _requestTimeout = const Duration(seconds: 30);
  String _githubToken = '';
  bool _disposed = false;
  final McpStdioCommandResolver _stdioCommandResolver =
      McpStdioCommandResolver();

  McpProvider() {
    _load();
  }

  List<McpServerConfig> get servers => List.unmodifiable(_servers);
  McpStatus statusFor(String id) => _status[id] ?? McpStatus.idle;
  String? errorFor(String id) => _errors[id];
  bool get hasAnyEnabled => _servers.any((s) => s.enabled);
  bool isConnected(String id) =>
      _clients.containsKey(id) && statusFor(id) == McpStatus.connected;
  List<McpServerConfig> get connectedServers => _servers
      .where((s) => statusFor(s.id) == McpStatus.connected)
      .toList(growable: false);
  Duration get requestTimeout => _requestTimeout;
  int get requestTimeoutSeconds => _requestTimeout.inSeconds;
  List<McpCallLogEntry> get callLogs => List.unmodifiable(_callLogs);
  bool get hasCallLogs => _callLogs.isNotEmpty;
  String get githubToken => _githubToken;
  bool get hasGithubToken => _githubToken.trim().isNotEmpty;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final timeoutMs = prefs.getInt(_prefsTimeoutKey);
    if (timeoutMs != null && timeoutMs > 0) {
      _requestTimeout = Duration(milliseconds: timeoutMs);
    }
    _githubToken = prefs.getString(_githubTokenPrefsKey)?.trim() ?? '';
    final raw = prefs.getString(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = (jsonDecode(raw) as List)
            .map(
              (e) =>
                  McpServerConfig.fromJson((e as Map).cast<String, dynamic>()),
            )
            .toList();
        _servers = list;
      } catch (_) {}
    }
    _ensureBuiltinServersPresent();
    // initialize statuses
    for (final s in _servers) {
      _status[s.id] = McpStatus.idle;
      _errors.remove(s.id);
    }
    notifyListeners();

    // Auto-connect enabled servers. Keep file access opt-in so app startup stays
    // identical to the original built-in fetch behavior until the user enables it.
    for (final s in _autoConnectServers()) {
      // fire and forget
      unawaited(connect(s.id));
    }
  }

  void _ensureBuiltinServersPresent() {
    final next = List<McpServerConfig>.of(_servers);
    if (!_hasBuiltinServer(_builtinFetchId, _builtinFetchName)) {
      next.add(_builtinServer(_builtinFetchId, _builtinFetchName));
    }
    if (!_hasBuiltinServer(_builtinFilesId, _builtinFilesName)) {
      next.add(
        _builtinServer(_builtinFilesId, _builtinFilesName, enabled: false),
      );
    }
    if (!_hasBuiltinServer(_builtinGithubId, _builtinGithubName)) {
      next.add(
        _builtinServer(_builtinGithubId, _builtinGithubName, enabled: false),
      );
    }
    if (!_hasBuiltinServer(_builtinImagesId, _builtinImagesName)) {
      next.add(
        _builtinServer(_builtinImagesId, _builtinImagesName, enabled: false),
      );
    }
    _servers = next;
  }

  Iterable<McpServerConfig> _autoConnectServers() {
    return _servers.where(
      (s) =>
          s.enabled && !_isBuiltinFilesServer(s) && !_isBuiltinImagesServer(s),
    );
  }

  bool _hasBuiltinServer(String id, String name) {
    return _servers.any(
      (s) =>
          s.transport == McpTransportType.inmemory &&
          (s.id == id || s.name == name),
    );
  }

  McpServerConfig _builtinServer(
    String id,
    String name, {
    bool enabled = true,
  }) {
    return McpServerConfig(
      id: id,
      enabled: enabled,
      name: name,
      transport: McpTransportType.inmemory,
      tools: const <McpToolConfig>[],
    );
  }

  bool _isBuiltinFilesServer(McpServerConfig server) {
    return server.transport == McpTransportType.inmemory &&
        (server.id == _builtinFilesId || server.name == _builtinFilesName);
  }

  bool _isBuiltinImagesServer(McpServerConfig server) {
    return server.transport == McpTransportType.inmemory &&
        (server.id == _builtinImagesId || server.name == _builtinImagesName);
  }

  bool _isBuiltinGithubServer(McpServerConfig server) {
    return server.transport == McpTransportType.inmemory &&
        (server.id == _builtinGithubId || server.name == _builtinGithubName);
  }

  bool isBuiltinServer(McpServerConfig server) {
    return _isBuiltinFetchServer(server) ||
        _isBuiltinFilesServer(server) ||
        _isBuiltinGithubServer(server) ||
        _isBuiltinImagesServer(server);
  }

  bool isBuiltinGithubServer(McpServerConfig server) {
    return _isBuiltinGithubServer(server);
  }

  bool _isBuiltinFetchServer(McpServerConfig server) {
    return server.transport == McpTransportType.inmemory &&
        (server.id == _builtinFetchId || server.name == _builtinFetchName);
  }

  KelivoInMemoryMcpServerEngine _createBuiltinEngine(McpServerConfig server) {
    if (_isBuiltinFilesServer(server)) return KelivoFilesMcpServerEngine();
    if (_isBuiltinImagesServer(server)) return KelivoImagesMcpServerEngine();
    if (_isBuiltinGithubServer(server)) {
      return KelivoGithubMcpServerEngine(
        client: GitHubApiClient(accessTokenProvider: () async => _githubToken),
      );
    }
    return KelivoFetchMcpServerEngine();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_servers.map((e) => e.toJson()).toList()),
    );
    await prefs.setInt(_prefsTimeoutKey, _requestTimeout.inMilliseconds);
  }

  Future<void> _persistTimeout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsTimeoutKey, _requestTimeout.inMilliseconds);
  }

  Future<void> updateGithubToken(String token) async {
    final normalized = token.trim();
    if (normalized == _githubToken) return;
    _githubToken = normalized;
    final prefs = await SharedPreferences.getInstance();
    if (normalized.isEmpty) {
      await prefs.remove(_githubTokenPrefsKey);
    } else {
      await prefs.setString(_githubTokenPrefsKey, normalized);
    }
    notifyListeners();
    for (final server in _servers) {
      if (_isBuiltinGithubServer(server) && server.enabled) {
        unawaited(reconnect(server.id));
        break;
      }
    }
  }

  /// Export current MCP servers as a user-friendly JSON structure.
  ///
  /// Shape:
  /// {
  ///   "mcpServers": {
  ///     "serverId": {
  ///       "name": "...",
  ///       "type": "streamableHttp" | "sse",
  ///       "description": "",
  ///       "isActive": true/false,
  ///       "baseUrl": "...",
  ///       "headers": { ... }
  ///     },
  ///     ...
  ///   }
  /// }
  String exportServersAsUiJson() {
    // On mobile, skip stdio entries in exported JSON.
    final isDesktop = _isDesktopPlatform();
    final map = <String, dynamic>{
      'mcpServers': {
        for (final s in _servers)
          if (s.transport != McpTransportType.stdio || isDesktop)
            s.id: {
              'name': s.name,
              if (s.transport == McpTransportType.http)
                'type': 'streamableHttp',
              if (s.transport == McpTransportType.sse) 'type': 'sse',
              if (s.transport == McpTransportType.inmemory) 'type': 'inmemory',
              'description': '',
              'isActive': s.enabled,
              if (s.transport != McpTransportType.stdio &&
                  s.transport != McpTransportType.inmemory)
                'baseUrl': s.url,
              if (s.transport != McpTransportType.stdio &&
                  s.transport != McpTransportType.inmemory &&
                  s.headers.isNotEmpty)
                'headers': s.headers,
              // For stdio, include an optional type for compatibility
              if (s.transport == McpTransportType.stdio) 'type': 'stdio',
              // Include command/args/env
              if (s.transport == McpTransportType.stdio &&
                  (s.command ?? '').isNotEmpty)
                'command': s.command,
              if (s.transport == McpTransportType.stdio && s.args.isNotEmpty)
                'args': s.args,
              if (s.transport == McpTransportType.stdio && s.env.isNotEmpty)
                'env': s.env,
              if (s.transport == McpTransportType.stdio)
                ...() {
                  final reg =
                      s.env['NPM_CONFIG_REGISTRY'] ??
                      s.env['npm_config_registry'];
                  return reg != null && reg.isNotEmpty
                      ? {'registryUrl': reg}
                      : <String, dynamic>{};
                }(),
              if (s.transport == McpTransportType.stdio &&
                  (s.workingDirectory ?? '').isNotEmpty)
                'workingDirectory': s.workingDirectory,
            },
      },
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// Replace all MCP servers from a JSON string.
  /// Accepts either the UI JSON (with top-level `mcpServers`) or the internal list format.
  Future<void> replaceAllFromJson(String rawJson) async {
    dynamic data;
    try {
      data = jsonDecode(rawJson);
    } catch (e) {
      throw FormatException('Invalid JSON: ${e.toString()}');
    }

    List<McpServerConfig> next = [];
    try {
      Map<String, dynamic>? serversFromMap;
      if (data is Map && data.containsKey('mcpServers')) {
        serversFromMap = (data['mcpServers'] as Map).cast<String, dynamic>();
      } else if (data is Map && data.isNotEmpty) {
        // Allow raw map format: { id: { ... } }
        // Heuristically treat it as mcpServers format when values are maps.
        final ok = data.values.every((v) => v is Map);
        if (ok) serversFromMap = data.cast<String, dynamic>();
      }

      if (serversFromMap != null) {
        final isDesktop = _isDesktopPlatform();
        final builtinEnabledById = <String, bool>{};
        bool legacyBuiltinSeen = false;
        bool legacyBuiltinEnabled = true;
        serversFromMap.forEach((id, cfgAny) {
          if (cfgAny is! Map) return;
          final cfg = cfgAny.cast<String, dynamic>();
          final typeLower = (cfg['type'] ?? '').toString().toLowerCase();
          if (typeLower == 'inmemory') {
            final enabled = (cfg['isActive'] as bool?) ?? true;
            final name = (cfg['name'] as String?)?.trim();
            if (id == _builtinFilesId || name == _builtinFilesName) {
              builtinEnabledById[_builtinFilesId] = enabled;
            } else if (id == _builtinGithubId || name == _builtinGithubName) {
              builtinEnabledById[_builtinGithubId] = enabled;
            } else if (id == _builtinImagesId || name == _builtinImagesName) {
              builtinEnabledById[_builtinImagesId] = enabled;
            } else if (id == _builtinFetchId || name == _builtinFetchName) {
              builtinEnabledById[_builtinFetchId] = enabled;
            } else {
              legacyBuiltinSeen = true;
              legacyBuiltinEnabled = enabled;
            }
            return;
          }
          final hasStdioShape =
              cfg.containsKey('command') ||
              cfg.containsKey('args') ||
              cfg.containsKey('env') ||
              (cfg['type']?.toString().toLowerCase() == 'stdio');
          if (hasStdioShape) {
            if (!isDesktop) {
              // Mobile: skip stdio entries entirely
              return;
            }
            final enabled = (cfg['isActive'] as bool?) ?? true;
            final name = (cfg['name'] as String?)?.trim();
            final cmd = (cfg['command'] as String?)?.trim();
            if (cmd == null || cmd.isEmpty) {
              // invalid stdio entry without command
              return;
            }
            final argsAny = cfg['args'];
            final envAny = cfg['env'];
            final wd = (cfg['workingDirectory'] as String?)?.trim();
            final registryUrl = (cfg['registryUrl'] as String?)?.trim();
            Map<String, String> env = envAny is Map
                ? envAny.map((k, v) => MapEntry(k.toString(), v.toString()))
                : const <String, String>{};
            if ((registryUrl != null) && registryUrl.isNotEmpty) {
              if (!env.containsKey('NPM_CONFIG_REGISTRY') &&
                  !env.containsKey('npm_config_registry')) {
                env = {...env, 'NPM_CONFIG_REGISTRY': registryUrl};
              }
            }
            next.add(
              McpServerConfig(
                id: id,
                enabled: enabled,
                name: (name == null || name.isEmpty) ? id : name,
                transport: McpTransportType.stdio,
                command: cmd,
                args: argsAny is List
                    ? argsAny.map((e) => e.toString()).toList()
                    : const <String>[],
                env: env,
                workingDirectory: (wd != null && wd.isNotEmpty) ? wd : null,
              ),
            );
            return;
          }

          // SSE/HTTP branch using legacy fields
          final typeRaw = (cfg['type'] ?? '').toString().toLowerCase();
          final transport = (typeRaw.contains('http'))
              ? McpTransportType.http
              : McpTransportType.sse;
          final enabled = (cfg['isActive'] as bool?) ?? true;
          final name = (cfg['name'] as String?)?.trim();
          final url = (cfg['baseUrl'] as String?)?.trim();
          final headersAny = cfg['headers'];
          Map<String, String> headers = const {};
          if (headersAny is Map) {
            headers = headersAny.map(
              (k, v) => MapEntry(k.toString(), v.toString()),
            );
          }
          if ((url ?? '').isEmpty) {
            // Skip invalid entries with empty URL
            return;
          }
          next.add(
            McpServerConfig(
              id: id,
              enabled: enabled,
              name: (name == null || name.isEmpty) ? id : name,
              transport: transport,
              url: url!,
              headers: headers,
            ),
          );
        });
        if (builtinEnabledById.isNotEmpty || legacyBuiltinSeen) {
          next.add(
            _builtinServer(_builtinFetchId, _builtinFetchName).copyWith(
              enabled:
                  builtinEnabledById[_builtinFetchId] ?? legacyBuiltinEnabled,
            ),
          );
          next.add(
            _builtinServer(
              _builtinFilesId,
              _builtinFilesName,
              enabled: false,
            ).copyWith(enabled: builtinEnabledById[_builtinFilesId] ?? false),
          );
          next.add(
            _builtinServer(
              _builtinGithubId,
              _builtinGithubName,
              enabled: false,
            ).copyWith(enabled: builtinEnabledById[_builtinGithubId] ?? false),
          );
          next.add(
            _builtinServer(
              _builtinImagesId,
              _builtinImagesName,
              enabled: false,
            ).copyWith(enabled: builtinEnabledById[_builtinImagesId] ?? false),
          );
        }
      } else if (data is List) {
        // Attempt to parse internal list format. Be tolerant to transport string variants.
        for (final item in data) {
          if (item is! Map) continue;
          final m = item.cast<String, dynamic>();
          final t = (m['transport'] ?? '').toString().toLowerCase();
          if (t == 'streamablehttp' || t.contains('http')) {
            m['transport'] = 'http';
          } else if (t == 'sse') {
            m['transport'] = 'sse';
          } else if (t == 'stdio') {
            m['transport'] = 'stdio';
          }
          try {
            final s = McpServerConfig.fromJson(m);
            if (s.transport != McpTransportType.stdio &&
                s.transport != McpTransportType.inmemory &&
                s.url.trim().isEmpty) {
              continue;
            }
            next.add(s);
          } catch (_) {}
        }
      } else if (data is Map && data.containsKey('servers')) {
        final list = data['servers'];
        if (list is List) {
          for (final item in list) {
            if (item is! Map) continue;
            final m = item.cast<String, dynamic>();
            final t = (m['transport'] ?? '').toString().toLowerCase();
            if (t == 'streamablehttp' || t.contains('http')) {
              m['transport'] = 'http';
            } else if (t == 'sse') {
              m['transport'] = 'sse';
            } else if (t == 'stdio') {
              m['transport'] = 'stdio';
            }
            try {
              final s = McpServerConfig.fromJson(m);
              if (s.transport != McpTransportType.stdio &&
                  s.transport != McpTransportType.inmemory &&
                  s.url.trim().isEmpty) {
                continue;
              }
              next.add(s);
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      throw FormatException('Unrecognized or invalid MCP JSON');
    }

    if (next.isEmpty) {
      throw FormatException('No valid MCP servers found in JSON');
    }

    // Disconnect all current
    for (final s in _servers) {
      try {
        await disconnect(s.id);
      } catch (_) {}
    }

    // Replace and reset statuses
    _servers = next;
    _status.clear();
    _errors.clear();
    for (final s in _servers) {
      _status[s.id] = McpStatus.idle;
    }

    await _persist();
    notifyListeners();

    // Auto-connect enabled servers
    for (final s in _autoConnectServers()) {
      // fire and forget
      unawaited(connect(s.id));
    }
  }

  McpServerConfig? getById(String id) {
    for (final s in _servers) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<String> addServer({
    required bool enabled,
    required String name,
    required McpTransportType transport,
    String url = '',
    Map<String, String> headers = const {},
    String? command,
    List<String> args = const <String>[],
    Map<String, String> env = const <String, String>{},
    String? workingDirectory,
  }) async {
    final id = const Uuid().v4();
    final cfg = McpServerConfig(
      id: id,
      enabled: enabled,
      name: name.trim().isEmpty ? 'MCP' : name.trim(),
      transport: transport,
      url: url.trim(),
      headers: headers,
      command: command?.trim(),
      args: args,
      env: env,
      workingDirectory: (workingDirectory?.trim().isNotEmpty ?? false)
          ? workingDirectory!.trim()
          : null,
    );
    _servers = [..._servers, cfg];
    _status[id] = McpStatus.idle;
    await _persist();
    notifyListeners();
    if (enabled) {
      unawaited(connect(id));
    }
    return id;
  }

  Future<void> updateServer(McpServerConfig updated) async {
    final idx = _servers.indexWhere((e) => e.id == updated.id);
    if (idx < 0) return;
    _servers = List<McpServerConfig>.of(_servers)..[idx] = updated;
    await _persist();
    notifyListeners();
    if (!updated.enabled) {
      await disconnect(updated.id);
    } else {
      // Always reconnect after saving to apply changes (url/transport/name)
      await disconnect(updated.id);
      unawaited(connect(updated.id));
    }
  }

  Future<void> removeServer(String id) async {
    final current = getById(id);
    if (current != null && isBuiltinServer(current)) return;
    await disconnect(id);
    _servers = _servers.where((e) => e.id != id).toList(growable: false);
    _status.remove(id);
    await _persist();
    notifyListeners();
  }

  Future<void> reorderServers(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    if (oldIndex < 0 || oldIndex >= _servers.length) return;
    if (newIndex < 0 || newIndex >= _servers.length) return;
    final moved = _servers.removeAt(oldIndex);
    _servers.insert(newIndex, moved);
    notifyListeners();
    await _persist();
  }

  Future<void> setToolEnabled(
    String serverId,
    String toolName,
    bool enabled,
  ) async {
    final idx = _servers.indexWhere((e) => e.id == serverId);
    if (idx < 0) return;
    final server = _servers[idx];
    final tools = server.tools
        .map((t) => t.name == toolName ? t.copyWith(enabled: enabled) : t)
        .toList();
    _servers[idx] = server.copyWith(tools: tools);
    await _persist();
    notifyListeners();
  }

  /// Set whether a tool requires user approval before execution.
  Future<void> setToolNeedsApproval(
    String serverId,
    String toolName,
    bool needsApproval,
  ) async {
    final idx = _servers.indexWhere((e) => e.id == serverId);
    if (idx < 0) return;
    final server = _servers[idx];
    final tools = server.tools
        .map(
          (t) =>
              t.name == toolName ? t.copyWith(needsApproval: needsApproval) : t,
        )
        .toList();
    _servers[idx] = server.copyWith(tools: tools);
    await _persist();
    notifyListeners();
  }

  /// Check if a tool (by name) requires approval across all connected servers.
  /// Conservative: returns true if ANY connected server marks the tool as needing approval.
  bool toolNeedsApproval(String toolName) {
    for (final s in _servers) {
      if (statusFor(s.id) != McpStatus.connected) continue;
      if (!s.enabled) continue;
      for (final t in s.tools) {
        if (t.name == toolName && t.enabled && t.needsApproval) return true;
      }
    }
    return false;
  }

  void clearCallLogs() {
    _callLogs.clear();
    notifyListeners();
  }

  String _beginCallLog({
    required String serverId,
    required String toolName,
    required Map<String, dynamic> arguments,
  }) {
    final server = getById(serverId);
    final id = '${toolName}_${DateTime.now().microsecondsSinceEpoch}';
    _callLogs.insert(
      0,
      McpCallLogEntry(
        id: id,
        serverId: serverId,
        serverName: server?.name ?? serverId,
        toolName: toolName,
        startedAt: DateTime.now(),
        status: McpCallLogStatus.running,
        argumentsPreview: _previewJson(arguments),
      ),
    );
    if (_callLogs.length > _maxCallLogEntries) {
      _callLogs.removeRange(_maxCallLogEntries, _callLogs.length);
    }
    notifyListeners();
    return id;
  }

  void _finishCallLog(
    String id, {
    required McpCallLogStatus status,
    String? resultPreview,
    String? error,
    bool retried = false,
  }) {
    final idx = _callLogs.indexWhere((entry) => entry.id == id);
    if (idx < 0) return;
    final now = DateTime.now();
    final current = _callLogs[idx];
    _callLogs[idx] = current.copyWith(
      finishedAt: now,
      durationMs: now.difference(current.startedAt).inMilliseconds,
      status: status,
      resultPreview: resultPreview,
      error: error,
      retried: retried,
    );
    notifyListeners();
  }

  static String _previewJson(dynamic value, {int maxLength = 1200}) {
    String text;
    try {
      text = const JsonEncoder.withIndent(
        '  ',
      ).convert(_redactSensitive(value));
    } catch (_) {
      text = value.toString();
    }
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}…';
  }

  static dynamic _redactSensitive(dynamic value) {
    if (value is List) return value.map(_redactSensitive).toList();
    if (value is! Map) return value;
    return value.map((key, entryValue) {
      final keyText = key.toString().toLowerCase();
      final sensitive =
          keyText.contains('key') ||
          keyText.contains('token') ||
          keyText.contains('secret') ||
          keyText.contains('password') ||
          keyText.contains('authorization') ||
          keyText.contains('cookie');
      return MapEntry(
        key.toString(),
        sensitive ? '***' : _redactSensitive(entryValue),
      );
    });
  }

  static String _previewCallToolResult(mcp.CallToolResult result) {
    final buf = StringBuffer();
    for (final content in result.content.take(3)) {
      try {
        if (content is mcp.TextContent) {
          final text = content.text.trim();
          if (text.isNotEmpty) buf.writeln(text);
          continue;
        }
        if (content is mcp.ImageContent) {
          buf.writeln('[image ${content.mimeType}]');
          continue;
        }
        if (content is mcp.ResourceContent) {
          buf.writeln('[resource ${content.uri}]');
          continue;
        }
        buf.writeln(content.toString());
      } catch (_) {}
    }
    final text = buf.toString().trim();
    if (text.isEmpty) return '(empty result)';
    return text.length <= 1600 ? text : '${text.substring(0, 1600)}…';
  }

  Future<void> connect(String id) async {
    if (_disposed) return;
    final server = _servers.firstWhere(
      (e) => e.id == id,
      orElse: () => throw StateError('Server not found'),
    );
    // If already connected, try a ping by listing tools quickly; else return
    if (_clients.containsKey(id)) {
      // Already connected; update status just in case
      _status[id] = McpStatus.connected;
      _errors.remove(id);
      notifyListeners();
      return;
    }
    _status[id] = McpStatus.connecting;
    _errors.remove(id);
    notifyListeners();

    try {
      // Log connect intent and parameters
      // debugPrint('[MCP/Connect] id=$id name=${server.name} transport=${server.transport.name}');
      // debugPrint('[MCP/Connect] url=${server.url}');
      // if (server.headers.isNotEmpty) {
      //   debugPrint('[MCP/Headers] ${server.headers.length} headers:');
      //   server.headers.forEach((k, v) {
      //     final masked = _maskIfSensitive(k, v);
      //     debugPrint('  - $k: $masked');
      //   });
      // } else {
      //   debugPrint('[MCP/Headers] (none)');
      // }

      final clientConfig = mcp.McpClient.simpleConfig(
        name: 'Kelivo MCP',
        version: '1.0.0',
        // Turn on library-internal verbose logs
        enableDebugLogging: false,
        requestTimeout: _requestTimeout,
      );

      // In-memory builtin server path
      if (server.transport == McpTransportType.inmemory) {
        final engine = _createBuiltinEngine(server);
        final transport = KelivoInMemoryClientTransport(engine);
        final client = mcp.McpClient.createClient(clientConfig);
        await client.connect(transport);
        if (_disposed) {
          try {
            client.disconnect();
          } catch (_) {}
          return;
        }
        _clients[id] = client;
        _status[id] = McpStatus.connected;
        _errors.remove(id);
        notifyListeners();
        await refreshTools(id);
        _startHeartbeat(id);
        return;
      }

      final mergedHeaders = <String, String>{...server.headers};
      final transportConfig = await () async {
        if (server.transport == McpTransportType.sse) {
          return mcp.TransportConfig.sse(
            serverUrl: server.url,
            headers: mergedHeaders.isEmpty ? null : mergedHeaders,
          );
        } else if (server.transport == McpTransportType.http) {
          return mcp.TransportConfig.streamableHttp(
            baseUrl: server.url,
            headers: mergedHeaders.isEmpty ? null : mergedHeaders,
            timeout: _requestTimeout,
          );
        } else {
          // STDIO; only supported on desktop
          if (!_isDesktopPlatform()) {
            throw StateError('STDIO transport not supported on this platform');
          }
          final cmd = server.command;
          if (cmd == null || cmd.isEmpty) {
            throw StateError('STDIO command is empty');
          }
          final mergedEnv = await _stdioCommandResolver
              .resolveEnvironmentWithPath(server.env);
          final commandExists = await _stdioCommandResolver.commandExists(
            cmd,
            mergedEnv,
          );
          if (!commandExists) {
            throw StateError(
              'Command "$cmd" not found in PATH. '
              'Ensure the command is installed and accessible.',
            );
          }
          return mcp.TransportConfig.stdio(
            command: cmd,
            arguments: server.args,
            workingDirectory: server.workingDirectory,
            environment: mergedEnv.isEmpty ? null : mergedEnv,
          );
        }
      }();

      // debugPrint('[MCP/Connect] creating client (enableDebugLogging=true) ...');
      final clientResult = await mcp.McpClient.createAndConnect(
        config: clientConfig,
        transportConfig: transportConfig,
      );

      final client = clientResult.fold((c) => c, (err) => throw err);
      if (_disposed) {
        try {
          client.disconnect();
        } catch (_) {}
        return;
      }
      _clients[id] = client;
      _status[id] = McpStatus.connected;
      _errors.remove(id);
      // debugPrint('[MCP/Connected] id=$id (${server.name})');
      notifyListeners();

      // Try to refresh tools once connected
      // debugPrint('[MCP/Tools] refreshing tools for id=$id ...');
      await refreshTools(id);
      // debugPrint('[MCP/Tools] refresh done for id=$id');

      // Start/refresh heartbeat for this connection
      if (!_disposed) _startHeartbeat(id);
    } catch (e) {
      if (_disposed) return;
      // debugPrint('[MCP/Error] connect failed for id=$id (${server.name})');
      // _logMcpException('connect', serverId: id, error: e, stack: st);
      _status[id] = McpStatus.error;
      _errors[id] = e.toString();
      notifyListeners();
    }
  }

  Future<void> updateRequestTimeout(
    Duration duration, {
    bool reconnectActive = true,
  }) async {
    if (duration.inMilliseconds <= 0) return;
    if (duration == _requestTimeout) return;
    _requestTimeout = duration;
    await _persistTimeout();
    notifyListeners();
    if (reconnectActive) {
      for (final id in _clients.keys.toList()) {
        if (_servers.any((s) => s.id == id && s.enabled)) {
          unawaited(reconnect(id));
        }
      }
    }
  }

  Future<void> disconnect(String id) async {
    final client = _clients.remove(id);
    try {
      // debugPrint('[MCP/Disconnect] id=$id ...');
      client?.disconnect();
      // debugPrint('[MCP/Disconnect] id=$id done');
    } catch (e) {
      // debugPrint('[MCP/Error] disconnect failed for id=$id');
      // _logMcpException('disconnect', serverId: id, error: e, stack: st);
    }
    _status[id] = McpStatus.idle;
    _errors.remove(id);
    _stopHeartbeat(id);
    notifyListeners();
  }

  Future<void> reconnect(String id) async {
    await disconnect(id);
    await connect(id);
  }

  Future<void> _reconnectWithBackoff(String id, {int maxAttempts = 3}) async {
    if (_reconnecting.contains(id)) return;
    _reconnecting.add(id);
    try {
      for (int attempt = 1; attempt <= maxAttempts; attempt++) {
        await reconnect(id);
        if (isConnected(id)) return;
        // progressive backoff: 600ms, 1200ms, 2400ms
        final delayMs = 600 * (1 << (attempt - 1));
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    } finally {
      _reconnecting.remove(id);
    }
  }

  void _startHeartbeat(
    String id, {
    Duration interval = const Duration(seconds: 12),
  }) {
    _stopHeartbeat(id);
    _heartbeats[id] = Timer.periodic(interval, (t) async {
      // Heartbeat only when we think we're connected
      if (!isConnected(id)) return;
      final client = _clients[id];
      if (client == null) return;
      try {
        // A lightweight call to verify liveness
        // listTools is relatively cheap and available
        final fut = client.listTools();
        // Add a soft timeout to avoid piling up
        await fut.timeout(const Duration(seconds: 6));
      } catch (e) {
        // debugPrint('[MCP/Heartbeat] liveness check failed id=$id');
        // Consider connection lost; mark error and try auto-reconnect
        _status[id] = McpStatus.error;
        _errors[id] = e.toString();
        notifyListeners();
        await _reconnectWithBackoff(id, maxAttempts: 3);
        // If reconnected, restart heartbeat (connect() also starts it)
        if (!isConnected(id)) {
          // keep error state; next heartbeat tick will be a no-op
        }
      }
    });
  }

  void _stopHeartbeat(String id) {
    _heartbeats.remove(id)?.cancel();
  }

  McpToolConfig? _toolConfig(String serverId, String toolName) {
    final idx = _servers.indexWhere((e) => e.id == serverId);
    if (idx < 0) return null;
    final s = _servers[idx];
    for (final t in s.tools) {
      if (t.name == toolName) return t;
    }
    return null;
  }

  Map<String, dynamic> _normalizeArgsForTool(
    String serverId,
    String toolName,
    Map<String, dynamic> args,
  ) {
    try {
      final cfg = _toolConfig(serverId, toolName);
      final schema = cfg?.schema;
      if (schema == null || schema.isEmpty) return args;
      final cloned = jsonDecode(jsonEncode(args)) as Map<String, dynamic>;
      var normalized = _normalizeBySchema(cloned, schema, propertyName: null);
      if (normalized is! Map<String, dynamic>) return args;
      normalized = _normalizeSpecialCases(toolName, normalized);
      return normalized;
    } catch (_) {
      return args;
    }
  }

  Map<String, dynamic> _normalizeSpecialCases(
    String toolName,
    Map<String, dynamic> args,
  ) {
    try {
      if (toolName == 'firecrawl_search') {
        // sources: ["web"] -> [{"type":"web"}]
        final rawSources = args['sources'];
        if (rawSources is List &&
            rawSources.isNotEmpty &&
            rawSources.every((e) => e is String)) {
          args['sources'] = rawSources.map((e) => {'type': e}).toList();
        }
        // Provide pragmatic defaults for commonly required fields if absent
        args.putIfAbsent('tbs', () => '0');
        args.putIfAbsent('filter', () => '0');
        args.putIfAbsent('location', () => 'us');
        // If tbs/filter are present but empty, coerce to '0'
        if ((args['tbs'] is String) && (args['tbs'] as String).isEmpty) {
          args['tbs'] = '0';
        }
        if ((args['filter'] is String) && (args['filter'] as String).isEmpty) {
          args['filter'] = '0';
        }
        if ((args['location'] is String) &&
            (args['location'] as String).toLowerCase() == 'global') {
          args['location'] = 'us';
        }
        final so = (args['scrapeOptions'] is Map)
            ? (args['scrapeOptions'] as Map).cast<String, dynamic>()
            : <String, dynamic>{};
        so.putIfAbsent('waitFor', () => 0);
        // formats normalization: server expects union of simple literals ["markdown"|"html"|"rawHtml"] OR an object only when type=="json"
        final fm = so['formats'];
        if (fm is List) {
          final norm = <dynamic>[];
          for (final f in fm) {
            if (f is Map) {
              final t = (f['type'] ?? '').toString();
              if (t == 'markdown' || t == 'html' || t == 'rawHtml') {
                norm.add(t);
              } else if (t == 'json') {
                norm.add(f); // keep object form for json
              } else if (t.isNotEmpty) {
                norm.add(t);
              }
            } else if (f is String) {
              if (f == 'json') {
                norm.add({'type': 'json'});
              } else {
                norm.add(f);
              }
            } else {
              norm.add(f);
            }
          }
          so['formats'] = norm;
        }
        args['scrapeOptions'] = so;
      }
    } catch (_) {}
    return args;
  }

  dynamic _normalizeBySchema(
    dynamic value,
    Map<String, dynamic> schema, {
    String? propertyName,
  }) {
    try {
      // Handle anyOf/oneOf by choosing first matching branch; if value is null, attempt defaults
      final List<Map<String, dynamic>> unions = _schemaUnions(schema);
      if (unions.isNotEmpty) {
        // Heuristic only for certain fields (e.g., sources) — DO NOT apply globally.
        if (value is String && propertyName == 'sources') {
          final objBranch = unions.firstWhere(
            (m) =>
                _schemaTypes(m).contains('object') &&
                ((m['properties'] as Map?)?.containsKey('type') ?? false),
            orElse: () => const {},
          );
          if (objBranch.isNotEmpty) {
            return _normalizeBySchema(
              {'type': value},
              objBranch,
              propertyName: propertyName,
            );
          }
        }
        for (final branch in unions) {
          try {
            return _normalizeBySchema(
              value,
              branch,
              propertyName: propertyName,
            );
          } catch (_) {
            // try next branch
          }
        }
        // fallthrough to first branch
        return _normalizeBySchema(
          value,
          unions.first,
          propertyName: propertyName,
        );
      }

      final declaredTypes = _schemaTypes(schema);
      if (declaredTypes.contains('object')) {
        final props =
            (schema['properties'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
        final req =
            (schema['required'] as List?)?.map((e) => e.toString()).toSet() ??
            const <String>{};
        final out = <String, dynamic>{};
        final input = (value is Map)
            ? value.cast<String, dynamic>()
            : const <String, dynamic>{};
        // copy passthrough unknowns
        input.forEach((k, v) {
          if (!props.containsKey(k)) out[k] = v;
        });
        for (final entry in props.entries) {
          final key = entry.key;
          final propSchema = (entry.value is Map)
              ? (entry.value as Map).cast<String, dynamic>()
              : const <String, dynamic>{};
          dynamic v = input.containsKey(key) ? input[key] : null;
          if (v == null) {
            if (propSchema.containsKey('default')) {
              v = propSchema['default'];
            } else if (req.contains(key)) {
              // Only synthesize enum / waitFor defaults for required fields; optional
              // omitted keys should stay absent (do not pick enum.first).
              final enumVals = _schemaEnum(propSchema);
              if (enumVals.isNotEmpty) {
                v = enumVals.first;
              } else if (key == 'waitFor' &&
                  _schemaTypes(
                    propSchema,
                  ).any((t) => t == 'number' || t == 'integer')) {
                v = 0; // pragmatic default often acceptable for waitFor
              }
            }
          }
          if (v != null) {
            out[key] = _normalizeBySchema(v, propSchema, propertyName: key);
          } else if (!req.contains(key)) {
            // omit optional nulls
          } else {
            // keep as null for required to let server validate if still missing
          }
        }
        return out;
      }

      if (declaredTypes.contains('array')) {
        final items =
            (schema['items'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
        final list = (value is List) ? value : [value];
        final out = [];
        for (final item in list) {
          dynamic iv = item;
          // Heuristic only for sources array, not for other arrays like formats
          final itemTypes = _schemaTypes(items);
          if (propertyName == 'sources' &&
              item is String &&
              itemTypes.contains('object')) {
            final itemProps =
                (items['properties'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{};
            if (itemProps.containsKey('type')) {
              iv = {'type': item};
            }
          }
          out.add(_normalizeBySchema(iv, items, propertyName: propertyName));
        }
        return out;
      }

      if (declaredTypes.contains('boolean')) {
        if (value is bool) return value;
        if (value is String) {
          final s = value.toLowerCase();
          if (s == 'true' || s == '1' || s == 'yes') return true;
          if (s == 'false' || s == '0' || s == 'no') return false;
        }
        return value;
      }

      if (declaredTypes.contains('integer')) {
        if (value is int) return value;
        if (value is num) return value.toInt();
        if (value is String) {
          final p = int.tryParse(value);
          if (p != null) return p;
        }
        return value;
      }

      if (declaredTypes.contains('number')) {
        if (value is num) return value;
        if (value is String) {
          final p = double.tryParse(value);
          if (p != null) return p;
        }
        return value;
      }

      if (declaredTypes.contains('string')) {
        if (value == null) return value;
        if (value is String) {
          final enums = _schemaEnum(schema);
          if (enums.isNotEmpty && !enums.contains(value)) {
            // keep original; server will validate
          }
          return value;
        }
        return value.toString();
      }

      // no declared type: return as-is
      return value;
    } catch (_) {
      return value;
    }
  }

  List<Map<String, dynamic>> _schemaUnions(Map<String, dynamic> schema) {
    final out = <Map<String, dynamic>>[];
    final anyOf = schema['anyOf'];
    final oneOf = schema['oneOf'];
    if (anyOf is List) {
      out.addAll(anyOf.whereType<Map>().map((e) => e.cast<String, dynamic>()));
    }
    if (oneOf is List) {
      out.addAll(oneOf.whereType<Map>().map((e) => e.cast<String, dynamic>()));
    }
    return out;
  }

  List<String> _schemaTypes(Map<String, dynamic> schema) {
    final t = schema['type'];
    if (t is String) return [t];
    if (t is List) return t.map((e) => e.toString()).toList();
    return const [];
  }

  List<dynamic> _schemaEnum(Map<String, dynamic> schema) {
    final e = schema['enum'];
    if (e is List) return e;
    return const [];
  }

  Future<void> refreshTools(String id) async {
    final client = _clients[id];
    if (client == null) return;
    try {
      // debugPrint('[MCP/Tools] listTools() ...');
      final tools = await client.listTools();
      // debugPrint('[MCP/Tools] listTools() returned ${tools.length} tools');
      // Preserve enabled state from existing config
      final idx = _servers.indexWhere((e) => e.id == id);
      if (idx < 0) return;
      final existing = _servers[idx].tools;
      final existingMap = {for (final t in existing) t.name: t};

      List<McpToolConfig> merged = [];
      for (final t in tools) {
        final prior = existingMap[t.name];
        // Extract params from inputSchema if present
        final params = <McpParamSpec>[];
        Map<String, dynamic>? schemaJson;
        try {
          final js = t.inputSchema;
          schemaJson = js;
          final props =
              (js['properties'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          final req =
              (js['required'] as List?)?.map((e) => e.toString()).toSet() ??
              const <String>{};
          props.forEach((key, val) {
            String? ty;
            dynamic defVal;
            try {
              final v = (val as Map).cast<String, dynamic>();
              final ttype = v['type'];
              if (ttype is String) {
                ty = ttype;
              } else if (ttype is List) {
                ty = ttype.map((e) => e.toString()).join('|');
              }
              defVal = v['default'];
            } catch (_) {}
            params.add(
              McpParamSpec(
                name: key,
                required: req.contains(key),
                type: ty,
                defaultValue: defVal,
              ),
            );
          });
        } catch (_) {}

        merged.add(
          McpToolConfig(
            enabled: prior?.enabled ?? true,
            name: t.name,
            description: t.description,
            params: params,
            schema: schemaJson,
            needsApproval:
                prior?.needsApproval ??
                (_isBuiltinFilesServer(_servers[idx]) &&
                        _builtinFileWriteToolNames.contains(t.name)) ||
                    (_isBuiltinGithubServer(_servers[idx]) &&
                        _builtinGithubWriteToolNames.contains(t.name)),
          ),
        );
      }

      _servers[idx] = _servers[idx].copyWith(tools: merged);
      await _persist();
      notifyListeners();
    } catch (e) {
      // debugPrint('[MCP/Tools] listTools() failed for id=$id');
      // ignore tool refresh errors; status stays connected
    }
  }

  Future<void> ensureConnected(String id) async {
    // Do not attempt to connect if the server is disabled
    final cfg = getById(id);
    if (cfg == null || !cfg.enabled) return;
    if (isConnected(id)) return;
    // Try a few times with short backoff in case server blips
    await _reconnectWithBackoff(id, maxAttempts: 3);
  }

  Future<mcp.CallToolResult?> callTool(
    String serverId,
    String toolName,
    Map<String, dynamic> args,
  ) async {
    final logId = _beginCallLog(
      serverId: serverId,
      toolName: toolName,
      arguments: args,
    );
    try {
      await ensureConnected(serverId);
      var client = _clients[serverId];
      if (client == null) {
        _finishCallLog(
          logId,
          status: McpCallLogStatus.error,
          error: 'Server is not connected.',
        );
        return null;
      }
      // Normalize arguments based on tool schema (best-effort)
      final normalized = _normalizeArgsForTool(serverId, toolName, args);
      // if (normalized != args) {
      //   debugPrint('[MCP/Call] serverId=$serverId tool=$toolName args(normalized)=${jsonEncode(normalized)}');
      // } else {
      //   debugPrint('[MCP/Call] serverId=$serverId tool=$toolName args=${jsonEncode(args)}');
      // }
      final result = await client.callTool(toolName, normalized);
      // Detailed call timing/content logging disabled
      _finishCallLog(
        logId,
        status: McpCallLogStatus.success,
        resultPreview: _previewCallToolResult(result),
      );
      return result;
    } catch (e) {
      // debugPrint('[MCP/Call/Error] serverId=$serverId tool=$toolName');

      // If this is a parameter validation error from the server, do NOT disconnect.
      try {
        if (e is mcp.McpError && (e.code == -32602)) {
          // Keep connection healthy status; surface error to caller via null
          _errors[serverId] = e.toString();
          // debugPrint('[MCP/Call] invalid arguments; skipping reconnect');
          _finishCallLog(
            logId,
            status: McpCallLogStatus.error,
            error: e.toString(),
          );
          return null;
        }
      } catch (_) {}

      _status[serverId] = McpStatus.error;
      _errors[serverId] = e.toString();
      notifyListeners();
      // Auto-reconnect a few times and try once more
      try {
        await _reconnectWithBackoff(serverId, maxAttempts: 3);
        if (!isConnected(serverId)) {
          _finishCallLog(
            logId,
            status: McpCallLogStatus.error,
            error: _errors[serverId] ?? 'Server did not reconnect.',
            retried: true,
          );
          return null;
        }
        final client = _clients[serverId];
        if (client == null) {
          _finishCallLog(
            logId,
            status: McpCallLogStatus.error,
            error: 'Server is not connected after retry.',
            retried: true,
          );
          return null;
        }
        // debugPrint('[MCP/Call] retry serverId=$serverId tool=$toolName');
        final normalized = _normalizeArgsForTool(serverId, toolName, args);
        final result = await client.callTool(toolName, normalized);
        // Detailed retry logging disabled
        // Mark healthy again
        _status[serverId] = McpStatus.connected;
        _errors.remove(serverId);
        notifyListeners();
        _finishCallLog(
          logId,
          status: McpCallLogStatus.success,
          resultPreview: _previewCallToolResult(result),
          retried: true,
        );
        return result;
      } catch (e2) {
        // debugPrint('[MCP/Call/RetryError] serverId=$serverId tool=$toolName');
        // Keep error state; give up
        _finishCallLog(
          logId,
          status: McpCallLogStatus.error,
          error: e2.toString(),
          retried: true,
        );
        return null;
      }
    }
  }

  List<McpToolConfig> getEnabledToolsForServers(Set<String> serverIds) {
    // Only expose tools for servers that are both selected AND currently connected
    final tools = <McpToolConfig>[];
    for (final s in _servers.where((s) => serverIds.contains(s.id))) {
      if (statusFor(s.id) != McpStatus.connected) continue;
      if (!s.enabled) continue;
      tools.addAll(s.tools.where((t) => t.enabled));
    }
    return tools;
  }

  @override
  void dispose() {
    _disposed = true;
    // Clean up timers
    for (final t in _heartbeats.values) {
      t.cancel();
    }
    _heartbeats.clear();
    super.dispose();
  }

  bool _isDesktopPlatform() {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }
}
