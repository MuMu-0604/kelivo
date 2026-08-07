import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:mcp_client/mcp_client.dart' as mcp;
import '../../providers/mcp_provider.dart';
import '../chat/chat_service.dart';
import '../../providers/assistant_provider.dart';
import '../../../utils/app_directories.dart';

class _McpToolRoute {
  const _McpToolRoute({
    required this.server,
    required this.tool,
    required this.exposedName,
  });

  final McpServerConfig server;
  final McpToolConfig tool;
  final String exposedName;
}

class McpToolRouteSnapshot {
  McpToolRouteSnapshot._(List<_McpToolRoute> routes)
    : _routes = List.unmodifiable(routes);

  final List<_McpToolRoute> _routes;

  _McpToolRoute? _find(String exposedName) {
    for (final route in _routes) {
      if (route.exposedName == exposedName) return route;
    }
    return null;
  }
}

class McpToolService extends ChangeNotifier {
  McpToolService();

  List<McpToolConfig> listAvailableToolsForConversation(
    McpProvider mcpProvider,
    ChatService chat,
    String conversationId,
  ) {
    final selected = chat.getConversationMcpServers(conversationId).toSet();
    return _exposedTools(mcpProvider, selected);
  }

  List<McpToolConfig> listAvailableToolsForAssistant(
    McpProvider mcpProvider,
    AssistantProvider assistants,
    String? assistantId, {
    McpToolRouteSnapshot? routeSnapshot,
  }) {
    if (routeSnapshot != null) {
      return _exposedToolsForRoutes(routeSnapshot._routes);
    }
    final a = (assistantId != null)
        ? assistants.getById(assistantId)
        : assistants.currentAssistant;
    final selected = (a?.mcpServerIds ?? const <String>[]).toSet();
    return _exposedTools(mcpProvider, selected);
  }

  Future<mcp.CallToolResult?> callToolForConversation(
    McpProvider mcpProvider,
    ChatService chat, {
    required String conversationId,
    required String toolName,
    Map<String, dynamic> arguments = const {},
  }) async {
    final selected = chat.getConversationMcpServers(conversationId).toSet();
    // debugPrint('[MCP/Call/Select] convo=$conversationId tool=$toolName selectedServers=${selected.join(',')}');
    if (selected.isEmpty) return null;

    final route = _findRoute(mcpProvider, selected, toolName);
    if (route == null) return null;
    return mcpProvider.callTool(route.server.id, route.tool.name, arguments);
  }

  // Convenience: call tool and flatten result contents to plain text
  Future<String> callToolTextForConversation(
    McpProvider mcpProvider,
    ChatService chat, {
    required String conversationId,
    required String toolName,
    Map<String, dynamic> arguments = const {},
  }) async {
    // Attempt call via selected server
    final selected = chat.getConversationMcpServers(conversationId).toSet();
    final route = _findRoute(mcpProvider, selected, toolName);
    final res = route == null
        ? null
        : await mcpProvider.callTool(
            route.server.id,
            route.tool.name,
            arguments,
          );
    if (res == null) {
      if (route != null) {
        final errMsg =
            mcpProvider.errorFor(route.server.id) ??
            'MCP server is unavailable.';
        return _renderToolErrorForModel(
          serverName: route.server.name,
          toolName: toolName,
          arguments: arguments,
          errorMessage: errMsg,
          schema: route.tool.schema,
        );
      }
      return '';
    }
    final buf = StringBuffer();
    // Be liberal in what we accept: many servers return different content variants.
    for (final c in res.content) {
      try {
        // Known types from mcp_client
        if (c is mcp.TextContent) {
          if ((c.text).trim().isNotEmpty) buf.writeln(c.text);
          continue;
        }
        if (c is mcp.ResourceContent) {
          final t = (c.text ?? '').toString();
          if (t.trim().isNotEmpty) {
            buf.writeln(t);
          } else {
            final uri = (c.uri).toString();
            if (uri.isNotEmpty) buf.writeln('resource: $uri');
          }
          continue;
        }
        if (c is mcp.ImageContent) {
          final data = c.data.toString();
          final mime = c.mimeType.toString();
          if (data.isNotEmpty) {
            final savedPath = await AppDirectories.saveBase64Image(
              mime,
              data,
              prefix: 'mcp_img',
            );
            if (savedPath != null) {
              buf.writeln('[image:$savedPath]');
            }
          } else {
            final url = (c.url ?? '').toString();
            if (url.isNotEmpty) buf.writeln('[image:$url]');
          }
          continue;
        }
        // Try dynamic accessors that some adapters may expose
        final dyn = c as dynamic;
        try {
          final txt = (dyn.text as String?);
          if (txt != null && txt.trim().isNotEmpty) {
            buf.writeln(txt);
            continue;
          }
        } catch (_) {}
        try {
          final uri = (dyn.uri as String?);
          if (uri != null && uri.isNotEmpty) {
            buf.writeln('resource: $uri');
            continue;
          }
        } catch (_) {}
        // As a last resort, serialize to JSON if available
        try {
          final json = (dyn.toJson as dynamic).call();
          buf.writeln(const JsonEncoder.withIndent('  ').convert(json));
          continue;
        } catch (_) {}
        // Fallback to a readable string (avoid Instance of ... when possible)
        final s = c.toString();
        if (!s.startsWith('Instance of')) buf.writeln(s);
      } catch (_) {
        // ignore single content parse errors and continue
      }
    }
    return buf.toString().trim();
  }

