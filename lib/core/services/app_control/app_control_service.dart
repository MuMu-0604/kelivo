import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/assistant.dart';
import '../../models/instruction_injection.dart';
import '../../models/quick_phrase.dart';
import '../../models/skill.dart';
import '../../models/world_book.dart';
import '../../providers/assistant_provider.dart';
import '../../providers/instruction_injection_provider.dart';
import '../../providers/memory_provider.dart';
import '../../providers/mcp_provider.dart';
import '../../providers/quick_phrase_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/skill_provider.dart';
import '../../providers/world_book_provider.dart';
import '../search/search_service.dart';
import '../../../features/home/services/local_tools_service.dart';

class AppControlToolNames {
  const AppControlToolNames._();

  static const String appControl = 'kelivo_app_control';
}

class AppControlActionNames {
  const AppControlActionNames._();

  static const String listCapabilities = 'list_capabilities';
  static const String inspectTarget = 'inspect_target';
  static const String planAction = 'plan_action';
  static const String executeAction = 'execute_action';
  static const String undoLast = 'undo_last';
}

class AppControlTargets {
  const AppControlTargets._();

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
}

class AppControlOperations {
  const AppControlOperations._();

  static const String append = 'append';
  static const String overwrite = 'overwrite';
  static const String create = 'create';
  static const String update = 'update';
  static const String enable = 'enable';
  static const String disable = 'disable';
  static const String bind = 'bind';
  static const String unbind = 'unbind';
  static const String delete = 'delete';
  static const String reorder = 'reorder';
  static const String importJson = 'import_json';
  static const String exportJson = 'export_json';
  static const String addEntry = 'add_entry';
  static const String updateEntry = 'update_entry';
  static const String deleteEntry = 'delete_entry';
  static const String createVersion = 'create_version';
  static const String rollbackVersion = 'rollback_version';
  static const String setApproval = 'set_approval';
}

class AppControlUndoEntry {
  const AppControlUndoEntry({
    required this.id,
    required this.target,
    required this.payload,
    required this.createdAt,
  });

  final String id;
  final String target;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
}

class AppControlAuditEntry {
  const AppControlAuditEntry({
    required this.id,
    required this.target,
    required this.operation,
    required this.title,
    required this.assistantId,
    required this.assistantName,
    required this.createdAt,
    required this.success,
    required this.undoable,
  });

  final String id;
  final String target;
  final String operation;
  final String title;
  final String? assistantId;
  final String? assistantName;
  final DateTime createdAt;
  final bool success;
  final bool undoable;

  Map<String, dynamic> toJson() => {
    'id': id,
    'target': target,
    'operation': operation,
    'title': title,
    'assistant_id': assistantId,
    'assistant_name': assistantName,
    'created_at': createdAt.toIso8601String(),
    'success': success,
    'undoable': undoable,
  };
}

class AppControlService {
  AppControlService({required this.contextProvider});

  static const String systemPrompt = '''
Kelivo 神经权能网关 is available for this assistant. Use the `kelivo_app_control` tool when the user asks you to import, append, overwrite, create, inspect, configure, or undo Kelivo app data from chat content or generated content.

Supported targets:
- `current_assistant.settings`: update core assistant settings from structured JSON content.
- `current_assistant.system_prompt`: append, overwrite, import, or export the current assistant system prompt.
- `current_assistant.memory`: create, update, delete, import, or export memories for the current assistant.
- `current_assistant.skills`: create, update, delete, version, roll back, import/export, or bind/unbind skills for the current assistant.
- `current_assistant.local_tools`: bind/unbind local tools such as time, clipboard, TTS, ask-user, or calculator.
- `current_assistant.mcp`: bind/unbind MCP servers for the current assistant.
- `quick_phrase`: create, update, reorder, delete, import, or export global/assistant quick phrases.
- `instruction_injection`: create, update, delete, activate/deactivate, import, or export instruction injections.
- `world_book`: create, update, delete, activate/deactivate, import/export books, and add/update/delete entries.
- `mcp_server`: create/update/delete MCP servers and enable/disable MCP servers/tools or approval for MCP tools.
- `search_settings`: enable/disable, update, import, or export built-in search globally or for the current assistant.
- `app_bundle`: import or export a migration bundle containing assistant settings, skills, world books, quick phrases, instruction injections, MCP, and search settings.
- `audit_log`: inspect recent 神经权能网关 operations and whether they can be undone.

Prefer `plan_action` when the user's wording is ambiguous or the change is large. Use `execute_action` only when the user clearly asks to apply/import/save the content. Include concise `title` and `reason` fields so Kelivo can show a useful confirmation. Use `undo_last` when the user asks to undo the last 神经权能网关 operation.
''';

  static String systemPromptForAssistant(Assistant assistant) {
    final enabled = capabilitiesForAssistant(assistant);
    final buffer = StringBuffer()
      ..writeln('Kelivo 神经权能网关 is available for this assistant.')
      ..writeln(
        'Use the `kelivo_app_control` tool only for targets enabled by this assistant policy.',
      )
      ..writeln()
      ..writeln('Enabled targets:');
    for (final item in enabled) {
      final target = item['target'].toString();
      final operations = (item['operations'] as List).join(', ');
      final approval = assistant.appControlPolicy.approvalRequiredFor(
        target,
        '',
      );
      buffer.writeln(
        '- `$target`: operations [$operations]; approval ${approval ? 'usually required' : 'not usually required'}.',
      );
    }
    buffer
      ..writeln('- `audit_log`: inspect recent gateway operations.')
      ..writeln()
      ..writeln(
        'Prefer `plan_action` for ambiguous or large changes. Use `execute_action` only when the user clearly asks to apply, import, save, or configure content. Use `undo_last` when the user asks to undo the last gateway operation.',
      );
    return buffer.toString();
  }

  static const List<Map<String, dynamic>> capabilities = [
    {
      'target': AppControlTargets.currentAssistantSettings,
      'operations': [
        AppControlOperations.update,
        AppControlOperations.importJson,
        AppControlOperations.exportJson,
      ],
      'description':
          'Update current assistant settings from JSON content such as name, model binding, search, memory, context size, temperature, max tokens, or 神经权能网关 permission.',
      'requires_confirmation': true,
      'undoable': true,
    },
    {
      'target': AppControlTargets.currentAssistantSystemPrompt,
      'operations': [
        AppControlOperations.append,
        AppControlOperations.overwrite,
        AppControlOperations.importJson,
        AppControlOperations.exportJson,
      ],
      'description':
          'Append to or overwrite the current assistant system prompt.',
      'requires_confirmation': true,
      'undoable': true,
    },
    {
      'target': AppControlTargets.currentAssistantMemory,
      'operations': [
        AppControlOperations.create,
        AppControlOperations.update,
        AppControlOperations.delete,
        AppControlOperations.importJson,
        AppControlOperations.exportJson,
      ],
      'description':
          'Create, update, delete, import, or export memories for the current assistant.',
      'requires_confirmation': true,
      'undoable': true,
    },
    {
      'target': AppControlTargets.currentAssistantSkills,
      'operations': [
        AppControlOperations.create,
        AppControlOperations.update,
        AppControlOperations.delete,
        AppControlOperations.bind,
        AppControlOperations.unbind,
        AppControlOperations.importJson,
        AppControlOperations.exportJson,
        AppControlOperations.createVersion,
        AppControlOperations.rollbackVersion,
      ],
      'description':
          'Create a reusable skill from content, or bind/unbind existing skill ids to the current assistant.',
      'requires_confirmation': true,
      'undoable': true,
    },
    {
      'target': AppControlTargets.currentAssistantLocalTools,
      'operations': [AppControlOperations.bind, AppControlOperations.unbind],
      'description': 'Bind or unbind local tool ids for the current assistant.',
      'requires_confirmation': true,
      'undoable': true,
    },
    {
      'target': AppControlTargets.currentAssistantMcp,
      'operations': [AppControlOperations.bind, AppControlOperations.unbind],
      'description': 'Bind or unbind MCP server ids for the current assistant.',
      'requires_confirmation': true,
      'undoable': true,
    },
    {
      'target': AppControlTargets.quickPhrase,
      'operations': [
        AppControlOperations.create,
        AppControlOperations.update,
        AppControlOperations.delete,
        AppControlOperations.reorder,
        AppControlOperations.importJson,
        AppControlOperations.exportJson,
      ],
      'description':
          'Create a global or assistant-specific quick phrase from content.',
      'requires_confirmation': true,
      'undoable': true,
    },
    {
      'target': AppControlTargets.instructionInjection,
      'operations': [
        AppControlOperations.create,
        AppControlOperations.update,
        AppControlOperations.delete,
        AppControlOperations.enable,
        AppControlOperations.disable,
        AppControlOperations.importJson,
        AppControlOperations.exportJson,
      ],
      'description':
          'Create, update, delete, import/export, or activate instruction injection cards.',
      'requires_confirmation': true,
      'undoable': true,
    },
    {
      'target': AppControlTargets.worldBook,
      'operations': [
        AppControlOperations.create,
        AppControlOperations.update,
        AppControlOperations.delete,
        AppControlOperations.enable,
        AppControlOperations.disable,
        AppControlOperations.addEntry,
        AppControlOperations.updateEntry,
        AppControlOperations.deleteEntry,
        AppControlOperations.importJson,
        AppControlOperations.exportJson,
      ],
      'description':
          'Create a world book containing one generated entry; can be activated.',
      'requires_confirmation': true,
      'undoable': true,
    },
    {
      'target': AppControlTargets.mcpServer,
      'operations': [
        AppControlOperations.create,
        AppControlOperations.update,
        AppControlOperations.delete,
        AppControlOperations.enable,
        AppControlOperations.disable,
        AppControlOperations.importJson,
        AppControlOperations.exportJson,
        AppControlOperations.setApproval,
      ],
      'description':
          'Create/update MCP server configs from JSON, enable/disable MCP servers, enable/disable MCP tools, or change tool approval requirements.',
      'requires_confirmation': true,
      'undoable': true,
    },
    {
      'target': AppControlTargets.searchSettings,
      'operations': [
        AppControlOperations.update,
        AppControlOperations.enable,
        AppControlOperations.disable,
        AppControlOperations.importJson,
        AppControlOperations.exportJson,
      ],
      'description':
          'Enable/disable built-in search globally or for the current assistant, or update selected search services from JSON.',
      'requires_confirmation': true,
      'undoable': true,
    },
    {
      'target': AppControlTargets.appBundle,
      'operations': [
        AppControlOperations.importJson,
        AppControlOperations.exportJson,
      ],
      'description':
          'Import or export a portable JSON bundle for migration and recovery.',
      'requires_confirmation': true,
      'undoable': true,
    },
  ];

  static final List<AppControlUndoEntry> _undoStack = <AppControlUndoEntry>[];
  static final List<AppControlAuditEntry> _auditLog = <AppControlAuditEntry>[];

  final BuildContext contextProvider;
  final Uuid _uuid = const Uuid();

  static List<Map<String, dynamic>> capabilitiesForAssistant(
    Assistant? assistant,
  ) {
    if (assistant == null) return capabilities;
    return capabilities
        .where(
          (item) => assistant.appControlPolicy.isTargetEnabled(
            item['target'].toString(),
          ),
        )
        .toList(growable: false);
  }

