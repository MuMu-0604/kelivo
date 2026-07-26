import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/assistant.dart';
import '../../models/instruction_injection.dart';
import '../../models/quick_phrase.dart';
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

class AppControlService {
  AppControlService({required this.contextProvider});

  static const String systemPrompt = '''
Kelivo App Control is available for this assistant. Use the `kelivo_app_control` tool when the user asks you to import, append, overwrite, create, inspect, configure, or undo Kelivo app data from chat content or generated content.

Supported targets:
- `current_assistant.settings`: update core assistant settings from structured JSON content.
- `current_assistant.system_prompt`: append or overwrite the current assistant system prompt.
- `current_assistant.memory`: create a memory for the current assistant.
- `current_assistant.skills`: create a skill, or bind/unbind existing skills to the current assistant.
- `current_assistant.local_tools`: bind/unbind local tools such as time, clipboard, TTS, ask-user, or calculator.
- `current_assistant.mcp`: bind/unbind MCP servers for the current assistant.
- `quick_phrase`: create a global or assistant-specific quick phrase.
- `instruction_injection`: create an instruction injection card and optionally activate it for the current assistant.
- `world_book`: create a world book with one entry and optionally activate it for the current assistant.
- `mcp_server`: enable/disable MCP servers and enable/disable tools or approval for MCP tools.
- `search_settings`: enable/disable built-in search globally or for the current assistant.

Prefer `plan_action` when the user's wording is ambiguous or the change is large. Use `execute_action` only when the user clearly asks to apply/import/save the content. Include concise `title` and `reason` fields so Kelivo can show a useful confirmation. Use `undo_last` when the user asks to undo the last app control operation.
''';

  static const List<Map<String, dynamic>> capabilities = [
    {
      'target': AppControlTargets.currentAssistantSettings,
      'operations': [AppControlOperations.update],
      'description':
          'Update current assistant settings from JSON content such as name, model binding, search, memory, context size, temperature, max tokens, or App Control permission.',
      'requires_confirmation': true,
      'undoable': true,
    },
    {
      'target': AppControlTargets.currentAssistantSystemPrompt,
      'operations': [
        AppControlOperations.append,
        AppControlOperations.overwrite,
      ],
      'description':
          'Append to or overwrite the current assistant system prompt.',
      'requires_confirmation': true,
      'undoable': true,
    },
    {
      'target': AppControlTargets.currentAssistantMemory,
      'operations': [AppControlOperations.create],
      'description': 'Create a memory for the current assistant.',
      'requires_confirmation': true,
      'undoable': true,
    },
    {
      'target': AppControlTargets.currentAssistantSkills,
      'operations': [
        AppControlOperations.create,
        AppControlOperations.bind,
        AppControlOperations.unbind,
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
      'operations': [AppControlOperations.create],
      'description':
          'Create a global or assistant-specific quick phrase from content.',
      'requires_confirmation': true,
      'undoable': true,
    },
    {
      'target': AppControlTargets.instructionInjection,
      'operations': [AppControlOperations.create],
      'description': 'Create an instruction injection card; can be activated.',
      'requires_confirmation': true,
      'undoable': true,
    },
    {
      'target': AppControlTargets.worldBook,
      'operations': [AppControlOperations.create],
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
        AppControlOperations.enable,
        AppControlOperations.disable,
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
      ],
      'description':
          'Enable/disable built-in search globally or for the current assistant, or update selected search services from JSON.',
      'requires_confirmation': true,
      'undoable': true,
    },
  ];

  static final List<AppControlUndoEntry> _undoStack = <AppControlUndoEntry>[];

  final BuildContext contextProvider;
  final Uuid _uuid = const Uuid();

