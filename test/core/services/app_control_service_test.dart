import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/models/app_control_policy.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/instruction_injection_provider.dart';
import 'package:Kelivo/core/providers/memory_provider.dart';
import 'package:Kelivo/core/providers/mcp_provider.dart';
import 'package:Kelivo/core/providers/quick_phrase_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/skill_provider.dart';
import 'package:Kelivo/core/providers/world_book_provider.dart';
import 'package:Kelivo/core/services/app_control/app_control_service.dart';
import 'package:Kelivo/core/services/search/search_service.dart';
import 'package:Kelivo/features/home/services/local_tools_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('神经权能网关 appends and undoes assistant prompt', (tester) async {
    const assistant = Assistant(
      id: 'assistant-a',
      name: 'Assistant',
      systemPrompt: 'Base prompt',
      appControlEnabled: true,
    );

    await _pumpScope(tester, assistant);
    final context = tester.element(find.byType(SizedBox));
    final service = AppControlService(contextProvider: context);
    final ap = context.read<AssistantProvider>();

    final result =
        jsonDecode(
              await service.handleToolCall({
                'action': AppControlActionNames.executeAction,
                'target': AppControlTargets.currentAssistantSystemPrompt,
                'operation': AppControlOperations.append,
                'content': 'Imported prompt',
              }, assistant),
            )
            as Map<String, dynamic>;

    expect(result['success'], isTrue);
    expect(
      ap.getById(assistant.id)!.systemPrompt,
      'Base prompt\n\nImported prompt',
    );

    final undo =
        jsonDecode(
              await service.handleToolCall({
                'action': AppControlActionNames.undoLast,
              }, ap.getById(assistant.id)),
            )
            as Map<String, dynamic>;

    expect(undo['success'], isTrue);
    expect(ap.getById(assistant.id)!.systemPrompt, 'Base prompt');
  });

  testWidgets('app control clears assistant prompt with empty overwrite', (
    tester,
  ) async {
    const assistant = Assistant(
      id: 'assistant-a',
      name: 'Assistant',
      systemPrompt: 'Temporary prompt',
      appControlEnabled: true,
    );

    await _pumpScope(tester, assistant);
    final context = tester.element(find.byType(SizedBox));
    final service = AppControlService(contextProvider: context);
    final ap = context.read<AssistantProvider>();

    final result =
        jsonDecode(
              await service.handleToolCall({
                'action': AppControlActionNames.executeAction,
                'target': AppControlTargets.currentAssistantSystemPrompt,
                'operation': AppControlOperations.overwrite,
                'content': '',
              }, assistant),
            )
            as Map<String, dynamic>;

    expect(result['success'], isTrue);
    expect(result['content_length'], 0);
    expect(ap.getById(assistant.id)!.systemPrompt, isEmpty);
  });

  testWidgets('app control clears prompt via camelCase import and settings', (
    tester,
  ) async {
    const assistant = Assistant(
      id: 'assistant-a',
      name: 'Assistant',
      systemPrompt: 'Temporary prompt',
      appControlEnabled: true,
    );

    await _pumpScope(tester, assistant);
    final context = tester.element(find.byType(SizedBox));
    final service = AppControlService(contextProvider: context);
    final ap = context.read<AssistantProvider>();

    final imported =
        jsonDecode(
              await service.handleToolCall({
                'action': AppControlActionNames.executeAction,
                'target': AppControlTargets.currentAssistantSystemPrompt,
                'operation': AppControlOperations.importJson,
                'content': jsonEncode({'systemPrompt': ''}),
              }, assistant),
            )
            as Map<String, dynamic>;

    expect(imported['success'], isTrue);
    expect(ap.getById(assistant.id)!.systemPrompt, isEmpty);

    await ap.updateAssistant(
      assistant.copyWith(systemPrompt: 'Temporary prompt'),
    );

    final updated =
        jsonDecode(
              await service.handleToolCall({
                'action': AppControlActionNames.executeAction,
                'target': AppControlTargets.currentAssistantSettings,
                'operation': AppControlOperations.update,
                'content': jsonEncode({'systemPrompt': ''}),
              }, ap.getById(assistant.id)),
            )
            as Map<String, dynamic>;

    expect(updated['success'], isTrue);
    expect(ap.getById(assistant.id)!.systemPrompt, isEmpty);
  });

  testWidgets('神经权能网关 creates active instruction injection', (tester) async {
    const assistant = Assistant(
      id: 'assistant-a',
      name: 'Assistant',
      appControlEnabled: true,
    );

    await _pumpScope(tester, assistant);
    final context = tester.element(find.byType(SizedBox));
    final service = AppControlService(contextProvider: context);
    final provider = context.read<InstructionInjectionProvider>();

    final result =
        jsonDecode(
              await service.handleToolCall({
                'action': AppControlActionNames.executeAction,
                'target': AppControlTargets.instructionInjection,
                'operation': AppControlOperations.create,
                'title': 'Style Guide',
                'content': 'Always answer concisely.',
                'activate': true,
              }, assistant),
            )
            as Map<String, dynamic>;

    expect(result['success'], isTrue);
    final created = provider.items.firstWhere(
      (item) => item.title == 'Style Guide',
    );
    expect(created.prompt, 'Always answer concisely.');
    expect(provider.activeIdsFor(assistant.id), contains(created.id));
  });

  testWidgets('神经权能网关 refuses execution without permission', (tester) async {
    const assistant = Assistant(id: 'assistant-a', name: 'Assistant');

    await _pumpScope(tester, assistant);
    final context = tester.element(find.byType(SizedBox));
    final service = AppControlService(contextProvider: context);

    final result =
        jsonDecode(
              await service.handleToolCall({
                'action': AppControlActionNames.executeAction,
                'target': AppControlTargets.currentAssistantSystemPrompt,
                'operation': AppControlOperations.overwrite,
                'content': 'New prompt',
              }, assistant),
            )
            as Map<String, dynamic>;

    expect(result['type'], 'app_control_error');
    expect(result['error'], 'permission_required');
  });

  testWidgets('神经权能网关 refuses disabled target by assistant policy', (
    tester,
  ) async {
    final assistant = Assistant(
      id: 'assistant-a',
      name: 'Assistant',
      appControlEnabled: true,
      appControlPolicy: AppControlPolicy.safeDefault(
        enabled: true,
      ).setTargetEnabled(AppControlPolicy.currentAssistantSystemPrompt, false),
    );

    await _pumpScope(tester, assistant);
    final context = tester.element(find.byType(SizedBox));
    final service = AppControlService(contextProvider: context);

    final result =
        jsonDecode(
              await service.handleToolCall({
                'action': AppControlActionNames.executeAction,
                'target': AppControlTargets.currentAssistantSystemPrompt,
                'operation': AppControlOperations.append,
                'content': 'Blocked prompt',
              }, assistant),
            )
            as Map<String, dynamic>;

    expect(result['type'], 'app_control_error');
    expect(result['error'], 'permission_denied');
  });

  testWidgets('神经权能网关 exposes only enabled policy targets', (tester) async {
    final assistant = Assistant(
      id: 'assistant-a',
      name: 'Assistant',
      appControlEnabled: true,
      appControlPolicy: AppControlPolicy.safeDefault(
        enabled: true,
      ).setTargetEnabled(AppControlPolicy.currentAssistantSystemPrompt, false),
    );

    final tool = AppControlService.getToolDefinition(assistant);
    final targets =
        ((tool['function'] as Map)['parameters'] as Map)['properties'] as Map;
    final targetEnum = (targets['target'] as Map)['enum'] as List;

    expect(
      targetEnum,
      isNot(contains(AppControlTargets.currentAssistantSystemPrompt)),
    );
    expect(targetEnum, contains(AppControlTargets.auditLog));
  });

  testWidgets('神经权能网关 updates assistant settings from JSON and undoes', (
    tester,
  ) async {
    const assistant = Assistant(
      id: 'assistant-a',
      name: 'Assistant',
      appControlEnabled: true,
      searchEnabled: false,
    );

    await _pumpScope(tester, assistant);
    final context = tester.element(find.byType(SizedBox));
    final service = AppControlService(contextProvider: context);
    final ap = context.read<AssistantProvider>();

    final result =
        jsonDecode(
              await service.handleToolCall({
                'action': AppControlActionNames.executeAction,
                'target': AppControlTargets.currentAssistantSettings,
                'operation': AppControlOperations.update,
                'content': jsonEncode({
                  'name': 'Configured Assistant',
                  'search_enabled': true,
                  'memory_enabled': true,
                  'temperature': 0.7,
                  'context_message_size': 12,
                }),
              }, assistant),
            )
            as Map<String, dynamic>;

    expect(result['success'], isTrue);
    final updated = ap.getById(assistant.id)!;
    expect(updated.name, 'Configured Assistant');
    expect(updated.searchEnabled, isTrue);
    expect(updated.enableMemory, isTrue);
    expect(updated.temperature, 0.7);
    expect(updated.contextMessageSize, 12);

    await service.handleToolCall({
      'action': AppControlActionNames.undoLast,
    }, updated);

    final restored = ap.getById(assistant.id)!;
    expect(restored.name, 'Assistant');
    expect(restored.searchEnabled, isFalse);
    expect(restored.enableMemory, isFalse);
  });

  testWidgets('神经权能网关 creates active skill and can undo it', (tester) async {
    const assistant = Assistant(
      id: 'assistant-a',
      name: 'Assistant',
      appControlEnabled: true,
    );

    await _pumpScope(tester, assistant);
    final context = tester.element(find.byType(SizedBox));
    final service = AppControlService(contextProvider: context);
    final ap = context.read<AssistantProvider>();
    final sp = context.read<SkillProvider>();

    final result =
        jsonDecode(
              await service.handleToolCall({
                'action': AppControlActionNames.executeAction,
                'target': AppControlTargets.currentAssistantSkills,
                'operation': AppControlOperations.create,
                'title': 'Repo Reviewer',
                'content': 'Review repositories carefully.',
                'keywords': ['review', 'repo'],
                'priority': 7,
                'activate': true,
              }, assistant),
            )
            as Map<String, dynamic>;

    expect(result['success'], isTrue);
    final skillId = result['skill_id'] as String;
    expect(sp.getById(skillId)!.name, 'Repo Reviewer');
    expect(sp.getById(skillId)!.priority, 7);
    expect(ap.getById(assistant.id)!.skillIds, contains(skillId));

    await service.handleToolCall({
      'action': AppControlActionNames.undoLast,
    }, ap.getById(assistant.id));

    expect(sp.getById(skillId), isNull);
    expect(ap.getById(assistant.id)!.skillIds, isNot(contains(skillId)));
  });

  testWidgets('app control inspect reports missing active skill ids', (
    tester,
  ) async {
    const assistant = Assistant(
      id: 'assistant-a',
      name: 'Assistant',
      appControlEnabled: true,
      skillIds: ['missing-skill-id'],
    );

    await _pumpScope(tester, assistant);
    final context = tester.element(find.byType(SizedBox));
    final service = AppControlService(contextProvider: context);

    final result =
        jsonDecode(
              await service.handleToolCall({
                'action': AppControlActionNames.inspectTarget,
                'target': AppControlTargets.currentAssistantSkills,
              }, assistant),
            )
            as Map<String, dynamic>;
    final items = (result['items'] as List).cast<Map>();
    final missing = items.singleWhere(
      (item) => item['id'] == 'missing-skill-id',
    );

    expect(missing['missing'], isTrue);
    expect(missing['active'], isTrue);
    expect(missing['reason'], 'skill_not_found_or_not_accessible');
  });

  testWidgets('神经权能网关 binds local tools without content', (tester) async {
    const assistant = Assistant(
      id: 'assistant-a',
      name: 'Assistant',
      appControlEnabled: true,
    );

    await _pumpScope(tester, assistant);
    final context = tester.element(find.byType(SizedBox));
    final service = AppControlService(contextProvider: context);
    final ap = context.read<AssistantProvider>();

    final result =
        jsonDecode(
              await service.handleToolCall({
                'action': AppControlActionNames.executeAction,
                'target': AppControlTargets.currentAssistantLocalTools,
                'operation': AppControlOperations.bind,
                'ids': [LocalToolNames.timeInfo, LocalToolNames.calculate],
              }, assistant),
            )
            as Map<String, dynamic>;

    expect(result['success'], isTrue);
    expect(
      ap.getById(assistant.id)!.localToolIds,
      contains(LocalToolNames.timeInfo),
    );
    expect(
      ap.getById(assistant.id)!.localToolIds,
      contains(LocalToolNames.calculate),
    );
  });

  testWidgets('神经权能网关 creates assistant quick phrase', (tester) async {
    const assistant = Assistant(
      id: 'assistant-a',
      name: 'Assistant',
      appControlEnabled: true,
    );

    await _pumpScope(tester, assistant);
    final context = tester.element(find.byType(SizedBox));
    final service = AppControlService(contextProvider: context);
    final qp = context.read<QuickPhraseProvider>();

    final result =
        jsonDecode(
              await service.handleToolCall({
                'action': AppControlActionNames.executeAction,
                'target': AppControlTargets.quickPhrase,
                'operation': AppControlOperations.create,
                'title': 'Ship checklist',
                'content': 'Run tests, build APK, verify signature.',
              }, assistant),
            )
            as Map<String, dynamic>;

    expect(result['success'], isTrue);
    final phrase = qp.phrases.singleWhere((p) => p.title == 'Ship checklist');
    expect(phrase.isGlobal, isFalse);
    expect(phrase.assistantId, assistant.id);
  });

  testWidgets('神经权能网关 creates memory and can undo it', (tester) async {
    const assistant = Assistant(
      id: 'assistant-a',
      name: 'Assistant',
      appControlEnabled: true,
    );

    await _pumpScope(tester, assistant);
    final context = tester.element(find.byType(SizedBox));
    final service = AppControlService(contextProvider: context);
    final mp = context.read<MemoryProvider>();

    final result =
        jsonDecode(
              await service.handleToolCall({
                'action': AppControlActionNames.executeAction,
                'target': AppControlTargets.currentAssistantMemory,
                'operation': AppControlOperations.create,
                'content': 'Prefers compact 神经权能网关 plans.',
              }, assistant),
            )
            as Map<String, dynamic>;

    expect(result['success'], isTrue);
    expect(mp.getForAssistant(assistant.id), hasLength(1));

    final undo =
        jsonDecode(
              await service.handleToolCall({
                'action': AppControlActionNames.undoLast,
              }, assistant),
            )
            as Map<String, dynamic>;

    expect(undo['success'], isTrue);
    expect(mp.getForAssistant(assistant.id), isEmpty);
  });

  testWidgets('神经权能网关 updates and deletes memory with undo', (tester) async {
    const assistant = Assistant(
      id: 'assistant-a',
      name: 'Assistant',
      appControlEnabled: true,
    );

    await _pumpScope(tester, assistant);
    final context = tester.element(find.byType(SizedBox));
    final service = AppControlService(contextProvider: context);
    final mp = context.read<MemoryProvider>();
    final memory = await mp.add(assistantId: assistant.id, content: 'Old');

    final update =
        jsonDecode(
              await service.handleToolCall({
                'action': AppControlActionNames.executeAction,
                'target': AppControlTargets.currentAssistantMemory,
                'operation': AppControlOperations.update,
                'id': memory.id,
                'content': 'New',
              }, assistant),
            )
            as Map<String, dynamic>;

    expect(update['success'], isTrue);
    expect(mp.getForAssistant(assistant.id).single.content, 'New');

    final delete =
        jsonDecode(
              await service.handleToolCall({
                'action': AppControlActionNames.executeAction,
                'target': AppControlTargets.currentAssistantMemory,
                'operation': AppControlOperations.delete,
                'id': memory.id,
              }, assistant),
            )
            as Map<String, dynamic>;

    expect(delete['success'], isTrue);
    expect(mp.getForAssistant(assistant.id), isEmpty);

    await service.handleToolCall({
      'action': AppControlActionNames.undoLast,
    }, assistant);

    expect(mp.getForAssistant(assistant.id).single.content, 'New');
  });

  testWidgets('神经权能网关 updates skill and rolls back a version', (tester) async {
    const assistant = Assistant(
      id: 'assistant-a',
      name: 'Assistant',
      appControlEnabled: true,
    );

    await _pumpScope(tester, assistant);
    final context = tester.element(find.byType(SizedBox));
    final service = AppControlService(contextProvider: context);
    final sp = context.read<SkillProvider>();
    final skillId = await sp.addSkill(name: 'Skill', content: 'v1');

    final version =
        jsonDecode(
              await service.handleToolCall({
                'action': AppControlActionNames.executeAction,
                'target': AppControlTargets.currentAssistantSkills,
                'operation': AppControlOperations.createVersion,
                'id': skillId,
              }, assistant),
            )
            as Map<String, dynamic>;
    final versionId = version['skill_id'] as String;

    await service.handleToolCall({
      'action': AppControlActionNames.executeAction,
      'target': AppControlTargets.currentAssistantSkills,
      'operation': AppControlOperations.update,
      'id': skillId,
      'content': jsonEncode({'content': 'v2', 'name': 'Skill v2'}),
    }, assistant);

    expect(sp.getById(skillId)!.content, 'v2');

    final rollback =
        jsonDecode(
              await service.handleToolCall({
                'action': AppControlActionNames.executeAction,
                'target': AppControlTargets.currentAssistantSkills,
                'operation': AppControlOperations.rollbackVersion,
                'id': skillId,
                'version_id': versionId,
              }, assistant),
            )
            as Map<String, dynamic>;

    expect(rollback['success'], isTrue);
    expect(sp.getById(skillId)!.content, 'v1');
  });

  testWidgets('神经权能网关 edits world book entries and exports bundle', (
    tester,
  ) async {
    const assistant = Assistant(
      id: 'assistant-a',
      name: 'Assistant',
      appControlEnabled: true,
    );

    await _pumpScope(tester, assistant);
    final context = tester.element(find.byType(SizedBox));
    final service = AppControlService(contextProvider: context);
    final wp = context.read<WorldBookProvider>();

    final created =
        jsonDecode(
              await service.handleToolCall({
                'action': AppControlActionNames.executeAction,
                'target': AppControlTargets.worldBook,
                'operation': AppControlOperations.create,
                'title': 'Lore',
                'content': 'Base entry',
                'keywords': ['base'],
                'activate': true,
              }, assistant),
            )
            as Map<String, dynamic>;
    final bookId = created['id'] as String;

    final added =
        jsonDecode(
              await service.handleToolCall({
                'action': AppControlActionNames.executeAction,
                'target': AppControlTargets.worldBook,
                'operation': AppControlOperations.addEntry,
                'book_id': bookId,
                'title': 'Second',
                'content': jsonEncode({
                  'content': 'Second entry',
                  'keywords': ['second'],
                }),
              }, assistant),
            )
            as Map<String, dynamic>;
    final entryId = added['entry_id'] as String;

    await service.handleToolCall({
      'action': AppControlActionNames.executeAction,
      'target': AppControlTargets.worldBook,
      'operation': AppControlOperations.updateEntry,
      'book_id': bookId,
      'entry_id': entryId,
      'content': jsonEncode({'content': 'Updated entry'}),
    }, assistant);

    expect(wp.getById(bookId)!.entries, hasLength(2));
    expect(
      wp.getById(bookId)!.entries.firstWhere((e) => e.id == entryId).content,
      'Updated entry',
    );

    final exported =
        jsonDecode(
              await service.handleToolCall({
                'action': AppControlActionNames.executeAction,
                'target': AppControlTargets.appBundle,
                'operation': AppControlOperations.exportJson,
              }, assistant),
            )
            as Map<String, dynamic>;

    expect(exported['type'], 'app_control_export');
    expect((exported['payload'] as Map)['world_books'], isA<Map>());
  });

  testWidgets('神经权能网关 records audit log', (tester) async {
    const assistant = Assistant(
      id: 'assistant-a',
      name: 'Assistant',
      appControlEnabled: true,
    );

    await _pumpScope(tester, assistant);
    final context = tester.element(find.byType(SizedBox));
    final service = AppControlService(contextProvider: context);

    await service.handleToolCall({
      'action': AppControlActionNames.executeAction,
      'target': AppControlTargets.currentAssistantSystemPrompt,
      'operation': AppControlOperations.append,
      'content': 'Audit me',
    }, assistant);

    final audit =
        jsonDecode(
              await service.handleToolCall({
                'action': AppControlActionNames.inspectTarget,
                'target': AppControlTargets.auditLog,
              }, assistant),
            )
            as Map<String, dynamic>;

    expect(audit['type'], 'app_control_audit_log');
    expect(audit['items'], isNotEmpty);
  });

  testWidgets('神经权能网关 updates search settings from JSON and undoes', (
    tester,
  ) async {
    const assistant = Assistant(
      id: 'assistant-a',
      name: 'Assistant',
      appControlEnabled: true,
      searchEnabled: false,
    );

    await _pumpScope(tester, assistant);
    final context = tester.element(find.byType(SizedBox));
    final service = AppControlService(contextProvider: context);
    final settings = context.read<SettingsProvider>();
    final ap = context.read<AssistantProvider>();

    final result =
        jsonDecode(
              await service.handleToolCall({
                'action': AppControlActionNames.executeAction,
                'target': AppControlTargets.searchSettings,
                'operation': AppControlOperations.update,
                'content': jsonEncode({
                  'global_enabled': true,
                  'assistant_enabled': true,
                  'selected_index': 0,
                  'common': {'resultSize': 6, 'timeout': 3000},
                  'services': [
                    {'type': 'hybrid_local', 'id': 'hybrid-test'},
                    {'type': 'duckduckgo', 'id': 'ddg-test', 'region': 'cn-zh'},
                  ],
                }),
              }, assistant),
            )
            as Map<String, dynamic>;

    expect(result['success'], isTrue);
    expect(settings.searchEnabled, isTrue);
    expect(ap.getById(assistant.id)!.searchEnabled, isTrue);
    expect(settings.searchServices, hasLength(2));
    expect(settings.searchServices.first, isA<HybridLocalSearchOptions>());
    expect(settings.searchCommonOptions.resultSize, 6);

    await service.handleToolCall({
      'action': AppControlActionNames.undoLast,
    }, ap.getById(assistant.id));

    expect(settings.searchEnabled, isFalse);
    expect(ap.getById(assistant.id)!.searchEnabled, isFalse);
  });

  testWidgets('app control creates disabled MCP server from flat JSON', (
    tester,
  ) async {
    const assistant = Assistant(
      id: 'assistant-a',
      name: 'Assistant',
      appControlEnabled: true,
    );

    await _pumpScope(tester, assistant);
    final context = tester.element(find.byType(SizedBox));
    final service = AppControlService(contextProvider: context);
    final provider = context.read<McpProvider>();

    final result =
        jsonDecode(
              await service.handleToolCall({
                'action': AppControlActionNames.executeAction,
                'target': AppControlTargets.mcpServer,
                'operation': AppControlOperations.create,
                'content': jsonEncode({
                  'id': 'gateway-test-dummy-mcp',
                  'name': 'Gateway Test Dummy MCP',
                  'enabled': false,
                  'transport': 'stdio',
                  'command': 'echo',
                  'args': ['gateway-test'],
                  'env': {},
                }),
              }, assistant),
            )
            as Map<String, dynamic>;

    expect(result['success'], isTrue);
    final server = provider.getById('gateway-test-dummy-mcp')!;
    expect(server.enabled, isFalse);
    expect(provider.statusFor(server.id), McpStatus.idle);
  });

  testWidgets(
    'app control respects disabled true in MCP create update import',
    (tester) async {
      const assistant = Assistant(
        id: 'assistant-a',
        name: 'Assistant',
        appControlEnabled: true,
      );

      await _pumpScope(tester, assistant);
      final context = tester.element(find.byType(SizedBox));
      final service = AppControlService(contextProvider: context);
      final provider = context.read<McpProvider>();

      final create =
          jsonDecode(
                await service.handleToolCall({
                  'action': AppControlActionNames.executeAction,
                  'target': AppControlTargets.mcpServer,
                  'operation': AppControlOperations.create,
                  'content': jsonEncode({
                    'mcpServers': {
                      'gateway-test-dummy-mcp': {
                        'command': 'echo',
                        'args': ['gateway-test'],
                        'env': {},
                        'disabled': true,
                      },
                    },
                  }),
                }, assistant),
              )
              as Map<String, dynamic>;

      expect(create['success'], isTrue);
      expect(provider.getById('gateway-test-dummy-mcp')!.enabled, isFalse);
    expect(provider.statusFor('gateway-test-dummy-mcp'), McpStatus.idle);

      final update =
          jsonDecode(
                await service.handleToolCall({
                  'action': AppControlActionNames.executeAction,
                  'target': AppControlTargets.mcpServer,
                  'operation': AppControlOperations.update,
                  'server_id': 'gateway-test-dummy-mcp',
                  'content': jsonEncode({
                    'mcpServers': {
                      'gateway-test-dummy-mcp': {
                        'command': 'echo',
                        'args': ['gateway-test-updated'],
                        'env': {},
                        'disabled': true,
                      },
                    },
                  }),
                }, assistant),
              )
              as Map<String, dynamic>;

      expect(update['success'], isTrue);
      final updated = provider.getById('gateway-test-dummy-mcp')!;
      expect(updated.enabled, isFalse);
      expect(updated.args, ['gateway-test-updated']);

      final importResult =
          jsonDecode(
                await service.handleToolCall({
                  'action': AppControlActionNames.executeAction,
                  'target': AppControlTargets.mcpServer,
                  'operation': AppControlOperations.importJson,
                  'content': jsonEncode({
                    'mcpServers': {
                      'gateway-test-import-mcp': {
                        'command': 'echo',
                        'args': ['gateway-test-imported'],
                        'env': {},
                        'disabled': true,
                      },
                    },
                  }),
                }, assistant),
              )
              as Map<String, dynamic>;

      expect(importResult['success'], isTrue);
      final imported = provider.getById('gateway-test-import-mcp')!;
      expect(imported.enabled, isFalse);
      expect(imported.args, ['gateway-test-imported']);
    },
  );
}