  static Map<String, dynamic> getToolDefinition([Assistant? assistant]) {
    final targetIds = capabilitiesForAssistant(
      assistant,
    ).map((item) => item['target'].toString()).toSet().toList();
    if (!targetIds.contains(AppControlTargets.auditLog)) {
      targetIds.add(AppControlTargets.auditLog);
    }
    return {
      'type': 'function',
      'function': {
        'name': AppControlToolNames.appControl,
        'description':
            'Plan, inspect, execute, or undo safe Kelivo 神经权能网关 actions such as importing generated content into the current assistant prompt, memory, instruction injection, or world book. Execution requires the assistant 神经权能网关 permission and user confirmation.',
        'parameters': {
          'type': 'object',
          'properties': {
            'action': {
              'type': 'string',
              'enum': [
                AppControlActionNames.listCapabilities,
                AppControlActionNames.inspectTarget,
                AppControlActionNames.planAction,
                AppControlActionNames.executeAction,
                AppControlActionNames.undoLast,
              ],
              'description': 'App control command to run.',
            },
            'target': {
              'type': 'string',
              'enum': targetIds,
              'description': 'Kelivo app data target.',
            },
            'operation': {
              'type': 'string',
              'enum': [
                AppControlOperations.append,
                AppControlOperations.overwrite,
                AppControlOperations.create,
                AppControlOperations.update,
                AppControlOperations.enable,
                AppControlOperations.disable,
                AppControlOperations.bind,
                AppControlOperations.unbind,
                AppControlOperations.delete,
                AppControlOperations.reorder,
                AppControlOperations.importJson,
                AppControlOperations.exportJson,
                AppControlOperations.addEntry,
                AppControlOperations.updateEntry,
                AppControlOperations.deleteEntry,
                AppControlOperations.createVersion,
                AppControlOperations.rollbackVersion,
                AppControlOperations.setApproval,
              ],
              'description': 'Mutation operation for the target.',
            },
            'content': {
              'type': 'string',
              'description':
                  'Content to import, create, append, overwrite, or JSON config for settings/MCP/search updates.',
            },
            'id': {
              'type': 'string',
              'description':
                  'Primary id to update, delete, enable, disable, or inspect in the selected target.',
            },
            'entry_id': {
              'type': 'string',
              'description':
                  'World book entry id for update_entry or delete_entry.',
            },
            'book_id': {
              'type': 'string',
              'description': 'World book id for entry-level operations.',
            },
            'title': {
              'type': 'string',
              'description':
                  'Short title for created items or confirmation UI.',
            },
            'reason': {
              'type': 'string',
              'description': 'Brief reason shown to the user before execution.',
            },
            'activate': {
              'type': 'boolean',
              'description':
                  'Whether to activate the created instruction injection or world book for the current assistant.',
            },
            'ids': {
              'type': 'array',
              'items': {'type': 'string'},
              'description':
                  'Existing ids to bind/unbind, such as skill ids, local tool ids, or MCP server ids.',
            },
            'items': {
              'type': 'array',
              'items': {'type': 'object'},
              'description':
                  'Batch payload for import_json, reorder, or multi-item create/update/delete operations.',
            },
            'server_id': {
              'type': 'string',
              'description': 'MCP server id for mcp_server actions.',
            },
            'tool_name': {
              'type': 'string',
              'description': 'MCP tool name for mcp_server tool actions.',
            },
            'needs_approval': {
              'type': 'boolean',
              'description':
                  'Whether the MCP tool should require user approval when operation is set_approval.',
            },
            'scope': {
              'type': 'string',
              'enum': ['assistant', 'global', 'selected_service', 'service'],
              'description':
                  'Where applicable, choose assistant-specific or global scope.',
            },
            'index': {
              'type': 'integer',
              'description':
                  'Optional service index for selecting or updating a search provider.',
            },
            'old_index': {
              'type': 'integer',
              'description': 'Old index for reorder operations.',
            },
            'new_index': {
              'type': 'integer',
              'description': 'New index for reorder operations.',
            },
            'keywords': {
              'type': 'array',
              'items': {'type': 'string'},
              'description':
                  'Trigger keywords for skills or world book entries.',
            },
            'enabled': {
              'type': 'boolean',
              'description':
                  'Optional enabled flag for updated skills, books, entries, or servers.',
            },
            'mode': {
              'type': 'string',
              'enum': ['merge', 'replace'],
              'description':
                  'Import mode. merge keeps existing data; replace swaps the target snapshot.',
            },
            'version_id': {
              'type': 'string',
              'description': 'Skill version id used for rollback_version.',
            },
            'priority': {
              'type': 'integer',
              'description': 'Optional priority for created skills.',
            },
          },
          'required': ['action'],
        },
      },
    };
  }

  Future<String> handleToolCall(
    Map<String, dynamic> args,
    Assistant? assistant,
  ) async {
    final action = (args['action'] ?? '').toString().trim();
    if (action.isEmpty) {
      return _jsonError('invalid_action', 'action is required');
    }

    switch (action) {
      case AppControlActionNames.listCapabilities:
        return _json({
          'type': 'app_control_capabilities',
          'capabilities': capabilitiesForAssistant(assistant),
          'policy': assistant?.appControlPolicy.toJson(),
          'permission_enabled': assistant?.appControlEnabled == true,
          'audit_count': _auditLog.length,
        });
      case AppControlActionNames.inspectTarget:
        return _inspectTarget(args, assistant);
      case AppControlActionNames.planAction:
        return _planAction(args, assistant);
      case AppControlActionNames.executeAction:
        return _executeAction(args, assistant);
      case AppControlActionNames.undoLast:
        return _undoLast(assistant);
      default:
        return _jsonError('invalid_action', 'unknown 神经权能网关 action: $action');
    }
  }

  String _planAction(Map<String, dynamic> args, Assistant? assistant) {
    final validation = _validateMutationArgs(args, assistant);
    if (validation != null) return validation;
    final target = args['target'].toString();
    final operation = args['operation'].toString();
    final content = args['content'].toString();
    final requiresApproval =
        assistant?.appControlPolicy.approvalRequiredFor(target, operation) ??
        true;
    return _json({
      'type': 'app_control_plan',
      'target': target,
      'operation': operation,
      'title': _title(args, target),
      'reason': _reason(args, target, operation),
      'content_preview': _preview(content),
      'content_length': content.length,
      'requires_confirmation': requiresApproval,
      'permission_enabled': assistant?.appControlEnabled == true,
      'target_enabled': assistant?.appControlPolicy.isTargetEnabled(target),
      'next_step': assistant?.appControlEnabled == true
          ? 'Call execute_action with the same target, operation, content, title, and activate fields after the user confirms.'
          : 'Ask the user to enable 神经权能网关 permission in this assistant settings.',
    });
  }

  Future<String> _executeAction(
    Map<String, dynamic> args,
    Assistant? assistant,
  ) async {
    final validation = _validateMutationArgs(args, assistant);
    if (validation != null) return validation;
    if (assistant?.appControlEnabled != true) {
      return _jsonError(
        'permission_required',
        'Current assistant has not been granted 神经权能网关 permission.',
      );
    }

    final target = args['target'].toString();
    final operation = args['operation'].toString();
    final content = args['content'].toString();

    if (!assistant!.appControlPolicy.isTargetEnabled(target)) {
      return _jsonError(
        'permission_denied',
        '神经权能网关 target is disabled for this assistant: $target',
      );
    }

    if (operation == AppControlOperations.exportJson) {
      return _exportTarget(target, assistant, args);
    }
    if (target == AppControlTargets.auditLog) {
      return _inspectAuditLog();
    }

    final result = switch (target) {
      AppControlTargets.currentAssistantSettings =>
        await _executeAssistantSettings(assistant, operation, content),
      AppControlTargets.currentAssistantSystemPrompt =>
        await _executeAssistantPrompt(assistant, operation, content),
      AppControlTargets.currentAssistantMemory => await _executeMemory(
        assistant,
        args,
        operation,
        content,
      ),
      AppControlTargets.currentAssistantSkills => await _executeSkills(
        assistant,
        args,
        operation,
        content,
      ),
      AppControlTargets.currentAssistantLocalTools =>
        await _executeAssistantLocalTools(assistant, args, operation),
      AppControlTargets.currentAssistantMcp => await _executeAssistantMcp(
        assistant,
        args,
        operation,
      ),
      AppControlTargets.quickPhrase => await _executeQuickPhrase(
        assistant,
        args,
        operation,
        content,
      ),
      AppControlTargets.instructionInjection =>
        await _executeInstructionInjection(assistant, args, operation, content),
      AppControlTargets.worldBook => await _executeWorldBook(
        assistant,
        args,
        operation,
        content,
      ),
      AppControlTargets.mcpServer => await _executeMcpServer(args, operation),
      AppControlTargets.searchSettings => await _executeSearchSettings(
        assistant,
        args,
        operation,
      ),
      AppControlTargets.appBundle => await _executeAppBundle(
        assistant,
        args,
        operation,
        content,
      ),
      _ => _jsonError('unsupported_target', 'unsupported target: $target'),
    };
    _recordAudit(
      target: target,
      operation: operation,
      title: _title(args, target),
      assistant: assistant,
      success: !_isJsonError(result),
      undoable: !_isJsonError(result) && _undoStack.isNotEmpty,
    );
    return result;
  }

  Future<String> _inspectTarget(
    Map<String, dynamic> args,
    Assistant? assistant,
  ) async {
    final target = (args['target'] ?? '').toString().trim();
    if (assistant == null) {
      return _jsonError('assistant_unavailable', 'No current assistant found.');
    }
    switch (target) {
      case AppControlTargets.currentAssistantSettings:
        return _json({
          'type': 'app_control_inspection',
          'target': target,
          'assistant': _assistantSummary(assistant),
        });
      case AppControlTargets.currentAssistantSystemPrompt:
        final prompt = assistant.systemPrompt;
        return _json({
          'type': 'app_control_inspection',
          'target': target,
          'assistant_id': assistant.id,
          'assistant_name': assistant.name,
          'content_length': prompt.length,
          'content_preview': _preview(prompt),
        });
      case AppControlTargets.currentAssistantMemory:
        final mp = contextProvider.read<MemoryProvider>();
        await mp.initialize();
        final memories = mp.getForAssistant(assistant.id);
        final requestedId = (args['id'] ?? '').toString().trim();
        return _json({
          'type': 'app_control_inspection',
          'target': target,
          'count': memories.length,
          if (requestedId.isNotEmpty)
            'item': memories
                .where((m) => m.id.toString() == requestedId)
                .map((m) => m.toJson())
                .cast<Map<String, dynamic>?>()
                .firstOrNull,
          'items': memories
              .take(20)
              .map(
                (m) => {
                  'id': m.id,
                  'assistant_id': m.assistantId,
                  'content': m.content,
                  'content_preview': _preview(m.content),
                },
              )
              .toList(growable: false),
        });
      case AppControlTargets.currentAssistantSkills:
        final provider = contextProvider.read<SkillProvider>();
        await provider.initialize();
        final visibleItems = provider.skills
            .take(30)
            .map(
              (skill) => {
                'id': skill.id,
                'name': skill.name,
                'enabled': skill.enabled,
                'active': assistant.skillIds.contains(skill.id),
                'priority': skill.priority,
                'trigger_keywords': skill.triggerKeywords,
                'source_path': skill.sourcePath,
                'description_preview': _preview(skill.description),
                'content_preview': _preview(skill.content),
              },
            )
            .toList(growable: true);
        final visibleIds = provider.skills.map((skill) => skill.id).toSet();
        final missingItems = assistant.skillIds
            .where((id) => !visibleIds.contains(id))
            .map(
              (id) => {
                'id': id,
                'missing': true,
                'active': true,
                'reason': 'skill_not_found_or_not_accessible',
              },
            )
            .toList(growable: false);
        visibleItems.addAll(missingItems);
        final requestedSkillId = (args['id'] ?? '').toString().trim();
        final requestedSkill = requestedSkillId.isEmpty
            ? null
            : provider.getById(requestedSkillId);
        return _json({
          'type': 'app_control_inspection',
          'target': target,
          'active_ids': assistant.skillIds,
          'items': visibleItems,
          if (requestedSkillId.isNotEmpty)
            'item':
                requestedSkill?.toJson() ??
                (assistant.skillIds.contains(requestedSkillId)
                    ? {
                        'id': requestedSkillId,
                        'missing': true,
                        'active': true,
                        'reason': 'skill_not_found_or_not_accessible',
                      }
                    : null),
        });
      case AppControlTargets.currentAssistantLocalTools:
        return _json({
          'type': 'app_control_inspection',
          'target': target,
          'active_ids': assistant.localToolIds,
          'available_ids': _availableLocalToolIds,
        });
      case AppControlTargets.currentAssistantMcp:
        final provider = contextProvider.read<McpProvider>();
        return _json({
          'type': 'app_control_inspection',
          'target': target,
          'active_ids': assistant.mcpServerIds,
          'servers': provider.servers
              .map(
                (server) => {
                  'id': server.id,
                  'name': server.name,
                  'enabled': server.enabled,
                  'active': assistant.mcpServerIds.contains(server.id),
                  'transport': server.transport.name,
                  'tools': server.tools.length,
                },
              )
              .toList(growable: false),
        });
      case AppControlTargets.quickPhrase:
        final provider = contextProvider.read<QuickPhraseProvider>();
        await provider.initialize();
        return _json({
          'type': 'app_control_inspection',
          'target': target,
          'global_count': provider.globalPhrases.length,
          'assistant_count': provider.getForAssistant(assistant.id).length,
          'items': provider.phrases
              .take(30)
              .map(
                (phrase) => {
                  'id': phrase.id,
                  'title': phrase.title,
                  'scope': phrase.isGlobal ? 'global' : 'assistant',
                  'assistant_id': phrase.assistantId,
                  'content': phrase.content,
                  'content_preview': _preview(phrase.content),
                },
              )
              .toList(growable: false),
          if ((args['id'] ?? '').toString().trim().isNotEmpty)
            'item': provider.phrases
                .where((p) => p.id == (args['id'] ?? '').toString().trim())
                .map((p) => p.toJson())
                .cast<Map<String, dynamic>?>()
                .firstOrNull,
        });
      case AppControlTargets.instructionInjection:
        final provider = contextProvider.read<InstructionInjectionProvider>();
        await provider.initialize();
        return _json({
          'type': 'app_control_inspection',
          'target': target,
          'count': provider.items.length,
          'active_ids': provider.activeIdsFor(assistant.id),
          'items': provider.items
              .take(20)
              .map(
                (item) => {
                  'id': item.id,
                  'title': item.title,
                  'group': item.group,
                  'active': provider
                      .activeIdsFor(assistant.id)
                      .contains(item.id),
                  'prompt': item.prompt,
                  'prompt_preview': _preview(item.prompt),
                },
              )
              .toList(growable: false),
          if ((args['id'] ?? '').toString().trim().isNotEmpty)
            'item': provider.items
                .where(
                  (item) => item.id == (args['id'] ?? '').toString().trim(),
                )
                .map((item) => item.toJson())
                .cast<Map<String, dynamic>?>()
                .firstOrNull,
        });
      case AppControlTargets.worldBook:
        final provider = contextProvider.read<WorldBookProvider>();
        await provider.initialize();
        return _json({
          'type': 'app_control_inspection',
          'target': target,
          'count': provider.books.length,
          'active_ids': provider.activeBookIdsFor(assistant.id),
          'items': provider.books
              .take(20)
              .map(
                (book) => {
                  'id': book.id,
                  'name': book.name,
                  'enabled': book.enabled,
                  'active': provider
                      .activeBookIdsFor(assistant.id)
                      .contains(book.id),
                  'entries': book.entries.length,
                  'entry_items': book.entries
                      .map((entry) => entry.toJson())
                      .toList(growable: false),
                  'description_preview': _preview(book.description),
                },
              )
              .toList(growable: false),
          if ((args['id'] ?? '').toString().trim().isNotEmpty)
            'item': provider
                .getById((args['id'] ?? '').toString().trim())
                ?.toJson(),
        });
      case AppControlTargets.mcpServer:
        final provider = contextProvider.read<McpProvider>();
        return _json({
          'type': 'app_control_inspection',
          'target': target,
          'servers': provider.servers
              .map(
                (server) => {
                  'id': server.id,
                  'name': server.name,
                  'enabled': server.enabled,
                  'status': provider.statusFor(server.id).name,
                  'tools': server.tools
                      .map(
                        (tool) => {
                          'name': tool.name,
                          'enabled': tool.enabled,
                          'needs_approval': tool.needsApproval,
                        },
                      )
                      .toList(growable: false),
                },
              )
              .toList(growable: false),
        });
      case AppControlTargets.searchSettings:
        final settings = contextProvider.read<SettingsProvider>();
        return _json({
          'type': 'app_control_inspection',
          'target': target,
          'global_enabled': settings.searchEnabled,
          'assistant_enabled': assistant.searchEnabled,
          'selected_index': settings.searchServiceSelected,
          'services': settings.searchServices
              .asMap()
              .entries
              .map(
                (entry) => {
                  'index': entry.key,
                  'id': entry.value.id,
                  'type': entry.value.toJson()['type'],
                  'selected': entry.key == settings.searchServiceSelected,
                },
              )
              .toList(growable: false),
        });
      case AppControlTargets.appBundle:
        return _exportTarget(AppControlTargets.appBundle, assistant, args);
      case AppControlTargets.auditLog:
        return _inspectAuditLog();
      default:
        return _jsonError('unsupported_target', 'unsupported target: $target');
    }
  }