  static Map<String, dynamic> getToolDefinition() => const {
    'type': 'function',
    'function': {
      'name': AppControlToolNames.appControl,
      'description':
          'Plan, inspect, execute, or undo safe Kelivo app-control actions such as importing generated content into the current assistant prompt, memory, instruction injection, or world book. Execution requires the assistant App Control permission and user confirmation.',
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
            'enum': [
              AppControlTargets.currentAssistantSettings,
              AppControlTargets.currentAssistantSystemPrompt,
              AppControlTargets.currentAssistantMemory,
              AppControlTargets.currentAssistantSkills,
              AppControlTargets.currentAssistantLocalTools,
              AppControlTargets.currentAssistantMcp,
              AppControlTargets.quickPhrase,
              AppControlTargets.instructionInjection,
              AppControlTargets.worldBook,
              AppControlTargets.mcpServer,
              AppControlTargets.searchSettings,
            ],
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
              AppControlOperations.setApproval,
            ],
            'description': 'Mutation operation for the target.',
          },
          'content': {
            'type': 'string',
            'description':
                'Content to import, create, append, overwrite, or JSON config for settings/MCP/search updates.',
          },
          'title': {
            'type': 'string',
            'description': 'Short title for created items or confirmation UI.',
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
          'keywords': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'Trigger keywords for created skills.',
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
          'capabilities': capabilities,
          'permission_enabled': assistant?.appControlEnabled == true,
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
        return _jsonError(
          'invalid_action',
          'unknown app control action: $action',
        );
    }
  }

  String _planAction(Map<String, dynamic> args, Assistant? assistant) {
    final validation = _validateMutationArgs(args, assistant);
    if (validation != null) return validation;
    final target = args['target'].toString();
    final operation = args['operation'].toString();
    final content = args['content'].toString();
    return _json({
      'type': 'app_control_plan',
      'target': target,
      'operation': operation,
      'title': _title(args, target),
      'reason': _reason(args, target, operation),
      'content_preview': _preview(content),
      'content_length': content.length,
      'requires_confirmation': true,
      'permission_enabled': assistant?.appControlEnabled == true,
      'next_step': assistant?.appControlEnabled == true
          ? 'Call execute_action with the same target, operation, content, title, and activate fields after the user confirms.'
          : 'Ask the user to enable App Control permission in this assistant settings.',
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
        'Current assistant has not been granted App Control permission.',
      );
    }

    final target = args['target'].toString();
    final operation = args['operation'].toString();
    final content = args['content'].toString();

    return switch (target) {
      AppControlTargets.currentAssistantSettings =>
        await _executeAssistantSettings(assistant!, operation, content),
      AppControlTargets.currentAssistantSystemPrompt =>
        await _executeAssistantPrompt(assistant!, operation, content),
      AppControlTargets.currentAssistantMemory => await _executeMemory(
        assistant!,
        operation,
        content,
      ),
      AppControlTargets.currentAssistantSkills => await _executeSkills(
        assistant!,
        args,
        operation,
        content,
      ),
      AppControlTargets.currentAssistantLocalTools =>
        await _executeAssistantLocalTools(assistant!, args, operation),
      AppControlTargets.currentAssistantMcp => await _executeAssistantMcp(
        assistant!,
        args,
        operation,
      ),
      AppControlTargets.quickPhrase => await _executeQuickPhrase(
        assistant!,
        args,
        operation,
        content,
      ),
      AppControlTargets.instructionInjection =>
        await _executeInstructionInjection(
          assistant!,
          args,
          operation,
          content,
        ),
      AppControlTargets.worldBook => await _executeWorldBook(
        assistant!,
        args,
        operation,
        content,
      ),
      AppControlTargets.mcpServer => await _executeMcpServer(args, operation),
      AppControlTargets.searchSettings => await _executeSearchSettings(
        assistant!,
        args,
        operation,
      ),
      _ => _jsonError('unsupported_target', 'unsupported target: $target'),
    };
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
        return _json({
          'type': 'app_control_inspection',
          'target': target,
          'count': memories.length,
          'items': memories
              .take(20)
              .map((m) => {'id': m.id, 'content_preview': _preview(m.content)})
              .toList(growable: false),
        });
      case AppControlTargets.currentAssistantSkills:
        final provider = contextProvider.read<SkillProvider>();
        await provider.initialize();
        return _json({
          'type': 'app_control_inspection',
          'target': target,
          'active_ids': assistant.skillIds,
          'items': provider.skills
              .take(30)
              .map(
                (skill) => {
                  'id': skill.id,
                  'name': skill.name,
                  'enabled': skill.enabled,
                  'active': assistant.skillIds.contains(skill.id),
                  'description_preview': _preview(skill.description),
                },
              )
              .toList(growable: false),
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
                  'content_preview': _preview(phrase.content),
                },
              )
              .toList(growable: false),
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
                  'prompt_preview': _preview(item.prompt),
                },
              )
              .toList(growable: false),
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
                  'entries': book.entries.length,
                  'description_preview': _preview(book.description),
                },
              )
              .toList(growable: false),
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
      default:
        return _jsonError('unsupported_target', 'unsupported target: $target');
    }
  }

  Future<String> _executeAssistantPrompt(
    Assistant assistant,
    String operation,
    String content,
  ) async {
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
        ? content.trim()
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
    if (operation != AppControlOperations.update) {
      return _jsonError(
        'unsupported_operation',
        'assistant settings supports update only',
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
    if (patch.containsKey('system_prompt')) {
      next = next.copyWith(
        systemPrompt: patch['system_prompt']?.toString() ?? '',
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
    String operation,
    String content,
  ) async {
    if (operation != AppControlOperations.create) {
      return _jsonError('unsupported_operation', 'memory supports create only');
    }
    final mp = contextProvider.read<MemoryProvider>();
    final memory = await mp.add(
      assistantId: assistant.id,
      content: content.trim(),
    );
    _pushUndo(
      target: AppControlTargets.currentAssistantMemory,
      payload: {'id': memory.id},
    );
    return _json({
      'type': 'app_control_result',
      'success': true,
      'target': AppControlTargets.currentAssistantMemory,
      'operation': operation,
      'assistant_id': assistant.id,
      'memory_id': memory.id,
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
    } else {
      return _jsonError(
        'unsupported_operation',
        'skills supports create, bind, or unbind only',
      );
    }
    await ap.updateAssistant(assistant.copyWith(skillIds: nextIds));
    _pushUndo(
      target: AppControlTargets.currentAssistantSkills,
      payload: {
        'assistant_id': assistant.id,
        'skill_ids': before,
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
    if (operation != AppControlOperations.create) {
      return _jsonError(
        'unsupported_operation',
        'quick phrase supports create only',
      );
    }
    final provider = contextProvider.read<QuickPhraseProvider>();
    await provider.initialize();
    final scope = (args['scope'] ?? 'assistant').toString().trim();
    final isGlobal = scope == 'global';
    final phrase = QuickPhrase(
      id: _uuid.v4(),
      title: _title(args, AppControlTargets.quickPhrase),
      content: content.trim(),
      isGlobal: isGlobal,
      assistantId: isGlobal ? null : assistant.id,
    );
    await provider.add(phrase);
    _pushUndo(
      target: AppControlTargets.quickPhrase,
      payload: {'id': phrase.id},
    );
    return _json({
      'type': 'app_control_result',
      'success': true,
      'target': AppControlTargets.quickPhrase,
      'operation': operation,
      'id': phrase.id,
      'scope': isGlobal ? 'global' : 'assistant',
      'undo_available': true,
    });
  }

  Future<String> _executeInstructionInjection(
    Assistant assistant,
    Map<String, dynamic> args,
    String operation,
    String content,
  ) async {
    if (operation != AppControlOperations.create) {
      return _jsonError(
        'unsupported_operation',
        'instruction injection supports create only',
      );
    }
    final provider = contextProvider.read<InstructionInjectionProvider>();
    await provider.initialize();
    final item = InstructionInjection(
      id: _uuid.v4(),
      title: _title(args, AppControlTargets.instructionInjection),
      prompt: content.trim(),
      group: (args['group'] ?? '').toString().trim(),
    );
    await provider.add(item);
    final activate = args['activate'] == true;
    if (activate) {
      final activeIds = provider
          .activeIdsFor(assistant.id)
          .toList(growable: true);
      if (!activeIds.contains(item.id)) activeIds.add(item.id);
      await provider.setActiveIds(activeIds, assistantId: assistant.id);
    }
    _pushUndo(
      target: AppControlTargets.instructionInjection,
      payload: {'id': item.id},
    );
    return _json({
      'type': 'app_control_result',
      'success': true,
      'target': AppControlTargets.instructionInjection,
      'operation': operation,
      'id': item.id,
      'activated': activate,
      'undo_available': true,
    });
  }

  Future<String> _executeWorldBook(
    Assistant assistant,
    Map<String, dynamic> args,
    String operation,
    String content,
  ) async {
    if (operation != AppControlOperations.create) {
      return _jsonError(
        'unsupported_operation',
        'world book supports create only',
      );
    }
    final provider = contextProvider.read<WorldBookProvider>();
    await provider.initialize();
    final title = _title(args, AppControlTargets.worldBook);
    final entry = WorldBookEntry(
      id: _uuid.v4(),
      name: title,
      content: content.trim(),
      constantActive: true,
      keywords: const <String>[],
    );
    final book = WorldBook(
      id: _uuid.v4(),
      name: title,
      description: _reason(args, AppControlTargets.worldBook, operation),
      enabled: true,
      entries: <WorldBookEntry>[entry],
    );
    await provider.addBook(book);
    final activate = args['activate'] == true;
    if (activate) {
      final activeIds = provider
          .activeBookIdsFor(assistant.id)
          .toList(growable: true);
      if (!activeIds.contains(book.id)) activeIds.add(book.id);
      await provider.setActiveBookIds(activeIds, assistantId: assistant.id);
    }
    _pushUndo(target: AppControlTargets.worldBook, payload: {'id': book.id});
    return _json({
      'type': 'app_control_result',
      'success': true,
      'target': AppControlTargets.worldBook,
      'operation': operation,
      'id': book.id,
      'entry_id': entry.id,
      'activated': activate,
      'undo_available': true,
    });
  }

  Future<String> _executeMcpServer(
    Map<String, dynamic> args,
    String operation,
  ) async {
    final provider = contextProvider.read<McpProvider>();
    if (operation == AppControlOperations.create ||
        operation == AppControlOperations.update) {
      final content = (args['content'] ?? '').toString();
      if (content.trim().isEmpty) {
        return _jsonError('invalid_content', 'content must not be empty');
      }
      final before = provider.servers.map((server) => server.toJson()).toList();
      try {
        if (operation == AppControlOperations.update) {
          await provider.replaceAllFromJson(content);
        } else {
          final created = _mcpServersFromContent(content);
          if (created.isEmpty) {
            return _jsonError(
              'invalid_mcp_config',
              'No valid MCP server config found in content.',
            );
          }
          final existingIds = provider.servers.map((s) => s.id).toSet();
          for (final server in created) {
            final id = existingIds.contains(server.id) ? _uuid.v4() : server.id;
            await provider.addServer(
              enabled: server.enabled,
              name: server.name,
              transport: server.transport,
              url: server.url,
              headers: server.headers,
              command: server.command,
              args: server.args,
              env: server.env,
              workingDirectory: server.workingDirectory,
            );
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
    return _jsonError(
      'unsupported_operation',
      'mcp server supports create, update, enable, disable, or set_approval only',
    );
  }

  Future<String> _executeSearchSettings(
    Assistant assistant,
    Map<String, dynamic> args,
    String operation,
  ) async {
    if (operation == AppControlOperations.update) {
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
        'search settings supports update, enable, or disable only',
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

  Future<String> _undoLast(Assistant? assistant) async {
    if (assistant?.appControlEnabled != true) {
      return _jsonError(
        'permission_required',
        'Current assistant has not been granted App Control permission.',
      );
    }
    if (_undoStack.isEmpty) {
      return _jsonError(
        'nothing_to_undo',
        'No app control action can be undone.',
      );
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
        final id = _intFrom(entry.payload['id']);
        await contextProvider.read<MemoryProvider>().delete(id: id);
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
        final createdId = entry.payload['created_id']?.toString();
        if (createdId != null && createdId.isNotEmpty) {
          await sp.deleteSkill(createdId);
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
        final id = entry.payload['id']?.toString();
        if (id == null || id.isEmpty) {
          return _jsonError('undo_failed', 'Quick phrase id is missing.');
        }
        await contextProvider.read<QuickPhraseProvider>().delete(id);
        return _json({
          'type': 'app_control_undo',
          'success': true,
          'target': entry.target,
        });
      case AppControlTargets.instructionInjection:
        final id = entry.payload['id']?.toString();
        if (id == null || id.isEmpty) {
          return _jsonError(
            'undo_failed',
            'Instruction injection id is missing.',
          );
        }
        await contextProvider.read<InstructionInjectionProvider>().delete(id);
        return _json({
          'type': 'app_control_undo',
          'success': true,
          'target': entry.target,
        });
      case AppControlTargets.worldBook:
        final id = entry.payload['id']?.toString();
        if (id == null || id.isEmpty) {
          return _jsonError('undo_failed', 'World book id is missing.');
        }
        await contextProvider.read<WorldBookProvider>().deleteBook(id);
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
    if (target == AppControlTargets.currentAssistantLocalTools ||
        target == AppControlTargets.currentAssistantMcp ||
        target == AppControlTargets.mcpServer ||
        target == AppControlTargets.searchSettings) {
      return false;
    }
    if (target == AppControlTargets.currentAssistantSkills &&
        operation != AppControlOperations.create) {
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

  String _appendBlock(String before, String content) {
    final existing = before.trimRight();
    final incoming = content.trim();
    if (existing.isEmpty) return incoming;
    return '$existing\n\n$incoming';
  }

  String _title(Map<String, dynamic> args, String target) {
    final explicit = (args['title'] ?? '').toString().trim();
    if (explicit.isNotEmpty) return explicit;
    return switch (target) {
      AppControlTargets.currentAssistantSettings => 'Assistant Settings',
      AppControlTargets.currentAssistantSystemPrompt => 'App Control Import',
      AppControlTargets.currentAssistantMemory => 'Memory',
      AppControlTargets.currentAssistantSkills => 'AI Imported Skill',
      AppControlTargets.quickPhrase => 'AI Imported Quick Phrase',
      AppControlTargets.instructionInjection => 'AI Imported Instruction',
      AppControlTargets.worldBook => 'AI Imported World Book',
      _ => 'App Control Action',
    };
  }

  String _reason(Map<String, dynamic> args, String target, String operation) {
    final explicit = (args['reason'] ?? '').toString().trim();
    if (explicit.isNotEmpty) return explicit;
    return 'Apply $operation to $target from chat content.';
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

    void addFromUiMap(Map<dynamic, dynamic> map) {
      for (final entry in mapEntries(map)) {
        final raw = entry.value;
        if (raw is! Map) continue;
        final cfg = raw.cast<String, dynamic>();
        final id = entry.key.trim().isEmpty ? _uuid.v4() : entry.key.trim();
        final type = (cfg['type'] ?? cfg['transport'] ?? '')
            .toString()
            .toLowerCase();
        final enabled = cfg.containsKey('enabled')
            ? _boolFrom(cfg['enabled'])
            : (cfg.containsKey('isActive') ? _boolFrom(cfg['isActive']) : true);
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
          continue;
        }
        if (type == 'stdio' || cfg.containsKey('command')) {
          final command = (cfg['command'] ?? '').toString().trim();
          if (command.isEmpty) continue;
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
          continue;
        }
        final transport = type.contains('http')
            ? McpTransportType.http
            : McpTransportType.sse;
        final url = (cfg['url'] ?? cfg['baseUrl'] ?? '').toString().trim();
        if (url.isEmpty) continue;
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