Future<void> _pumpScope(WidgetTester tester, Assistant assistant) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AssistantProvider>(
          create: (_) => _SeededAssistantProvider(assistant),
        ),
        ChangeNotifierProvider<InstructionInjectionProvider>(
          create: (_) => InstructionInjectionProvider(),
        ),
        ChangeNotifierProvider<WorldBookProvider>(
          create: (_) => WorldBookProvider(),
        ),
        ChangeNotifierProvider<MemoryProvider>(create: (_) => MemoryProvider()),
        ChangeNotifierProvider<McpProvider>(create: (_) => McpProvider()),
        ChangeNotifierProvider<SkillProvider>(create: (_) => SkillProvider()),
        ChangeNotifierProvider<QuickPhraseProvider>(
          create: (_) => QuickPhraseProvider(),
        ),
        ChangeNotifierProvider<SettingsProvider>(
          create: (_) => SettingsProvider(),
        ),
      ],
      child: const SizedBox.shrink(),
    ),
  );
}

class _SeededAssistantProvider extends AssistantProvider {
  _SeededAssistantProvider(this.seed);

  final Assistant seed;
  late Assistant _current = seed;

  @override
  Assistant? get currentAssistant => _current;

  @override
  Assistant? getById(String id) => _current.id == id ? _current : null;

  @override
  Future<void> updateAssistant(Assistant updated) async {
    _current = updated;
    notifyListeners();
  }
}