  Future<String> _executeAssistantPrompt(
    Assistant assistant,
    String operation,
    String content,
  ) async {
    if (operation == AppControlOperations.importJson) {
      final decoded = _jsonObjectContent(content);
      if (decoded.containsKey('system_prompt')) {
        content = decoded['system_prompt']?.toString() ?? '';
      } else if (decoded.containsKey('systemPrompt')) {
        content = decoded['systemPrompt']?.toString() ?? '';
      } else {
        content = decoded['content']?.toString() ?? '';
      }
      operation = AppControlOperations.overwrite;
    }
    if (operation != AppControlOperations.append &&
        operation != AppControlOperations.overwrite) {
      return _jsonError(
        'unsupported_operation',
        'system prompt supports append or overwrite only',
      );
    }
    final ap = contextProvider.read<AssistantProvider>();
    final before = assistant.systemPrompt;
    final next = operation == AppControlOperations.overwrite
        ? content
        : _appendBlock(before, content);
    await ap.updateAssistant(assistant.copyWith(systemPrompt: next));
    _pushUndo(
      target: AppControlTargets.currentAssistantSystemPrompt,
      payload: {'assistant_id': assistant.id, 'system_prompt': before},
    );
    return _json({
      'type': 'app_control_result',
      'success': true,
      'target': AppControlTargets.currentAssistantSystemPrompt,
      'operation': operation,
      'assistant_id': assistant.id,
      'content_length': next.length,
      'undo_available': true,
    });
  }

  Future<String> _executeAssistantSettings(
    Assistant assistant,
    String operation,
    String content,
  ) async {
    if (operation != AppControlOperations.update &&
        operation != AppControlOperations.importJson) {
      return _jsonError(
        'unsupported_operation',
        'assistant settings supports update or import_json only',
      );
    }
    final patch = _jsonObjectContent(content);
    final ap = contextProvider.read<AssistantProvider>();
    final before = assistant;
    var next = assistant;

    if (patch.containsKey('name')) {
      final name = patch['name']?.toString().trim() ?? '';
      if (name.isNotEmpty) next = next.copyWith(name: name);
    }
    if (patch.containsKey('system_prompt') ||
        patch.containsKey('systemPrompt')) {
      next = next.copyWith(
        systemPrompt:
            (patch.containsKey('system_prompt')
                    ? patch['system_prompt']
                    : patch['systemPrompt'])
                ?.toString() ??
            '',
      );
    }
    if (patch.containsKey('message_template')) {
      final template = patch['message_template']?.toString().trim() ?? '';
      if (template.isNotEmpty) next = next.copyWith(messageTemplate: template);
    }
    if (patch.containsKey('search_enabled')) {
      next = next.copyWith(searchEnabled: _boolFrom(patch['search_enabled']));
    }
    if (patch.containsKey('memory_enabled')) {
      next = next.copyWith(enableMemory: _boolFrom(patch['memory_enabled']));
    }
    if (patch.containsKey('recent_chats_reference_enabled')) {
      next = next.copyWith(
        enableRecentChatsReference: _boolFrom(
          patch['recent_chats_reference_enabled'],
        ),
      );
    }
    if (patch.containsKey('app_control_enabled')) {
      next = next.copyWith(
        appControlEnabled: _boolFrom(patch['app_control_enabled']),
      );
    }
    if (patch.containsKey('stream_output')) {
      next = next.copyWith(streamOutput: _boolFrom(patch['stream_output']));
    }
    if (patch.containsKey('context_message_size')) {
      final value = _intFrom(patch['context_message_size']);
      next = next.copyWith(
        contextMessageSize: value.clamp(
          Assistant.minContextMessageSize,
          Assistant.maxContextMessageSize,
        ),
        limitContextMessages: true,
      );
    }
    if (patch.containsKey('limit_context_messages')) {
      next = next.copyWith(
        limitContextMessages: _boolFrom(patch['limit_context_messages']),
      );
    }
    if (patch.containsKey('temperature')) {
      final value = patch['temperature'];
      next = value == null || value.toString().trim().isEmpty
          ? next.copyWith(clearTemperature: true)
          : next.copyWith(temperature: _doubleFrom(value).clamp(0.0, 2.0));
    }
    if (patch.containsKey('top_p')) {
      final value = patch['top_p'];
      next = value == null || value.toString().trim().isEmpty
          ? next.copyWith(clearTopP: true)
          : next.copyWith(topP: _doubleFrom(value).clamp(0.0, 1.0));
    }
    if (patch.containsKey('thinking_budget')) {
      final value = patch['thinking_budget'];
      next = value == null || value.toString().trim().isEmpty
          ? next.copyWith(clearThinkingBudget: true)
          : next.copyWith(thinkingBudget: _intFrom(value));
    }
    if (patch.containsKey('max_tokens')) {
      final value = patch['max_tokens'];
      next = value == null || value.toString().trim().isEmpty
          ? next.copyWith(clearMaxTokens: true)
          : next.copyWith(maxTokens: _intFrom(value));
    }
    if (patch.containsKey('chat_model_provider') ||
        patch.containsKey('chat_model_id')) {
      final provider = patch['chat_model_provider']?.toString().trim() ?? '';
      final modelId = patch['chat_model_id']?.toString().trim() ?? '';
      next = provider.isEmpty || modelId.isEmpty
          ? next.copyWith(clearChatModel: true)
          : next.copyWith(chatModelProvider: provider, chatModelId: modelId);
    }

    await ap.updateAssistant(next);
    _pushUndo(
      target: AppControlTargets.currentAssistantSettings,
      payload: {'assistant': before.toJson()},
    );
    return _json({
      'type': 'app_control_result',
      'success': true,
      'target': AppControlTargets.currentAssistantSettings,
      'operation': operation,
      'assistant': _assistantSummary(next),
      'undo_available': true,
    });
  }

  Future<String> _executeMemory(
    Assistant assistant,
    Map<String, dynamic> args,
    String operation,
    String content,
  ) async {
    final mp = contextProvider.read<MemoryProvider>();
    await mp.initialize();
    final before = mp
        .getForAssistant(assistant.id)
        .map((memory) => memory.toJson())
        .toList(growable: false);
    int? changedId;

    if (operation == AppControlOperations.create) {
      final memory = await mp.add(
        assistantId: assistant.id,
        content: content.trim(),
      );
      changedId = memory.id;
    } else if (operation == AppControlOperations.update) {
      final id = _intIdArg(args);
      final existing = mp.memories.where((m) => m.id == id).firstOrNull;
      if (existing == null || existing.assistantId != assistant.id) {
        return _jsonError('memory_not_found', 'Memory not found: $id');
      }
      await mp.update(id: id, content: content.trim());
      changedId = id;
    } else if (operation == AppControlOperations.delete) {
      final id = _intIdArg(args);
      final existing = mp.memories.where((m) => m.id == id).firstOrNull;
      if (existing == null || existing.assistantId != assistant.id) {
        return _jsonError('memory_not_found', 'Memory not found: $id');
      }
      await mp.delete(id: id);
      changedId = id;
    } else if (operation == AppControlOperations.importJson) {
      final items = _jsonListFromContent(content, rootKey: 'memories');
      for (final item in items) {
        final itemContent = (item['content'] ?? '').toString().trim();
        if (itemContent.isEmpty) continue;
        if (item['id'] != null) {
          final id = _intFrom(item['id']);
          final existing = mp.memories.where((m) => m.id == id).firstOrNull;
          if (existing != null && existing.assistantId == assistant.id) {
            await mp.update(id: id, content: itemContent);
            continue;
          }
        }
        await mp.add(assistantId: assistant.id, content: itemContent);
      }
    } else {
      return _jsonError(
        'unsupported_operation',
        'memory supports create, update, delete, import_json, or export_json',
      );
    }
    _pushUndo(
      target: AppControlTargets.currentAssistantMemory,
      payload: {'assistant_id': assistant.id, 'memories': before},
    );
    return _json({
      'type': 'app_control_result',
      'success': true,
      'target': AppControlTargets.currentAssistantMemory,
      'operation': operation,
      'assistant_id': assistant.id,
      if (changedId != null) 'memory_id': changedId,
      'memory_count': mp.getForAssistant(assistant.id).length,
      'undo_available': true,
    });
  }

  Future<String> _executeSkills(
    Assistant assistant,
    Map<String, dynamic> args,
    String operation,
    String content,
  ) async {
    final ap = contextProvider.read<AssistantProvider>();
    final sp = contextProvider.read<SkillProvider>();
    await sp.initialize();
    final before = assistant.skillIds;
    final beforeSkills = sp.skills.map((skill) => skill.toJson()).toList();
    var nextIds = before.toList(growable: true);
    String? createdId;
    if (operation == AppControlOperations.create) {
      createdId = await sp.addSkill(
        name: _title(args, AppControlTargets.currentAssistantSkills),
        description: _reason(
          args,
          AppControlTargets.currentAssistantSkills,
          operation,
        ),
        content: content.trim(),
        triggerKeywords: _stringListArg(args, 'keywords'),
        priority: args.containsKey('priority') ? _intFrom(args['priority']) : 0,
      );
      if (args['activate'] == true && !nextIds.contains(createdId)) {
        nextIds.add(createdId);
      }
    } else if (operation == AppControlOperations.bind) {
      for (final id in _idsArg(args)) {
        if (sp.getById(id) != null && !nextIds.contains(id)) nextIds.add(id);
      }
    } else if (operation == AppControlOperations.unbind) {
      final remove = _idsArg(args).toSet();
      nextIds = nextIds.where((id) => !remove.contains(id)).toList();
    } else if (operation == AppControlOperations.update) {
      final id = _stringIdArg(args);
      final skill = sp.getById(id);
      if (skill == null) {
        return _jsonError('skill_not_found', 'Skill not found: $id');
      }
      final patch = content.trim().startsWith('{')
          ? _jsonObjectContent(content)
          : <String, dynamic>{'content': content};
      await sp.updateSkill(_patchSkill(skill, patch, args));
    } else if (operation == AppControlOperations.delete) {
      final remove = _idsArgOrSingle(args).toSet();
      for (final id in remove) {
        await sp.deleteSkill(id);
      }
      nextIds = nextIds.where((id) => !remove.contains(id)).toList();
    } else if (operation == AppControlOperations.importJson) {
      final items = _jsonListFromContent(content, rootKey: 'skills');
      for (final item in items) {
        final imported = Skill.fromJson(_withGeneratedId(item));
        final existing = imported.id.isEmpty ? null : sp.getById(imported.id);
        if (existing == null) {
          final id = await sp.addSkill(
            name: imported.name,
            description: imported.description,
            content: imported.content,
            triggerKeywords: imported.triggerKeywords,
            priority: imported.priority,
          );
          if (args['activate'] == true && !nextIds.contains(id)) {
            nextIds.add(id);
          }
        } else {
          await sp.updateSkill(_patchSkill(existing, imported.toJson(), args));
        }
      }
    } else if (operation == AppControlOperations.createVersion) {
      final id = _stringIdArg(args);
      final skill = sp.getById(id);
      if (skill == null) {
        return _jsonError('skill_not_found', 'Skill not found: $id');
      }
      final version = SkillVersion(
        id: _uuid.v4(),
        name: skill.name,
        description: skill.description,
        content: skill.content,
        triggerKeywords: skill.triggerKeywords,
        priority: skill.priority,
        createdAt: DateTime.now(),
      );
      await sp.updateSkill(
        skill.copyWith(versions: [...skill.versions, version]),
      );
      createdId = version.id;
    } else if (operation == AppControlOperations.rollbackVersion) {
      final id = _stringIdArg(args);
      final versionId = (args['version_id'] ?? '').toString().trim();
      if (versionId.isEmpty) {
        return _jsonError('invalid_version_id', 'version_id is required');
      }
      final skill = sp.getById(id);
      if (skill == null) {
        return _jsonError('skill_not_found', 'Skill not found: $id');
      }
      final version = skill.versions
          .where((candidate) => candidate.id == versionId)
          .firstOrNull;
      if (version == null) {
        return _jsonError(
          'version_not_found',
          'Skill version not found: $versionId',
        );
      }
      await sp.updateSkill(
        skill.copyWith(
          name: version.name,
          description: version.description,
          content: version.content,
          triggerKeywords: version.triggerKeywords,
          priority: version.priority,
        ),
      );
    } else {
      return _jsonError(
        'unsupported_operation',
        'skills supports create, update, delete, bind, unbind, import_json, export_json, create_version, or rollback_version',
      );
    }
    await ap.updateAssistant(assistant.copyWith(skillIds: nextIds));
    _pushUndo(
      target: AppControlTargets.currentAssistantSkills,
      payload: {
        'assistant_id': assistant.id,
        'skill_ids': before,
        'skills': beforeSkills,
        if (createdId != null) 'created_id': createdId,
      },
    );
    return _json({
      'type': 'app_control_result',
      'success': true,
      'target': AppControlTargets.currentAssistantSkills,
      'operation': operation,
      if (createdId != null) 'skill_id': createdId,
      'active_ids': nextIds,
      'skill_count': sp.skills.length,
      'undo_available': true,
    });
  }