  Future<String> callToolTextForAssistant(
    McpProvider mcpProvider,
    AssistantProvider assistants, {
    required String? assistantId,
    required String toolName,
    Map<String, dynamic> arguments = const {},
    McpToolRouteSnapshot? routeSnapshot,
  }) async {
    // try servers selected for the assistant
    final a = (assistantId != null)
        ? assistants.getById(assistantId)
        : assistants.currentAssistant;
    final selected = (a?.mcpServerIds ?? const <String>[]).toSet();
    // debugPrint('[MCP/Call/Select] assistant=${assistantId ?? a?.id ?? '(current)'} tool=$toolName selectedServers=${selected.join(',')}');
    if (selected.isEmpty) return '';
    final routes = routeSnapshot?._routes ?? _toolRoutes(mcpProvider, selected);
    for (final publishedRoute in routes) {
      if (publishedRoute.exposedName == toolName) {
        final route = _currentRouteForIdentity(
          mcpProvider,
          selected,
          publishedRoute,
        );
        if (route == null) return '';
        final s = route.server;
        // debugPrint('[MCP/Call/Select] using server=${s.id} name=${s.name} transport=${s.transport.name}');
        final res = await mcpProvider.callTool(
          s.id,
          route.tool.name,
          arguments,
        );
        if (res == null) {
          final errMsg =
              mcpProvider.errorFor(s.id) ?? 'MCP server is unavailable.';
          return _renderToolErrorForModel(
            serverName: s.name,
            toolName: toolName,
            arguments: arguments,
            errorMessage: errMsg,
            schema: route.tool.schema,
          );
        }
        final buf = StringBuffer();
        for (final c in res.content) {
          try {
            if (c is mcp.TextContent) {
              if ((c.text).trim().isNotEmpty) buf.writeln(c.text);
              continue;
            }
            if (c is mcp.ResourceContent) {
              final t = (c.text ?? '').toString();
              if (t.trim().isNotEmpty) {
                buf.writeln(t);
              } else {
                final uri = (c.uri).toString();
                if (uri.isNotEmpty) buf.writeln('resource: $uri');
              }
              continue;
            }
            if (c is mcp.ImageContent) {
              final data = c.data.toString();
              final mime = c.mimeType.toString();
              if (data.isNotEmpty) {
                final savedPath = await AppDirectories.saveBase64Image(
                  mime,
                  data,
                  prefix: 'mcp_img',
                );
                if (savedPath != null) {
                  buf.writeln('[image:$savedPath]');
                }
              } else {
                final url = (c.url ?? '').toString();
                if (url.isNotEmpty) buf.writeln('[image:$url]');
              }
              continue;
            }
            final dyn = c as dynamic;
            try {
              final txt = (dyn.text as String?);
              if (txt != null && txt.trim().isNotEmpty) {
                buf.writeln(txt);
                continue;
              }
            } catch (_) {}
            try {
              final uri = (dyn.uri as String?);
              if (uri != null && uri.isNotEmpty) {
                buf.writeln('resource: $uri');
                continue;
              }
            } catch (_) {}
            try {
              final json = (dyn.toJson as dynamic).call();
              buf.writeln(const JsonEncoder.withIndent('  ').convert(json));
              continue;
            } catch (_) {}
            final s = c.toString();
            if (!s.startsWith('Instance of')) buf.writeln(s);
          } catch (_) {
            // ignore single content parse errors and continue
          }
        }
        return buf.toString().trim();
      }
    }
    return '';
  }

  bool toolNeedsApprovalForAssistant(
    McpProvider mcpProvider,
    AssistantProvider assistants, {
    required String? assistantId,
    required String toolName,
    McpToolRouteSnapshot? routeSnapshot,
  }) {
    final assistant = assistantId != null
        ? assistants.getById(assistantId)
        : assistants.currentAssistant;
    final selected = (assistant?.mcpServerIds ?? const <String>[]).toSet();
    final publishedRoute = routeSnapshot != null
        ? routeSnapshot._find(toolName)
        : _findRoute(mcpProvider, selected, toolName);
    if (publishedRoute == null) return false;
    final route = _currentRouteForIdentity(
      mcpProvider,
      selected,
      publishedRoute,
    );
    return route?.tool.needsApproval ?? true;
  }

  McpToolRouteSnapshot captureRoutesForAssistant(
    McpProvider mcpProvider,
    AssistantProvider assistants, {
    required String? assistantId,
  }) {
    final assistant = assistantId != null
        ? assistants.getById(assistantId)
        : assistants.currentAssistant;
    final selected = (assistant?.mcpServerIds ?? const <String>[]).toSet();
    return McpToolRouteSnapshot._(_toolRoutes(mcpProvider, selected));
  }

