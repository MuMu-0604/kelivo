import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/chat/widgets/reasoning_budget_sheet.dart';
import 'package:Kelivo/features/chat/widgets/thinking_effort_slider.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

Future<SettingsProvider> _settingsForClaudeModel(
  WidgetTester tester,
  String modelId,
) async {
  SharedPreferences.setMockInitialValues({});
  final settings = SettingsProvider();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();

  await settings.setProviderConfig(
    'Claude',
    ProviderConfig(
      id: 'Claude',
      enabled: true,
      name: 'Claude',
      apiKey: 'test-key',
      baseUrl: 'https://api.anthropic.com/v1',
      providerType: ProviderKind.claude,
      models: <String>[modelId],
    ),
  );
  await settings.setCurrentModel('Claude', modelId);
  return settings;
}

Future<void> _pumpSheetLauncher(
  WidgetTester tester, {
  required SettingsProvider settings,
  String? modelProvider,
  String? modelId,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<AssistantProvider>(
          create: (_) => AssistantProvider(),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                key: const ValueKey('open-reasoning-sheet'),
                onPressed: () => showReasoningBudgetSheet(
                  context,
                  modelProvider: modelProvider,
                  modelId: modelId,
                ),
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    ),
  );
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open-reasoning-sheet')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReasoningBudgetSheet', () {
    testWidgets('shows slider max reasoning for Claude Fable 5', (
      tester,
    ) async {
      const modelId = 'claude-fable-5';
      final settings = await _settingsForClaudeModel(tester, modelId);
      await _pumpSheetLauncher(
        tester,
        settings: settings,
        modelProvider: 'Claude',
        modelId: modelId,
      );

      await _openSheet(tester);

      expect(find.text('Faster'), findsOneWidget);
      expect(find.text('Smarter'), findsOneWidget);

      final track = find.byKey(ThinkingEffortSlider.sliderKey);
      final rect = tester.getRect(track);
      await tester.tapAt(rect.centerRight - const Offset(2, 0));
      await tester.pump(const Duration(milliseconds: 120));

      expect(settings.thinkingBudget, 128000);
      expect(find.text('Ultracode'), findsOneWidget);
    });

    testWidgets('keeps max reasoning hidden for older Claude models', (
      tester,
    ) async {
      final settings = await _settingsForClaudeModel(
        tester,
        'claude-sonnet-4-5',
      );
      await _pumpSheetLauncher(
        tester,
        settings: settings,
        modelProvider: 'Claude',
        modelId: 'claude-sonnet-4-5',
      );

      await _openSheet(tester);

      final track = find.byKey(ThinkingEffortSlider.sliderKey);
      final rect = tester.getRect(track);
      await tester.tapAt(rect.centerRight - const Offset(2, 0));
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.text('Ultracode'), findsNothing);
      expect(settings.thinkingBudget, 32000);
    });
  });
}