  Future<String> _executeAssistantLocalTools(
    Assistant assistant,
    Map<String, dynamic> args,
    String operation,
  ) async {
    if (operation != AppControlOperations.bind &&
        operation != AppControlOperations.unbind) {
      return _jsonError(
        'unsupported_operation',
        'local tools supports bind or unbind only',
      );
    }
    final ids = _idsArg(args);
    final unknown = ids
        .where((id) => !_availableLocalToolIds.contains(id))
        .toList();
    if (unknown.isNotEmpty) {
      return _jsonError(
        'invalid_tool_id',
        'unknown local tool ids: ${unknown.join(', ')}',
      );
    }
    final before = assistant.localToolIds;
    var next = before.toList(growable: true);
    if (operation == AppControlOperations.bind) {
      for (final id in ids) {
        if (!next.contains(id)) next.add(id);
      }
    } else {
      final remove = ids.toSet();
      next = next.where((id) => !remove.contains(id)).toList();
    }
    await contextProvider.read<AssistantProvider>().updateAssistant(
      assistant.copyWith(localToolIds: next),
    );
    _pushUndo(
      target: AppControlTargets.currentAssistantLocalTools,
      payload: {'assistant_id': assistant.id, 'local_tool_ids': before},
    );
    return _json({
      'type': 'app_control_result',
      'success': true,
      'target': AppControlTargets.currentAssistantLocalTools,
      'operation': operation,
      'active_ids': next,
      'undo_available': true,
    });
  }

  Future<String> _executeAssistantMcp(
    Assistant assistant,
    Map<String, dynamic> args,
    String operation,
  ) async {
    if (operation != AppControlOperations.bind &&
        operation != AppControlOperations.unbind) {
      return _jsonError(
        'unsupported_operation',
        'assistant MCP supports bind or unbind only',
      );
    }
    final provider = contextProvider.read<McpProvider>();
    final ids = _idsArg(args);
    final unknown = ids.where((id) => provider.getById(id) == null).toList();
    if (unknown.isNotEmpty) {
      return _jsonError(
        'invalid_mcp_server_id',
        'unknown MCP server ids: ${unknown.join(', ')}',
      );
    }
    final before = assistant.mcpServerIds;
    var next = before.toList(growable: true);
    if (operation == AppControlOperations.bind) {
      for (final id in ids) {
        if (!next.contains(id)) next.add(id);
      }
    } else {
      final remove = ids.toSet();
      next = next.where((id) => !remove.contains(id)).toList();
    }
    await contextProvider.read<AssistantProvider>().updateAssistant(
      assistant.copyWith(mcpServerIds: next),
    );
    _pushUndo(
      target: AppControlTargets.currentAssistantMcp,
      payload: {'assistant_id': assistant.id, 'mcp_server_ids': before},
    );
    return _json({
      'type': 'app_control_result',
      'success': true,
      'target': AppControlTargets.currentAssistantMcp,
      'operation': operation,
      'active_ids': next,
      'undo_available': true,
    });
  }

  Future<String> _executeQuickPhrase(
    Assistant assistant,
    Map<String, dynamic> args,
    String operation,
    String content,
  ) async {
    final provider = contextProvider.read<QuickPhraseProvider>();
    await provider.initialize();
    final before = provider.phrases.map((phrase) => phrase.toJson()).toList();
    final scope = (args['scope'] ?? 'assistant').toString().trim();
    final isGlobal = scope == 'global';
    String? changedId;

    if (operation == AppControlOperations.create) {
      final phrase = QuickPhrase(
        id: _uuid.v4(),
        title: _title(args, AppControlTargets.quickPhrase),
        content: content.trim(),
        isGlobal: isGlobal,
        assistantId: isGlobal ? null : assistant.id,
      );
      await provider.add(phrase);
      changedId = phrase.id;
    } else if (operation == AppControlOperations.update) {
      final id = _stringIdArg(args);
      final phrase = provider.phrases.where((p) => p.id == id).firstOrNull;
      if (phrase == null) {
        return _jsonError(
          'quick_phrase_not_found',
          'Quick phrase not found: $id',
        );
      }
      final patch = content.trim().startsWith('{')
          ? _jsonObjectContent(content)
          : <String, dynamic>{'content': content};
      await provider.update(_patchQuickPhrase(phrase, patch, args, assistant));
      changedId = id;
    } else if (operation == AppControlOperations.delete) {
      for (final id in _idsArgOrSingle(args)) {
        await provider.delete(id);
        changedId = id;
      }
    } else if (operation == AppControlOperations.reorder) {
      await provider.reorderPhrases(
        oldIndex: _intFrom(args['old_index']),
        newIndex: _intFrom(args['new_index']),
        assistantId: isGlobal ? null : assistant.id,
      );
    } else if (operation == AppControlOperations.importJson) {
      final items = _jsonListFromContent(content, rootKey: 'quick_phrases');
      for (final item in items) {
        final phrase = QuickPhrase.fromJson(_withGeneratedId(item));
        final existing = provider.phrases
            .where((candidate) => candidate.id == phrase.id)
            .firstOrNull;
        if (existing == null) {
          await provider.add(
            phrase.copyWith(
              id: phrase.id.isEmpty ? _uuid.v4() : phrase.id,
              assistantId: phrase.isGlobal
                  ? null
                  : (phrase.assistantId ?? assistant.id),
            ),
          );
        } else {
          await provider.update(phrase);
        }
      }
    } else {
      return _jsonError(
        'unsupported_operation',
        'quick phrase supports create, update, delete, reorder, import_json, or export_json',
      );
    }
    _pushUndo(
      target: AppControlTargets.quickPhrase,
      payload: {'phrases': before},
    );
    return _json({
      'type': 'app_control_result',
      'success': true,
      'target': AppControlTargets.quickPhrase,
      'operation': operation,
      if (changedId != null) 'id': changedId,
      'scope': isGlobal ? 'global' : 'assistant',
      'count': provider.phrases.length,
      'undo_available': true,
    });
  }

  Future<String> _executeInstructionInjection(
    Assistant assistant,
    Map<String, dynamic> args,
    String operation,
    String content,
  ) async {
    final provider = contextProvider.read<InstructionInjectionProvider>();
    await provider.initialize();
    final before = provider.items.map((item) => item.toJson()).toList();
    final beforeActive = provider.activeIdsFor(assistant.id);
    String? changedId;

    if (operation == AppControlOperations.create) {
      final item = InstructionInjection(
        id: _uuid.v4(),
        title: _title(args, AppControlTargets.instructionInjection),
        prompt: content.trim(),
        group: (args['group'] ?? '').toString().trim(),
      );
      await provider.add(item);
      changedId = item.id;
      if (args['activate'] == true) {
        final activeIds = provider
            .activeIdsFor(assistant.id)
            .toList(growable: true);
        if (!activeIds.contains(item.id)) activeIds.add(item.id);
        await provider.setActiveIds(activeIds, assistantId: assistant.id);
      }
    } else if (operation == AppControlOperations.update) {
      final id = _stringIdArg(args);
      final item = provider.items.where((item) => item.id == id).firstOrNull;
      if (item == null) {
        return _jsonError(
          'instruction_not_found',
          'Instruction injection not found: $id',
        );
      }
      final patch = content.trim().startsWith('{')
          ? _jsonObjectContent(content)
          : <String, dynamic>{'prompt': content};
      await provider.update(_patchInstructionInjection(item, patch, args));
      changedId = id;
    } else if (operation == AppControlOperations.delete) {
      for (final id in _idsArgOrSingle(args)) {
        await provider.delete(id);
        changedId = id;
      }
    } else if (operation == AppControlOperations.enable ||
        operation == AppControlOperations.disable) {
      final id = _stringIdArg(args);
      final activeIds = provider
          .activeIdsFor(assistant.id)
          .toList(growable: true);
      if (operation == AppControlOperations.enable) {
        if (!activeIds.contains(id)) activeIds.add(id);
      } else {
        activeIds.remove(id);
      }
      await provider.setActiveIds(activeIds, assistantId: assistant.id);
      changedId = id;
    } else if (operation == AppControlOperations.importJson) {
      final items = _jsonListFromContent(
        content,
        rootKey: 'instruction_injections',
      );
      for (final raw in items) {
        final item = InstructionInjection.fromJson(_withGeneratedId(raw));
        final existing = provider.items
            .where((candidate) => candidate.id == item.id)
            .firstOrNull;
        if (existing == null) {
          await provider.add(
            item.copyWith(id: item.id.isEmpty ? _uuid.v4() : item.id),
          );
        } else {
          await provider.update(item);
        }
      }
    } else {
      return _jsonError(
        'unsupported_operation',
        'instruction injection supports create, update, delete, enable, disable, import_json, or export_json',
      );
    }
    _pushUndo(
      target: AppControlTargets.instructionInjection,
      payload: {
        'assistant_id': assistant.id,
        'items': before,
        'active_ids': beforeActive,
      },
    );
    return _json({
      'type': 'app_control_result',
      'success': true,
      'target': AppControlTargets.instructionInjection,
      'operation': operation,
      if (changedId != null) 'id': changedId,
      'active_ids': provider.activeIdsFor(assistant.id),
      'count': provider.items.length,
      'undo_available': true,
    });
  }