  List<McpToolConfig> _exposedTools(
    McpProvider provider,
    Set<String> selected,
  ) {
    return _exposedToolsForRoutes(_toolRoutes(provider, selected));
  }

  List<McpToolConfig> _exposedToolsForRoutes(Iterable<_McpToolRoute> routes) {
    return [
      for (final route in routes) route.tool.copyWith(name: route.exposedName),
    ];
  }

  _McpToolRoute? _findRoute(
    McpProvider provider,
    Set<String> selected,
    String exposedName,
  ) {
    for (final route in _toolRoutes(provider, selected)) {
      if (route.exposedName == exposedName) return route;
    }
    return null;
  }

  _McpToolRoute? _currentRouteForIdentity(
    McpProvider provider,
    Set<String> selected,
    _McpToolRoute publishedRoute,
  ) {
    for (final server in provider.connectedServers) {
      if (server.id != publishedRoute.server.id ||
          !server.enabled ||
          !selected.contains(server.id)) {
        continue;
      }
      for (final tool in server.tools) {
        if (tool.name == publishedRoute.tool.name && tool.enabled) {
          return _McpToolRoute(
            server: server,
            tool: tool,
            exposedName: publishedRoute.exposedName,
          );
        }
      }
    }
    return null;
  }

  List<_McpToolRoute> _toolRoutes(McpProvider provider, Set<String> selected) {
    final entries = <({McpServerConfig server, McpToolConfig tool})>[];
    for (final server in provider.connectedServers) {
      if (!server.enabled || !selected.contains(server.id)) continue;
      for (final tool in server.tools.where((tool) => tool.enabled)) {
        entries.add((server: server, tool: tool));
      }
    }

    final originalNameCounts = <String, int>{};
    for (final entry in entries) {
      originalNameCounts.update(
        entry.tool.name,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final usedNames = <String>{
      for (final entry in entries)
        if (originalNameCounts[entry.tool.name] == 1) entry.tool.name,
    };
    final routes = <_McpToolRoute>[];
    for (final entry in entries) {
      final duplicated = originalNameCounts[entry.tool.name]! > 1;
      var exposedName = duplicated
          ? _qualifiedToolName(entry.server.name, entry.tool.name)
          : entry.tool.name;
      if (duplicated && usedNames.contains(exposedName)) {
        exposedName = _appendToolNameSuffix(
          exposedName,
          _serverIdSuffix(entry.server.id),
        );
      }
      var uniqueName = exposedName;
      var counter = 2;
      while (duplicated && usedNames.contains(uniqueName)) {
        uniqueName = _appendToolNameSuffix(exposedName, counter.toString());
        counter++;
      }
      usedNames.add(uniqueName);
      routes.add(
        _McpToolRoute(
          server: entry.server,
          tool: entry.tool,
          exposedName: uniqueName,
        ),
      );
    }
    return routes;
  }

  String _qualifiedToolName(String serverName, String toolName) {
    final server = _sanitizeToolNamePart(serverName, fallback: 'mcp');
    final tool = _sanitizeToolNamePart(toolName, fallback: 'tool');
    var name = '${server}__$tool';
    if (!RegExp(r'^[a-zA-Z_]').hasMatch(name)) name = 'mcp_$name';
    return _limitToolName(name);
  }

  String _sanitizeToolNamePart(String value, {required String fallback}) {
    var sanitized = value.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    sanitized = sanitized.replaceAll(RegExp(r'^-+'), '');
    sanitized = sanitized.replaceAll(RegExp(r'[_-]+$'), '');
    return sanitized.isEmpty ? fallback : sanitized;
  }

  String _serverIdSuffix(String serverId) {
    final sanitized = _sanitizeToolNamePart(serverId, fallback: 'server');
    return sanitized.length > 8 ? sanitized.substring(0, 8) : sanitized;
  }

  String _appendToolNameSuffix(String name, String suffix) {
    final separatorAndSuffix = '_$suffix';
    final maxBaseLength = 64 - separatorAndSuffix.length;
    final base = name.length > maxBaseLength
        ? name.substring(0, maxBaseLength)
        : name;
    return '$base$separatorAndSuffix';
  }

  String _limitToolName(String name) {
    return name.length > 64 ? name.substring(0, 64) : name;
  }

  String _renderToolErrorForModel({
    required String serverName,
    required String toolName,
    required Map<String, dynamic> arguments,
    required String errorMessage,
    Map<String, dynamic>? schema,
  }) {
    // Provide a concise JSON for the model to self-correct and retry
    final map = <String, dynamic>{
      'type': 'tool_error',
      'error': 'invalid_arguments',
      'message': errorMessage,
      'tool': toolName,
      'server': serverName,
      'lastArguments': arguments,
      if (schema != null && schema.isNotEmpty) 'parametersSchema': schema,
      'instruction':
          'Revise arguments to satisfy parametersSchema, then call the same tool again.',
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }
}