  Future<String> _executeWorldBook(
    Assistant assistant,
    Map<String, dynamic> args,
    String operation,
    String content,
  ) async {
    final provider = contextProvider.read<WorldBookProvider>();
    await provider.initialize();
    final before = provider.books.map((book) => book.toJson()).toList();
    final beforeActive = provider.activeBookIdsFor(assistant.id);
    String? changedId;
    String? changedEntryId;

    if (operation == AppControlOperations.create) {
      final title = _title(args, AppControlTargets.worldBook);
      final entry = WorldBookEntry(
        id: _uuid.v4(),
        name: (args['entry_title'] ?? title).toString().trim(),
        content: content.trim(),
        constantActive: args.containsKey('constant_active')
            ? _boolFrom(args['constant_active'])
            : true,
        keywords: _stringListArg(args, 'keywords'),
      );
      final book = WorldBook(
        id: _uuid.v4(),
        name: title,
        description: _reason(args, AppControlTargets.worldBook, operation),
        enabled: args.containsKey('enabled')
            ? _boolFrom(args['enabled'])
            : true,
        entries: <WorldBookEntry>[entry],
      );
      await provider.addBook(book);
      changedId = book.id;
      changedEntryId = entry.id;
      if (args['activate'] == true) {
        final activeIds = provider
            .activeBookIdsFor(assistant.id)
            .toList(growable: true);
        if (!activeIds.contains(book.id)) activeIds.add(book.id);
        await provider.setActiveBookIds(activeIds, assistantId: assistant.id);
      }
    } else if (operation == AppControlOperations.update) {
      final id = _stringIdArg(args);
      final book = provider.getById(id);
      if (book == null) {
        return _jsonError('world_book_not_found', 'World book not found: $id');
      }
      final patch = content.trim().startsWith('{')
          ? _jsonObjectContent(content)
          : <String, dynamic>{'description': content};
      await provider.updateBook(_patchWorldBook(book, patch, args));
      changedId = id;
    } else if (operation == AppControlOperations.delete) {
      for (final id in _idsArgOrSingle(args)) {
        await provider.deleteBook(id);
        changedId = id;
      }
    } else if (operation == AppControlOperations.enable ||
        operation == AppControlOperations.disable) {
      final id = _stringIdArg(args);
      final book = provider.getById(id);
      if (book == null) {
        return _jsonError('world_book_not_found', 'World book not found: $id');
      }
      if (args['activate'] == true || args['scope'] == 'assistant') {
        final activeIds = provider
            .activeBookIdsFor(assistant.id)
            .toList(growable: true);
        if (operation == AppControlOperations.enable) {
          if (!activeIds.contains(id)) activeIds.add(id);
        } else {
          activeIds.remove(id);
        }
        await provider.setActiveBookIds(activeIds, assistantId: assistant.id);
      } else {
        await provider.updateBook(
          book.copyWith(enabled: operation == AppControlOperations.enable),
        );
      }
      changedId = id;
    } else if (operation == AppControlOperations.addEntry) {
      final bookId = _bookIdArg(args);
      final book = provider.getById(bookId);
      if (book == null) {
        return _jsonError(
          'world_book_not_found',
          'World book not found: $bookId',
        );
      }
      final entry = _worldBookEntryFromArgs(args, content);
      await provider.updateBook(
        book.copyWith(entries: [...book.entries, entry]),
      );
      changedId = bookId;
      changedEntryId = entry.id;
    } else if (operation == AppControlOperations.updateEntry) {
      final bookId = _bookIdArg(args);
      final entryId = (args['entry_id'] ?? '').toString().trim();
      if (entryId.isEmpty) {
        return _jsonError('invalid_entry_id', 'entry_id is required');
      }
      final book = provider.getById(bookId);
      if (book == null) {
        return _jsonError(
          'world_book_not_found',
          'World book not found: $bookId',
        );
      }
      final index = book.entries.indexWhere((entry) => entry.id == entryId);
      if (index < 0) {
        return _jsonError(
          'entry_not_found',
          'World book entry not found: $entryId',
        );
      }
      final patch = content.trim().startsWith('{')
          ? _jsonObjectContent(content)
          : <String, dynamic>{'content': content};
      final entries = List<WorldBookEntry>.from(book.entries);
      entries[index] = _patchWorldBookEntry(entries[index], patch, args);
      await provider.updateBook(book.copyWith(entries: entries));
      changedId = bookId;
      changedEntryId = entryId;
    } else if (operation == AppControlOperations.deleteEntry) {
      final bookId = _bookIdArg(args);
      final entryId = (args['entry_id'] ?? '').toString().trim();
      if (entryId.isEmpty) {
        return _jsonError('invalid_entry_id', 'entry_id is required');
      }
      final book = provider.getById(bookId);
      if (book == null) {
        return _jsonError(
          'world_book_not_found',
          'World book not found: $bookId',
        );
      }
      await provider.updateBook(
        book.copyWith(
          entries: book.entries
              .where((entry) => entry.id != entryId)
              .toList(growable: false),
        ),
      );
      changedId = bookId;
      changedEntryId = entryId;
    } else if (operation == AppControlOperations.importJson) {
      final items = _jsonListFromContent(content, rootKey: 'world_books');
      for (final raw in items) {
        final book = WorldBook.fromJson(_withGeneratedId(raw));
        final normalized = book.copyWith(
          id: book.id.isEmpty ? _uuid.v4() : book.id,
          entries: book.entries
              .map(
                (entry) =>
                    entry.id.isEmpty ? entry.copyWith(id: _uuid.v4()) : entry,
              )
              .toList(growable: false),
        );
        if (provider.getById(normalized.id) == null) {
          await provider.addBook(normalized);
        } else {
          await provider.updateBook(normalized);
        }
      }
    } else {
      return _jsonError(
        'unsupported_operation',
        'world book supports create, update, delete, enable, disable, add_entry, update_entry, delete_entry, import_json, or export_json',
      );
    }
    _pushUndo(
      target: AppControlTargets.worldBook,
      payload: {
        'assistant_id': assistant.id,
        'books': before,
        'active_ids': beforeActive,
      },
    );
    return _json({
      'type': 'app_control_result',
      'success': true,
      'target': AppControlTargets.worldBook,
      'operation': operation,
      if (changedId != null) 'id': changedId,
      if (changedEntryId != null) 'entry_id': changedEntryId,
      'active_ids': provider.activeBookIdsFor(assistant.id),
      'count': provider.books.length,
      'undo_available': true,
    });
  }

  Future<String> _executeMcpServer(
    Map<String, dynamic> args,
    String operation,
  ) async {
    final provider = contextProvider.read<McpProvider>();
    if (operation == AppControlOperations.create ||
        operation == AppControlOperations.update ||
        operation == AppControlOperations.importJson) {
      final content = (args['content'] ?? '').toString();
      if (content.trim().isEmpty) {
        return _jsonError('invalid_content', 'content must not be empty');
      }
      final before = provider.servers.map((server) => server.toJson()).toList();
      try {
        final parsed = _mcpServersFromContent(content);
        if (parsed.isEmpty) {
          return _jsonError(
            'invalid_mcp_config',
            'Invalid MCP config. Expected JSON such as {"mcpServers":{"name":{"command":"...","args":[],"env":{},"disabled":true}}}, a flat server object, or an exported servers list.',
          );
        }
        if (operation == AppControlOperations.importJson) {
          await provider.replaceAllFromConfigs(parsed);
        } else if (operation == AppControlOperations.update) {
          final serverId = (args['server_id'] ?? args['id'] ?? '')
              .toString()
              .trim();
          if (serverId.isEmpty) {
            return _jsonError('invalid_server_id', 'server_id is required');
          }
          final existing = provider.getById(serverId);
          if (existing == null) {
            return _jsonError(
              'server_not_found',
              'MCP server not found: $serverId',
            );
          }
          final next = parsed.length == 1
              ? parsed.single.copyWith(id: existing.id)
              : parsed.where((server) => server.id == serverId).firstOrNull;
          if (next == null) {
            return _jsonError(
              'invalid_mcp_config',
              'No MCP server config matched server_id: $serverId',
            );
          }
          await provider.updateServer(next);
        } else {
          final existingIds = provider.servers.map((s) => s.id).toSet();
          for (final server in parsed) {
            final id = existingIds.contains(server.id) ? _uuid.v4() : server.id;
            await provider.addServerConfig(server.copyWith(id: id));
            existingIds.add(id);
          }
        }
      } on FormatException catch (e) {
        return _jsonError('invalid_mcp_config', e.message);
      } catch (e) {
        return _jsonError('mcp_update_failed', e.toString());
      }
      _pushUndo(
        target: AppControlTargets.mcpServer,
        payload: {'servers': before},
      );
      return _json({
        'type': 'app_control_result',
        'success': true,
        'target': AppControlTargets.mcpServer,
        'operation': operation,
        'server_count': provider.servers.length,
        'undo_available': true,
      });
    }

    final serverId = (args['server_id'] ?? '').toString().trim();
    if (serverId.isEmpty) {
      return _jsonError('invalid_server_id', 'server_id is required');
    }
    final server = provider.getById(serverId);
    if (server == null) {
      return _jsonError('server_not_found', 'MCP server not found: $serverId');
    }
    final toolName = (args['tool_name'] ?? '').toString().trim();
    if (operation == AppControlOperations.enable ||
        operation == AppControlOperations.disable) {
      final enabled = operation == AppControlOperations.enable;
      if (toolName.isEmpty) {
        await provider.updateServer(server.copyWith(enabled: enabled));
        _pushUndo(
          target: AppControlTargets.mcpServer,
          payload: {'server_id': server.id, 'server_enabled': server.enabled},
        );
        return _json({
          'type': 'app_control_result',
          'success': true,
          'target': AppControlTargets.mcpServer,
          'operation': operation,
          'server_id': server.id,
          'enabled': enabled,
          'undo_available': true,
        });
      }
      final tool = _findMcpTool(server, toolName);
      if (tool == null) {
        return _jsonError('tool_not_found', 'MCP tool not found: $toolName');
      }
      await provider.setToolEnabled(server.id, tool.name, enabled);
      _pushUndo(
        target: AppControlTargets.mcpServer,
        payload: {
          'server_id': server.id,
          'tool_name': tool.name,
          'tool_enabled': tool.enabled,
        },
      );
      return _json({
        'type': 'app_control_result',
        'success': true,
        'target': AppControlTargets.mcpServer,
        'operation': operation,
        'server_id': server.id,
        'tool_name': tool.name,
        'enabled': enabled,
        'undo_available': true,
      });
    }
    if (operation == AppControlOperations.setApproval) {
      if (toolName.isEmpty) {
        return _jsonError('invalid_tool_name', 'tool_name is required');
      }
      final tool = _findMcpTool(server, toolName);
      if (tool == null) {
        return _jsonError('tool_not_found', 'MCP tool not found: $toolName');
      }
      final needsApproval = _boolFrom(args['needs_approval']);
      await provider.setToolNeedsApproval(server.id, tool.name, needsApproval);
      _pushUndo(
        target: AppControlTargets.mcpServer,
        payload: {
          'server_id': server.id,
          'tool_name': tool.name,
          'tool_needs_approval': tool.needsApproval,
        },
      );
      return _json({
        'type': 'app_control_result',
        'success': true,
        'target': AppControlTargets.mcpServer,
        'operation': operation,
        'server_id': server.id,
        'tool_name': tool.name,
        'needs_approval': needsApproval,
        'undo_available': true,
      });
    }
    if (operation == AppControlOperations.delete) {
      if (provider.isBuiltinServer(server)) {
        return _jsonError(
          'builtin_mcp_server',
          'Built-in MCP servers cannot be deleted; disable them instead.',
        );
      }
      final before = provider.servers.map((server) => server.toJson()).toList();
      await provider.removeServer(server.id);
      _pushUndo(
        target: AppControlTargets.mcpServer,
        payload: {'servers': before},
      );
      return _json({
        'type': 'app_control_result',
        'success': true,
        'target': AppControlTargets.mcpServer,
        'operation': operation,
        'server_id': server.id,
        'server_count': provider.servers.length,
        'undo_available': true,
      });
    }
    return _jsonError(
      'unsupported_operation',
      'mcp server supports create, update, delete, enable, disable, import_json, export_json, or set_approval only',
    );
  }

  Future<String> _executeSearchSettings(
    Assistant assistant,
    Map<String, dynamic> args,
    String operation,
  ) async {
    if (operation == AppControlOperations.update ||
        operation == AppControlOperations.importJson) {
      final content = (args['content'] ?? '').toString();
      if (content.trim().isEmpty) {
        return _jsonError('invalid_content', 'content must not be empty');
      }
      final settings = contextProvider.read<SettingsProvider>();
      final ap = contextProvider.read<AssistantProvider>();
      final before = {
        'global_enabled': settings.searchEnabled,
        'selected_index': settings.searchServiceSelected,
        'services': settings.searchServices
            .map((service) => service.toJson())
            .toList(growable: false),
        'common': settings.searchCommonOptions.toJson(),
      };
      try {
        final patch = _jsonObjectContent(content);
        if (patch.containsKey('global_enabled')) {
          await settings.setSearchEnabled(_boolFrom(patch['global_enabled']));
        }
        if (patch.containsKey('common') && patch['common'] is Map) {
          await settings.setSearchCommonOptions(
            SearchCommonOptions.fromJson(
              (patch['common'] as Map).cast<String, dynamic>(),
            ),
          );
        }
        if (patch.containsKey('services')) {
          final servicesRaw = patch['services'];
          if (servicesRaw is! List) {
            return _jsonError(
              'invalid_search_config',
              'services must be a JSON array.',
            );
          }
          final services = <SearchServiceOptions>[];
          for (final item in servicesRaw) {
            if (item is! Map) continue;
            final map = item.cast<String, dynamic>();
            map['id'] = (map['id']?.toString().trim().isNotEmpty ?? false)
                ? map['id'].toString().trim()
                : _uuid.v4().substring(0, 8);
            services.add(SearchServiceOptions.fromJson(map));
          }
          if (services.isEmpty) {
            return _jsonError(
              'invalid_search_config',
              'No valid search services found in content.',
            );
          }
          await settings.setSearchServices(services);
        }
        if (patch.containsKey('selected_index')) {
          await settings.setSearchServiceSelected(
            _intFrom(patch['selected_index']),
          );
        }
        if (patch.containsKey('assistant_enabled')) {
          await ap.updateAssistant(
            assistant.copyWith(
              searchEnabled: _boolFrom(patch['assistant_enabled']),
            ),
          );
        }
      } catch (e) {
        return _jsonError('invalid_search_config', e.toString());
      }
      _pushUndo(
        target: AppControlTargets.searchSettings,
        payload: {
          'scope': 'config',
          'assistant_id': assistant.id,
          'assistant_search_enabled': assistant.searchEnabled,
          'settings': before,
        },
      );
      return _json({
        'type': 'app_control_result',
        'success': true,
        'target': AppControlTargets.searchSettings,
        'operation': operation,
        'global_enabled': settings.searchEnabled,
        'assistant_enabled':
            ap.getById(assistant.id)?.searchEnabled ?? assistant.searchEnabled,
        'selected_index': settings.searchServiceSelected,
        'service_count': settings.searchServices.length,
        'undo_available': true,
      });
    }

    if (operation != AppControlOperations.enable &&
        operation != AppControlOperations.disable) {
      return _jsonError(
        'unsupported_operation',
        'search settings supports update, import_json, export_json, enable, or disable only',
      );
    }
    final enabled = operation == AppControlOperations.enable;
    final scope = (args['scope'] ?? 'assistant').toString().trim();
    if (scope == 'global') {
      final settings = contextProvider.read<SettingsProvider>();
      final before = settings.searchEnabled;
      await settings.setSearchEnabled(enabled);
      _pushUndo(
        target: AppControlTargets.searchSettings,
        payload: {'scope': 'global', 'search_enabled': before},
      );
      return _json({
        'type': 'app_control_result',
        'success': true,
        'target': AppControlTargets.searchSettings,
        'operation': operation,
        'scope': 'global',
        'enabled': enabled,
        'undo_available': true,
      });
    }
    final before = assistant.searchEnabled;
    await contextProvider.read<AssistantProvider>().updateAssistant(
      assistant.copyWith(searchEnabled: enabled),
    );
    _pushUndo(
      target: AppControlTargets.searchSettings,
      payload: {
        'scope': 'assistant',
        'assistant_id': assistant.id,
        'search_enabled': before,
      },
    );
    return _json({
      'type': 'app_control_result',
      'success': true,
      'target': AppControlTargets.searchSettings,
      'operation': operation,
      'scope': 'assistant',
      'enabled': enabled,
      'undo_available': true,
    });
  }

  Future<String> _executeAppBundle(
    Assistant assistant,
    Map<String, dynamic> args,
    String operation,
    String content,
  ) async {
    if (operation == AppControlOperations.exportJson) {
      return _exportTarget(AppControlTargets.appBundle, assistant, args);
    }
    if (operation != AppControlOperations.importJson) {
      return _jsonError(
        'unsupported_operation',
        'app bundle supports import_json or export_json only',
      );
    }
    final before = await _bundleSnapshot(assistant);
    final decoded = _jsonObjectContent(content);
    await _importBundle(assistant, decoded);
    _pushUndo(
      target: AppControlTargets.appBundle,
      payload: {'assistant_id': assistant.id, 'bundle': before},
    );
    return _json({
      'type': 'app_control_result',
      'success': true,
      'target': AppControlTargets.appBundle,
      'operation': operation,
      'undo_available': true,
    });
  }

  Future<String> _exportTarget(
    String target,
    Assistant assistant,
    Map<String, dynamic> args,
  ) async {
    final mcpProvider = contextProvider.read<McpProvider>();
    final payload = switch (target) {
      AppControlTargets.currentAssistantSettings => {
        'assistant': assistant.toJson(),
      },
      AppControlTargets.currentAssistantSystemPrompt => {
        'assistant_id': assistant.id,
        'system_prompt': assistant.systemPrompt,
      },
      AppControlTargets.currentAssistantMemory => {
        'memories': await _memorySnapshot(assistant.id),
      },
      AppControlTargets.currentAssistantSkills => await _skillSnapshot(
        assistant,
      ),
      AppControlTargets.quickPhrase => await _quickPhraseSnapshot(assistant),
      AppControlTargets.instructionInjection =>
        await _instructionInjectionSnapshot(assistant),
      AppControlTargets.worldBook => await _worldBookSnapshot(assistant),
      AppControlTargets.mcpServer => {
        'servers': mcpProvider.servers
            .map((server) => server.toJson())
            .toList(growable: false),
      },
      AppControlTargets.searchSettings => _searchSettingsSnapshot(assistant),
      AppControlTargets.appBundle => await _bundleSnapshot(assistant),
      _ => <String, dynamic>{},
    };
    if (payload.isEmpty) {
      return _jsonError(
        'unsupported_target',
        'unsupported export target: $target',
      );
    }
    return _json({
      'type': 'app_control_export',
      'target': target,
      'format': 'json',
      'payload': payload,
      'content': const JsonEncoder.withIndent('  ').convert(payload),
    });
  }

  String _inspectAuditLog() => _json({
    'type': 'app_control_audit_log',
    'items': _auditLog.map((entry) => entry.toJson()).toList(),
    'undo_stack_count': _undoStack.length,
  });

  Future<String> _undoLast(Assistant? assistant) async {
    if (assistant?.appControlEnabled != true) {
      return _jsonError(
        'permission_required',
        'Current assistant has not been granted 神经权能网关 permission.',
      );
    }
    if (_undoStack.isEmpty) {
      return _jsonError('nothing_to_undo', 'No 神经权能网关 action can be undone.');
    }
    final entry = _undoStack.removeLast();
    switch (entry.target) {
      case AppControlTargets.currentAssistantSettings:
        final raw = entry.payload['assistant'];
        if (raw is! Map) {
          return _jsonError('undo_failed', 'Assistant snapshot is missing.');
        }
        await contextProvider.read<AssistantProvider>().updateAssistant(
          Assistant.fromJson(raw.cast<String, dynamic>()),
        );
        return _json({
          'type': 'app_control_undo',
          'success': true,
          'target': entry.target,
        });
      case AppControlTargets.currentAssistantMemory:
        await _restoreMemories(entry.payload);
        return _json({
          'type': 'app_control_undo',
          'success': true,
          'target': entry.target,
        });
      case AppControlTargets.currentAssistantSystemPrompt:
        final ap = contextProvider.read<AssistantProvider>();
        final id = entry.payload['assistant_id']?.toString();
        final restored = entry.payload['system_prompt']?.toString() ?? '';
        final current = id == null ? null : ap.getById(id);
        if (current == null) {
          return _jsonError('undo_failed', 'Assistant no longer exists.');
        }
        await ap.updateAssistant(current.copyWith(systemPrompt: restored));
        return _json({
          'type': 'app_control_undo',
          'success': true,
          'target': entry.target,
        });
      case AppControlTargets.currentAssistantSkills:
        final ap = contextProvider.read<AssistantProvider>();
        final sp = contextProvider.read<SkillProvider>();
        final id = entry.payload['assistant_id']?.toString();
        final current = id == null ? null : ap.getById(id);
        if (current == null) {
          return _jsonError('undo_failed', 'Assistant no longer exists.');
        }
        final ids = _stringListFromDynamic(entry.payload['skill_ids']);
        await ap.updateAssistant(current.copyWith(skillIds: ids));
        if (entry.payload['skills'] is List) {
          await _restoreSkills(entry.payload['skills'] as List);
        } else {
          final createdId = entry.payload['created_id']?.toString();
          if (createdId != null && createdId.isNotEmpty) {
            await sp.deleteSkill(createdId);
          }
        }
        return _json({
          'type': 'app_control_undo',
          'success': true,
          'target': entry.target,
        });
      case AppControlTargets.currentAssistantLocalTools:
        final ap = contextProvider.read<AssistantProvider>();
        final id = entry.payload['assistant_id']?.toString();
        final current = id == null ? null : ap.getById(id);
        if (current == null) {
          return _jsonError('undo_failed', 'Assistant no longer exists.');
        }
        await ap.updateAssistant(
          current.copyWith(
            localToolIds: _stringListFromDynamic(
              entry.payload['local_tool_ids'],
            ),
          ),
        );
        return _json({
          'type': 'app_control_undo',
          'success': true,
          'target': entry.target,
        });
      case AppControlTargets.currentAssistantMcp:
        final ap = contextProvider.read<AssistantProvider>();
        final id = entry.payload['assistant_id']?.toString();
        final current = id == null ? null : ap.getById(id);
        if (current == null) {
          return _jsonError('undo_failed', 'Assistant no longer exists.');
        }
        await ap.updateAssistant(
          current.copyWith(
            mcpServerIds: _stringListFromDynamic(
              entry.payload['mcp_server_ids'],
            ),
          ),
        );
        return _json({
          'type': 'app_control_undo',
          'success': true,
          'target': entry.target,
        });
      case AppControlTargets.quickPhrase:
        await _restoreQuickPhrases(entry.payload['phrases']);
        return _json({
          'type': 'app_control_undo',
          'success': true,
          'target': entry.target,
        });
      case AppControlTargets.instructionInjection:
        await _restoreInstructionInjections(entry.payload);
        return _json({
          'type': 'app_control_undo',
          'success': true,
          'target': entry.target,
        });
      case AppControlTargets.worldBook:
        await _restoreWorldBooks(entry.payload);
        return _json({
          'type': 'app_control_undo',
          'success': true,
          'target': entry.target,
        });
      case AppControlTargets.mcpServer:
        final provider = contextProvider.read<McpProvider>();
        if (entry.payload.containsKey('servers')) {
          final servers = entry.payload['servers'];
          if (servers is! List) {
            return _jsonError('undo_failed', 'MCP server snapshot is missing.');
          }
          await provider.replaceAllFromJson(jsonEncode(servers));
          return _json({
            'type': 'app_control_undo',
            'success': true,
            'target': entry.target,
          });
        }
        final serverId = entry.payload['server_id']?.toString();
        final server = serverId == null ? null : provider.getById(serverId);
        if (server == null) {
          return _jsonError('undo_failed', 'MCP server no longer exists.');
        }
        final toolName = entry.payload['tool_name']?.toString();
        if (toolName != null && toolName.isNotEmpty) {
          if (entry.payload.containsKey('tool_enabled')) {
            await provider.setToolEnabled(
              server.id,
              toolName,
              _boolFrom(entry.payload['tool_enabled']),
            );
          }
          if (entry.payload.containsKey('tool_needs_approval')) {
            await provider.setToolNeedsApproval(
              server.id,
              toolName,
              _boolFrom(entry.payload['tool_needs_approval']),
            );
          }
        } else if (entry.payload.containsKey('server_enabled')) {
          await provider.updateServer(
            server.copyWith(
              enabled: _boolFrom(entry.payload['server_enabled']),
            ),
          );
        }
        return _json({
          'type': 'app_control_undo',
          'success': true,
          'target': entry.target,
        });
      case AppControlTargets.searchSettings:
        final scope = entry.payload['scope']?.toString();
        if (scope == 'config') {
          final settingsSnapshot = entry.payload['settings'];
          if (settingsSnapshot is! Map) {
            return _jsonError(
              'undo_failed',
              'Search settings snapshot is missing.',
            );
          }
          final settingsMap = settingsSnapshot.cast<String, dynamic>();
          final settings = contextProvider.read<SettingsProvider>();
          final ap = contextProvider.read<AssistantProvider>();
          final servicesRaw = settingsMap['services'];
          if (servicesRaw is List) {
            final services = <SearchServiceOptions>[];
            for (final item in servicesRaw) {
              if (item is! Map) continue;
              services.add(
                SearchServiceOptions.fromJson(item.cast<String, dynamic>()),
              );
            }
            if (services.isNotEmpty) await settings.setSearchServices(services);
          }
          final commonRaw = settingsMap['common'];
          if (commonRaw is Map) {
            await settings.setSearchCommonOptions(
              SearchCommonOptions.fromJson(commonRaw.cast<String, dynamic>()),
            );
          }
          if (settingsMap.containsKey('selected_index')) {
            await settings.setSearchServiceSelected(
              _intFrom(settingsMap['selected_index']),
            );
          }
          if (settingsMap.containsKey('global_enabled')) {
            await settings.setSearchEnabled(
              _boolFrom(settingsMap['global_enabled']),
            );
          }
          final id = entry.payload['assistant_id']?.toString();
          final current = id == null ? null : ap.getById(id);
          if (current != null &&
              entry.payload.containsKey('assistant_search_enabled')) {
            await ap.updateAssistant(
              current.copyWith(
                searchEnabled: _boolFrom(
                  entry.payload['assistant_search_enabled'],
                ),
              ),
            );
          }
        } else if (scope == 'global') {
          await contextProvider.read<SettingsProvider>().setSearchEnabled(
            _boolFrom(entry.payload['search_enabled']),
          );
        } else {
          final ap = contextProvider.read<AssistantProvider>();
          final id = entry.payload['assistant_id']?.toString();
          final current = id == null ? null : ap.getById(id);
          if (current == null) {
            return _jsonError('undo_failed', 'Assistant no longer exists.');
          }
          await ap.updateAssistant(
            current.copyWith(
              searchEnabled: _boolFrom(entry.payload['search_enabled']),
            ),
          );
        }
        return _json({
          'type': 'app_control_undo',
          'success': true,
          'target': entry.target,
        });
      case AppControlTargets.appBundle:
        final bundle = entry.payload['bundle'];
        if (bundle is! Map) {
          return _jsonError('undo_failed', 'App bundle snapshot is missing.');
        }
        final assistantId = entry.payload['assistant_id']?.toString();
        final ap = contextProvider.read<AssistantProvider>();
        final current = assistantId == null ? null : ap.getById(assistantId);
        if (current == null) {
          return _jsonError('undo_failed', 'Assistant no longer exists.');
        }
        await _importBundle(current, bundle.cast<String, dynamic>());
        return _json({
          'type': 'app_control_undo',
          'success': true,
          'target': entry.target,
        });
      default:
        return _jsonError(
          'undo_failed',
          'Unsupported undo target: ${entry.target}',
        );
    }
  }

  String? _validateMutationArgs(
    Map<String, dynamic> args,
    Assistant? assistant,
  ) {
    if (assistant == null) {
      return _jsonError('assistant_unavailable', 'No current assistant found.');
    }
    final target = (args['target'] ?? '').toString().trim();
    final operation = (args['operation'] ?? '').toString().trim();
    final content = (args['content'] ?? '').toString();
    if (target.isEmpty) {
      return _jsonError('invalid_target', 'target is required');
    }
    if (operation.isEmpty) {
      return _jsonError('invalid_operation', 'operation is required');
    }
    final contentRequired = _contentRequired(target, operation);
    if (contentRequired && content.trim().isEmpty) {
      return _jsonError('invalid_content', 'content must not be empty');
    }
    Map<String, dynamic>? capability;
    for (final item in capabilities) {
      if (item['target'] == target) {
        capability = item;
        break;
      }
    }
    if (capability == null) {
      return _jsonError('unsupported_target', 'unsupported target: $target');
    }
    final operations = (capability['operations'] as List).cast<String>();
    if (!operations.contains(operation)) {
      return _jsonError(
        'unsupported_operation',
        'target $target does not support operation $operation',
      );
    }
    return null;
  }

  bool _contentRequired(String target, String operation) {
    if (target == AppControlTargets.currentAssistantSystemPrompt &&
        operation == AppControlOperations.overwrite) {
      return false;
    }
    if (operation == AppControlOperations.delete ||
        operation == AppControlOperations.reorder ||
        operation == AppControlOperations.exportJson ||
        operation == AppControlOperations.createVersion ||
        operation == AppControlOperations.rollbackVersion ||
        operation == AppControlOperations.deleteEntry ||
        operation == AppControlOperations.enable ||
        operation == AppControlOperations.disable ||
        operation == AppControlOperations.setApproval) {
      return false;
    }
    if (target == AppControlTargets.currentAssistantLocalTools ||
        target == AppControlTargets.currentAssistantMcp ||
        target == AppControlTargets.mcpServer ||
        target == AppControlTargets.searchSettings) {
      return false;
    }
    if (target == AppControlTargets.currentAssistantSkills &&
        operation != AppControlOperations.create &&
        operation != AppControlOperations.update &&
        operation != AppControlOperations.importJson) {
      return false;
    }
    return true;
  }

  void _pushUndo({
    required String target,
    required Map<String, dynamic> payload,
  }) {
    _undoStack.add(
      AppControlUndoEntry(
        id: _uuid.v4(),
        target: target,
        payload: payload,
        createdAt: DateTime.now(),
      ),
    );
    if (_undoStack.length > 20) {
      _undoStack.removeRange(0, _undoStack.length - 20);
    }
  }

  void _recordAudit({
    required String target,
    required String operation,
    required String title,
    required Assistant? assistant,
    required bool success,
    required bool undoable,
  }) {
    _auditLog.add(
      AppControlAuditEntry(
        id: _uuid.v4(),
        target: target,
        operation: operation,
        title: title,
        assistantId: assistant?.id,
        assistantName: assistant?.name,
        createdAt: DateTime.now(),
        success: success,
        undoable: undoable,
      ),
    );
    if (_auditLog.length > 80) {
      _auditLog.removeRange(0, _auditLog.length - 80);
    }
  }

  bool _isJsonError(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map && decoded['type'] == 'app_control_error';
    } catch (_) {
      return false;
    }
  }

  int _intIdArg(Map<String, dynamic> args) => _intFrom(args['id']);

  String _stringIdArg(Map<String, dynamic> args) {
    final id = (args['id'] ?? '').toString().trim();
    if (id.isEmpty) throw ArgumentError('id is required');
    return id;
  }

  String _bookIdArg(Map<String, dynamic> args) {
    final id = (args['book_id'] ?? args['id'] ?? '').toString().trim();
    if (id.isEmpty) throw ArgumentError('book_id is required');
    return id;
  }

  List<String> _idsArgOrSingle(Map<String, dynamic> args) {
    final ids = _stringListArg(args, 'ids');
    if (ids.isNotEmpty) return ids;
    return [_stringIdArg(args)];
  }

  List<Map<String, dynamic>> _jsonListFromContent(
    String content, {
    required String rootKey,
  }) {
    final decoded = jsonDecode(content);
    final raw = decoded is List
        ? decoded
        : decoded is Map && decoded[rootKey] is List
        ? decoded[rootKey] as List
        : decoded is Map
        ? [decoded]
        : const [];
    return raw
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList(growable: false);
  }

  Map<String, dynamic> _withGeneratedId(Map<String, dynamic> raw) => {
    ...raw,
    if ((raw['id'] ?? '').toString().trim().isEmpty) 'id': _uuid.v4(),
  };

  String _appendBlock(String before, String content) {
    final existing = before.trimRight();
    final incoming = content.trim();
    if (existing.isEmpty) return incoming;
    return '$existing\n\n$incoming';
  }

  Skill _patchSkill(
    Skill skill,
    Map<String, dynamic> patch,
    Map<String, dynamic> args,
  ) {
    return skill.copyWith(
      name:
          (patch['name'] ?? args['title'])?.toString().trim().isNotEmpty == true
          ? (patch['name'] ?? args['title']).toString().trim()
          : null,
      description:
          patch.containsKey('description') || args.containsKey('reason')
          ? (patch['description'] ?? args['reason'] ?? '').toString().trim()
          : null,
      content: patch.containsKey('content')
          ? patch['content']?.toString() ?? ''
          : null,
      enabled: patch.containsKey('enabled') || args.containsKey('enabled')
          ? _boolFrom(patch['enabled'] ?? args['enabled'])
          : null,
      triggerKeywords:
          patch.containsKey('triggerKeywords') ||
              patch.containsKey('trigger_keywords') ||
              args.containsKey('keywords')
          ? _stringListFromDynamic(
              patch['triggerKeywords'] ??
                  patch['trigger_keywords'] ??
                  args['keywords'],
            )
          : null,
      priority: patch.containsKey('priority') || args.containsKey('priority')
          ? _intFrom(patch['priority'] ?? args['priority'])
          : null,
    );
  }

  QuickPhrase _patchQuickPhrase(
    QuickPhrase phrase,
    Map<String, dynamic> patch,
    Map<String, dynamic> args,
    Assistant assistant,
  ) {
    final scope = (patch['scope'] ?? args['scope'] ?? '').toString().trim();
    final isGlobal = scope.isEmpty
        ? phrase.isGlobal
        : scope == 'global' || _boolFrom(scope == 'global');
    return phrase.copyWith(
      title:
          (patch['title'] ?? args['title'])?.toString().trim().isNotEmpty ==
              true
          ? (patch['title'] ?? args['title']).toString().trim()
          : null,
      content: patch.containsKey('content')
          ? patch['content']?.toString() ?? ''
          : null,
      isGlobal: isGlobal,
      assistantId: isGlobal
          ? null
          : (patch['assistantId'] ?? patch['assistant_id'] ?? assistant.id)
                .toString(),
    );
  }

  InstructionInjection _patchInstructionInjection(
    InstructionInjection item,
    Map<String, dynamic> patch,
    Map<String, dynamic> args,
  ) {
    return item.copyWith(
      title:
          (patch['title'] ?? args['title'])?.toString().trim().isNotEmpty ==
              true
          ? (patch['title'] ?? args['title']).toString().trim()
          : null,
      prompt: patch.containsKey('prompt') || patch.containsKey('content')
          ? (patch['prompt'] ?? patch['content'] ?? '').toString()
          : null,
      group: patch.containsKey('group') || args.containsKey('group')
          ? (patch['group'] ?? args['group'] ?? '').toString().trim()
          : null,
    );
  }

  WorldBook _patchWorldBook(
    WorldBook book,
    Map<String, dynamic> patch,
    Map<String, dynamic> args,
  ) {
    return book.copyWith(
      name:
          (patch['name'] ?? args['title'])?.toString().trim().isNotEmpty == true
          ? (patch['name'] ?? args['title']).toString().trim()
          : null,
      description:
          patch.containsKey('description') || args.containsKey('reason')
          ? (patch['description'] ?? args['reason'] ?? '').toString()
          : null,
      enabled: patch.containsKey('enabled') || args.containsKey('enabled')
          ? _boolFrom(patch['enabled'] ?? args['enabled'])
          : null,
      entries: patch['entries'] is List
          ? (patch['entries'] as List)
                .whereType<Map>()
                .map(
                  (entry) => WorldBookEntry.fromJson(
                    _withGeneratedId(entry.cast<String, dynamic>()),
                  ),
                )
                .toList(growable: false)
          : null,
    );
  }

  WorldBookEntry _worldBookEntryFromArgs(
    Map<String, dynamic> args,
    String content,
  ) {
    final patch = content.trim().startsWith('{')
        ? _jsonObjectContent(content)
        : <String, dynamic>{'content': content};
    return _patchWorldBookEntry(
      WorldBookEntry(
        id: _uuid.v4(),
        name: _title(args, AppControlTargets.worldBook),
      ),
      patch,
      args,
    );
  }

  WorldBookEntry _patchWorldBookEntry(
    WorldBookEntry entry,
    Map<String, dynamic> patch,
    Map<String, dynamic> args,
  ) {
    return entry.copyWith(
      name:
          (patch['name'] ?? patch['title'] ?? args['title'])
                  ?.toString()
                  .trim()
                  .isNotEmpty ==
              true
          ? (patch['name'] ?? patch['title'] ?? args['title']).toString().trim()
          : null,
      content: patch.containsKey('content')
          ? patch['content']?.toString() ?? ''
          : null,
      enabled: patch.containsKey('enabled') || args.containsKey('enabled')
          ? _boolFrom(patch['enabled'] ?? args['enabled'])
          : null,
      priority: patch.containsKey('priority') || args.containsKey('priority')
          ? _intFrom(patch['priority'] ?? args['priority'])
          : null,
      keywords: patch.containsKey('keywords') || args.containsKey('keywords')
          ? _stringListFromDynamic(patch['keywords'] ?? args['keywords'])
          : null,
      useRegex: patch.containsKey('useRegex') || patch.containsKey('use_regex')
          ? _boolFrom(patch['useRegex'] ?? patch['use_regex'])
          : null,
      caseSensitive:
          patch.containsKey('caseSensitive') ||
              patch.containsKey('case_sensitive')
          ? _boolFrom(patch['caseSensitive'] ?? patch['case_sensitive'])
          : null,
      constantActive:
          patch.containsKey('constantActive') ||
              patch.containsKey('constant_active')
          ? _boolFrom(patch['constantActive'] ?? patch['constant_active'])
          : null,
      scanDepth:
          patch.containsKey('scanDepth') || patch.containsKey('scan_depth')
          ? _intFrom(patch['scanDepth'] ?? patch['scan_depth'])
          : null,
      injectDepth:
          patch.containsKey('injectDepth') || patch.containsKey('inject_depth')
          ? _intFrom(patch['injectDepth'] ?? patch['inject_depth'])
          : null,
      position: patch.containsKey('position')
          ? WorldBookInjectionPositionJson.fromJson(patch['position'])
          : null,
      role: patch.containsKey('role')
          ? WorldBookInjectionRoleJson.fromJson(patch['role'])
          : null,
    );
  }

  String _title(Map<String, dynamic> args, String target) {
    final explicit = (args['title'] ?? '').toString().trim();
    if (explicit.isNotEmpty) return explicit;
    return switch (target) {
      AppControlTargets.currentAssistantSettings => 'Assistant Settings',
      AppControlTargets.currentAssistantSystemPrompt => '神经权能网关导入',
      AppControlTargets.currentAssistantMemory => 'Memory',
      AppControlTargets.currentAssistantSkills => 'AI Imported Skill',
      AppControlTargets.quickPhrase => 'AI Imported Quick Phrase',
      AppControlTargets.instructionInjection => 'AI Imported Instruction',
      AppControlTargets.worldBook => 'AI Imported World Book',
      _ => '神经权能网关操作',
    };
  }

  String _reason(Map<String, dynamic> args, String target, String operation) {
    final explicit = (args['reason'] ?? '').toString().trim();
    if (explicit.isNotEmpty) return explicit;
    return 'Apply $operation to $target from chat content.';
  }

  Future<List<Map<String, dynamic>>> _memorySnapshot(String assistantId) async {
    final provider = contextProvider.read<MemoryProvider>();
    await provider.initialize();
    return provider
        .getForAssistant(assistantId)
        .map((memory) => memory.toJson())
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> _skillSnapshot(Assistant assistant) async {
    final provider = contextProvider.read<SkillProvider>();
    await provider.initialize();
    return {
      'active_ids': assistant.skillIds,
      'skills': provider.skills.map((skill) => skill.toJson()).toList(),
    };
  }

  Future<Map<String, dynamic>> _quickPhraseSnapshot(Assistant assistant) async {
    final provider = contextProvider.read<QuickPhraseProvider>();
    await provider.initialize();
    return {
      'phrases': provider.phrases.map((phrase) => phrase.toJson()).toList(),
      'assistant_id': assistant.id,
    };
  }

  Future<Map<String, dynamic>> _instructionInjectionSnapshot(
    Assistant assistant,
  ) async {
    final provider = contextProvider.read<InstructionInjectionProvider>();
    await provider.initialize();
    return {
      'items': provider.items.map((item) => item.toJson()).toList(),
      'active_ids': provider.activeIdsFor(assistant.id),
      'assistant_id': assistant.id,
    };
  }

  Future<Map<String, dynamic>> _worldBookSnapshot(Assistant assistant) async {
    final provider = contextProvider.read<WorldBookProvider>();
    await provider.initialize();
    return {
      'books': provider.books.map((book) => book.toJson()).toList(),
      'active_ids': provider.activeBookIdsFor(assistant.id),
      'assistant_id': assistant.id,
    };
  }

  Map<String, dynamic> _searchSettingsSnapshot(Assistant assistant) {
    final settings = contextProvider.read<SettingsProvider>();
    return {
      'global_enabled': settings.searchEnabled,
      'assistant_enabled': assistant.searchEnabled,
      'selected_index': settings.searchServiceSelected,
      'services': settings.searchServices
          .map((service) => service.toJson())
          .toList(growable: false),
      'common': settings.searchCommonOptions.toJson(),
    };
  }

  Future<Map<String, dynamic>> _bundleSnapshot(Assistant assistant) async {
    final mcpProvider = contextProvider.read<McpProvider>();
    return {
      'format': 'kelivo.app_control_bundle.v1',
      'assistant': assistant.toJson(),
      'memories': await _memorySnapshot(assistant.id),
      'skills': await _skillSnapshot(assistant),
      'quick_phrases': await _quickPhraseSnapshot(assistant),
      'instruction_injections': await _instructionInjectionSnapshot(assistant),
      'world_books': await _worldBookSnapshot(assistant),
      'mcp_servers': mcpProvider.servers
          .map((server) => server.toJson())
          .toList(growable: false),
      'search_settings': _searchSettingsSnapshot(assistant),
    };
  }

  Future<void> _importBundle(
    Assistant assistant,
    Map<String, dynamic> bundle,
  ) async {
    final ap = contextProvider.read<AssistantProvider>();
    final mcpProvider = contextProvider.read<McpProvider>();
    final assistantRaw = bundle['assistant'];
    if (assistantRaw is Map) {
      await ap.updateAssistant(
        Assistant.fromJson(assistantRaw.cast<String, dynamic>()),
      );
    }
    if (bundle['memories'] is List) {
      await _restoreMemories({
        'assistant_id': assistant.id,
        'memories': bundle['memories'],
      });
    }
    if (bundle['skills'] is Map) {
      final skillsBundle = (bundle['skills'] as Map).cast<String, dynamic>();
      await _restoreSkills((skillsBundle['skills'] as List?) ?? const []);
      final current = ap.getById(assistant.id);
      if (current != null) {
        await ap.updateAssistant(
          current.copyWith(
            skillIds: _stringListFromDynamic(skillsBundle['active_ids']),
          ),
        );
      }
    }
    if (bundle['quick_phrases'] is Map) {
      await _restoreQuickPhrases((bundle['quick_phrases'] as Map)['phrases']);
    }
    if (bundle['instruction_injections'] is Map) {
      await _restoreInstructionInjections(
        (bundle['instruction_injections'] as Map).cast<String, dynamic>(),
      );
    }
    if (bundle['world_books'] is Map) {
      await _restoreWorldBooks(
        (bundle['world_books'] as Map).cast<String, dynamic>(),
      );
    }
    if (bundle['mcp_servers'] is List) {
      await mcpProvider.replaceAllFromJson(jsonEncode(bundle['mcp_servers']));
    }
    if (bundle['search_settings'] is Map) {
      final current = ap.getById(assistant.id) ?? assistant;
      await _executeSearchSettings(current, {
        'content': jsonEncode(bundle['search_settings']),
      }, AppControlOperations.importJson);
    }
  }

  Future<void> _restoreMemories(Map<String, dynamic> payload) async {
    final assistantId = payload['assistant_id']?.toString();
    final memories = payload['memories'];
    if (assistantId == null || memories is! List) return;
    final provider = contextProvider.read<MemoryProvider>();
    await provider.initialize();
    for (final memory in provider.getForAssistant(assistantId)) {
      await provider.delete(id: memory.id);
    }
    for (final raw in memories.whereType<Map>()) {
      final item = raw.cast<String, dynamic>();
      final content = (item['content'] ?? '').toString();
      if (content.trim().isEmpty) continue;
      await provider.add(assistantId: assistantId, content: content);
    }
  }

  Future<void> _restoreSkills(List rawSkills) async {
    final provider = contextProvider.read<SkillProvider>();
    await provider.initialize();
    for (final skill in provider.skills.toList()) {
      await provider.deleteSkill(skill.id);
    }
    for (final raw in rawSkills.whereType<Map>()) {
      final skill = Skill.fromJson(raw.cast<String, dynamic>());
      final id = await provider.addSkill(
        name: skill.name,
        description: skill.description,
        content: skill.content,
        triggerKeywords: skill.triggerKeywords,
        priority: skill.priority,
      );
      final created = provider.getById(id);
      if (created != null && skill.versions.isNotEmpty) {
        await provider.updateSkill(created.copyWith(versions: skill.versions));
      }
    }
  }

  Future<void> _restoreQuickPhrases(dynamic rawPhrases) async {
    if (rawPhrases is! List) return;
    final provider = contextProvider.read<QuickPhraseProvider>();
    await provider.initialize();
    await provider.clear();
    for (final raw in rawPhrases.whereType<Map>()) {
      await provider.add(QuickPhrase.fromJson(raw.cast<String, dynamic>()));
    }
  }

  Future<void> _restoreInstructionInjections(
    Map<String, dynamic> payload,
  ) async {
    final items = payload['items'];
    if (items is! List) return;
    final provider = contextProvider.read<InstructionInjectionProvider>();
    await provider.initialize();
    await provider.clear();
    final restored = items
        .whereType<Map>()
        .map(
          (raw) => InstructionInjection.fromJson(raw.cast<String, dynamic>()),
        )
        .toList(growable: false);
    await provider.addMany(restored);
    await provider.setActiveIds(
      _stringListFromDynamic(payload['active_ids']),
      assistantId: payload['assistant_id']?.toString(),
    );
  }

  Future<void> _restoreWorldBooks(Map<String, dynamic> payload) async {
    final books = payload['books'];
    if (books is! List) return;
    final provider = contextProvider.read<WorldBookProvider>();
    await provider.initialize();
    await provider.clear();
    for (final raw in books.whereType<Map>()) {
      await provider.addBook(WorldBook.fromJson(raw.cast<String, dynamic>()));
    }
    await provider.setActiveBookIds(
      _stringListFromDynamic(payload['active_ids']),
      assistantId: payload['assistant_id']?.toString(),
    );
  }

  String _preview(String text, [int max = 500]) {
    final trimmed = text.trim();
    if (trimmed.length <= max) return trimmed;
    return '${trimmed.substring(0, max)}...';
  }

  Map<String, dynamic> _jsonObjectContent(String content) {
    final decoded = jsonDecode(content);
    if (decoded is Map) return decoded.cast<String, dynamic>();
    throw const FormatException('content must be a JSON object');
  }

  bool _boolFrom(dynamic raw) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    final value = raw?.toString().trim().toLowerCase() ?? '';
    if (value == 'true' || value == '1' || value == 'yes' || value == 'on') {
      return true;
    }
    if (value == 'false' || value == '0' || value == 'no' || value == 'off') {
      return false;
    }
    throw ArgumentError('Expected boolean value, got $raw');
  }

  int _intFrom(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    final parsed = int.tryParse(raw?.toString().trim() ?? '');
    if (parsed != null) return parsed;
    throw ArgumentError('Expected integer value, got $raw');
  }

  double _doubleFrom(dynamic raw) {
    if (raw is num) return raw.toDouble();
    final parsed = double.tryParse(raw?.toString().trim() ?? '');
    if (parsed != null) return parsed;
    throw ArgumentError('Expected numeric value, got $raw');
  }

  List<String> _idsArg(Map<String, dynamic> args) {
    final ids = _stringListArg(args, 'ids');
    if (ids.isEmpty) throw ArgumentError('ids must not be empty');
    return ids;
  }

  List<String> _stringListArg(Map<String, dynamic> args, String key) =>
      _stringListFromDynamic(args[key]);

  List<String> _stringListFromDynamic(dynamic raw) {
    if (raw == null) return const <String>[];
    if (raw is List) {
      return raw
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    final text = raw.toString().trim();
    if (text.isEmpty) return const <String>[];
    return text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  McpToolConfig? _findMcpTool(McpServerConfig server, String toolName) {
    for (final tool in server.tools) {
      if (tool.name == toolName) return tool;
    }
    return null;
  }

  List<McpServerConfig> _mcpServersFromContent(String content) {
    final decoded = jsonDecode(content);
    final configs = <McpServerConfig>[];

    Iterable<MapEntry<String, dynamic>> mapEntries(Map<dynamic, dynamic> map) {
      return map.entries.map(
        (entry) => MapEntry(entry.key.toString(), entry.value),
      );
    }

    bool looksLikeSingleServer(Map<dynamic, dynamic> map) {
      const configKeys = {
        'id',
        'name',
        'type',
        'transport',
        'command',
        'args',
        'env',
        'url',
        'baseUrl',
        'headers',
        'enabled',
        'disabled',
        'isActive',
        'workingDirectory',
      };
      return map.keys.any((key) => configKeys.contains(key.toString()));
    }

    bool enabledFromConfig(Map<String, dynamic> cfg) {
      if (cfg.containsKey('disabled')) return !_boolFrom(cfg['disabled']);
      if (cfg.containsKey('enabled')) return _boolFrom(cfg['enabled']);
      if (cfg.containsKey('isActive')) return _boolFrom(cfg['isActive']);
      return true;
    }

    void addOne(Map<dynamic, dynamic> rawMap, String fallbackId) {
      final cfg = rawMap.cast<String, dynamic>();
      final explicitId = (cfg['id'] ?? '').toString().trim();
      final id = explicitId.isNotEmpty
          ? explicitId
          : (fallbackId.trim().isEmpty ? _uuid.v4() : fallbackId.trim());
      final type = (cfg['type'] ?? cfg['transport'] ?? '')
          .toString()
          .toLowerCase();
      final enabled = enabledFromConfig(cfg);
      final name = (cfg['name'] ?? id).toString().trim();
      if (type == 'inmemory') {
        configs.add(
          McpServerConfig(
            id: id,
            enabled: enabled,
            name: name.isEmpty ? id : name,
            transport: McpTransportType.inmemory,
          ),
        );
        return;
      }
      if (type == 'stdio' || cfg.containsKey('command')) {
        final command = (cfg['command'] ?? '').toString().trim();
        if (command.isEmpty) return;
        configs.add(
          McpServerConfig(
            id: id,
            enabled: enabled,
            name: name.isEmpty ? id : name,
            transport: McpTransportType.stdio,
            command: command,
            args: _stringListFromDynamic(cfg['args']),
            env: _stringMapFromDynamic(cfg['env']),
            workingDirectory:
                (cfg['workingDirectory'] ?? '').toString().trim().isEmpty
                ? null
                : (cfg['workingDirectory'] ?? '').toString().trim(),
          ),
        );
        return;
      }
      final transport = type.contains('http')
          ? McpTransportType.http
          : McpTransportType.sse;
      final url = (cfg['url'] ?? cfg['baseUrl'] ?? '').toString().trim();
      if (url.isEmpty) return;
      configs.add(
        McpServerConfig(
          id: id,
          enabled: enabled,
          name: name.isEmpty ? id : name,
          transport: transport,
          url: url,
          headers: _stringMapFromDynamic(cfg['headers']),
        ),
      );
    }

    void addFromUiMap(Map<dynamic, dynamic> map) {
      if (looksLikeSingleServer(map)) {
        addOne(map, (map['id'] ?? map['name'] ?? '').toString());
        return;
      }
      for (final entry in mapEntries(map)) {
        final raw = entry.value;
        if (raw is! Map) continue;
        addOne(raw, entry.key);
      }
    }

    if (decoded is List) {
      for (final item in decoded) {
        if (item is! Map) continue;
        final map = item.cast<String, dynamic>();
        final transport = (map['transport'] ?? map['type'] ?? '')
            .toString()
            .toLowerCase();
        if (transport == 'streamablehttp' || transport.contains('http')) {
          map['transport'] = 'http';
        } else if (transport == 'stdio') {
          map['transport'] = 'stdio';
        } else if (transport == 'inmemory') {
          map['transport'] = 'inmemory';
        } else {
          map['transport'] = 'sse';
        }
        configs.add(McpServerConfig.fromJson(map));
      }
    } else if (decoded is Map && decoded['servers'] is List) {
      final servers = decoded['servers'] as List;
      for (final item in servers) {
        if (item is! Map) continue;
        configs.addAll(_mcpServersFromContent(jsonEncode([item])));
      }
    } else if (decoded is Map && decoded['mcpServers'] is Map) {
      addFromUiMap(decoded['mcpServers'] as Map);
    } else if (decoded is Map) {
      addFromUiMap(decoded);
    }

    return configs
        .where(
          (server) =>
              server.transport == McpTransportType.inmemory ||
              server.transport == McpTransportType.stdio ||
              server.url.trim().isNotEmpty,
        )
        .toList(growable: false);
  }

  Map<String, String> _stringMapFromDynamic(dynamic raw) {
    if (raw is Map) {
      return raw.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    }
    return const <String, String>{};
  }

  Map<String, dynamic> _assistantSummary(Assistant assistant) => {
    'id': assistant.id,
    'name': assistant.name,
    'chat_model_provider': assistant.chatModelProvider,
    'chat_model_id': assistant.chatModelId,
    'search_enabled': assistant.searchEnabled,
    'memory_enabled': assistant.enableMemory,
    'recent_chats_reference_enabled': assistant.enableRecentChatsReference,
    'app_control_enabled': assistant.appControlEnabled,
    'local_tool_ids': assistant.localToolIds,
    'mcp_server_ids': assistant.mcpServerIds,
    'skill_ids': assistant.skillIds,
    'system_prompt_preview': _preview(assistant.systemPrompt),
  };

  static const List<String> _availableLocalToolIds = <String>[
    LocalToolNames.timeInfo,
    LocalToolNames.clipboard,
    LocalToolNames.textToSpeech,
    LocalToolNames.askUser,
    LocalToolNames.calculate,
  ];

  String _json(Map<String, dynamic> value) => jsonEncode(value);

  String _jsonError(String error, String message) => jsonEncode({
    'type': 'app_control_error',
    'error': error,
    'message': message,
  });
}
