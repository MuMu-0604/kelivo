import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/dialogs/reasoning_budget_custom_dialog.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../core/services/haptics.dart';
import 'thinking_effort_slider.dart';

Future<void> showReasoningBudgetSheet(
  BuildContext context, {
  String? modelProvider,
  String? modelId,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) =>
        _ReasoningBudgetSheet(modelProvider: modelProvider, modelId: modelId),
  );
}

class _ReasoningBudgetSheet extends StatefulWidget {
  const _ReasoningBudgetSheet({this.modelProvider, this.modelId});
  final String? modelProvider;
  final String? modelId;
  @override
  State<_ReasoningBudgetSheet> createState() => _ReasoningBudgetSheetState();
}

class _ReasoningBudgetSheetState extends State<_ReasoningBudgetSheet> {
  late int _selected;

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsProvider>();
    _selected = s.thinkingBudget ?? -1;
  }

  Future<void> _select(int value) async {
    setState(() {
      _selected = value;
    });
    await context.read<SettingsProvider>().setThinkingBudget(value);
  }

  bool _isCustomSelected({required bool showXhigh, required bool showMax}) {
    final presets = <int>{
      -1, // auto
      0, // off
      1024,
      16000,
      32000,
      if (showXhigh) 64000,
      if (showMax) 128000,
    };
    return !presets.contains(_selected);
  }

  Future<void> _openCustomBudget() async {
    Haptics.light();
    final settings = context.read<SettingsProvider>();
    final isCurrentCustom = _isCustomSelected(
      showXhigh: _showXhighOption(settings),
      showMax: _showMaxOption(settings),
    );
    final initialValue = isCurrentCustom ? _selected : 2048;
    final chosen = await ReasoningBudgetCustomDialog.show(
      context,
      initialValue: initialValue,
    );
    if (!mounted || chosen == null) return;
    await _select(chosen);
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  List<ThinkingEffortLevel> _levels(
    AppLocalizations l10n, {
    required bool showXhigh,
    required bool showMax,
  }) {
    final levels = <ThinkingEffortLevel>[
      ThinkingEffortLevel(
        label: l10n.reasoningBudgetSheetLight,
        budget: 1024,
        description: l10n.reasoningBudgetSheetLightSubtitle,
      ),
      ThinkingEffortLevel(
        label: l10n.reasoningBudgetSheetMedium,
        budget: 16000,
        description: l10n.reasoningBudgetSheetMediumSubtitle,
      ),
      ThinkingEffortLevel(
        label: l10n.reasoningBudgetSheetHeavy,
        budget: 32000,
        description: l10n.reasoningBudgetSheetHeavySubtitle,
      ),
      if (showXhigh)
        ThinkingEffortLevel(
          label: l10n.reasoningBudgetSheetXhigh,
          budget: 64000,
          description: l10n.reasoningBudgetSheetXhighSubtitle,
        ),
      if (showMax)
        ThinkingEffortLevel(
          label: l10n.reasoningBudgetSheetMax,
          budget: 128000,
          description: l10n.reasoningBudgetSheetMaxSubtitle,
        ),
    ];
    if (showXhigh || showMax) {
      levels.add(
        ThinkingEffortLevel(
          label: l10n.reasoningBudgetSheetUltracode,
          budget: showMax ? 128000 : 64000,
          description: l10n.reasoningBudgetSheetUltracodeSubtitle,
          particleMode: true,
        ),
      );
    }
    return levels;
  }

  Widget _compactAction({
    required String label,
    required bool active,
    required VoidCallback onTap,
    String? value,
    IconData? icon,
  }) {
    final cs = Theme.of(context).colorScheme;
    final color = active ? cs.primary : cs.onSurface.withValues(alpha: 0.78);
    return Expanded(
      child: IosCardPress(
        borderRadius: BorderRadius.circular(14),
        baseColor: active
            ? cs.primaryContainer.withValues(alpha: 0.38)
            : cs.surfaceContainerHighest.withValues(alpha: 0.42),
        duration: const Duration(milliseconds: 220),
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                value == null ? label : '$label $value',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _showXhighOption(SettingsProvider settings) {
    final assistant = context.read<AssistantProvider>().currentAssistant;
    final currentProvider =
        widget.modelProvider ??
        assistant?.chatModelProvider ??
        settings.currentModelProvider;
    final currentModelId =
        widget.modelId ?? assistant?.chatModelId ?? settings.currentModelId;
    if (currentProvider == null || currentModelId == null) return false;
    return settings.supportsXhighReasoning(currentProvider, currentModelId);
  }

  bool _showMaxOption(SettingsProvider settings) {
    final assistant = context.read<AssistantProvider>().currentAssistant;
    final currentProvider =
        widget.modelProvider ??
        assistant?.chatModelProvider ??
        settings.currentModelProvider;
    final currentModelId =
        widget.modelId ?? assistant?.chatModelId ?? settings.currentModelId;
    if (currentProvider == null || currentModelId == null) return false;
    return settings.supportsMaxReasoning(currentProvider, currentModelId);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();
    final showXhigh = _showXhighOption(settings);
    final showMax = _showMaxOption(settings);
    final customActive = _isCustomSelected(
      showXhigh: showXhigh,
      showMax: showMax,
    );
    final cs = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.8;
    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ThinkingEffortSlider(
                        levels: _levels(
                          l10n,
                          showXhigh: showXhigh,
                          showMax: showMax,
                        ),
                        selectedBudget: _selected,
                        title: l10n.reasoningBudgetSheetTitle,
                        fastLabel: l10n.reasoningBudgetSheetFastLabel,
                        smartLabel: l10n.reasoningBudgetSheetSmartLabel,
                        helpLabel: l10n.reasoningBudgetSheetHelpTooltip,
                        onChanged: (level) async {
                          Haptics.light();
                          await _select(level.budget);
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _compactAction(
                            label: l10n.reasoningBudgetSheetOff,
                            active: _selected == 0,
                            onTap: () async {
                              Haptics.light();
                              final navigator = Navigator.of(context);
                              await _select(0);
                              if (!mounted) return;
                              navigator.maybePop();
                            },
                          ),
                          const SizedBox(width: 8),
                          _compactAction(
                            label: l10n.reasoningBudgetSheetAuto,
                            active: _selected == -1,
                            onTap: () async {
                              Haptics.light();
                              final navigator = Navigator.of(context);
                              await _select(-1);
                              if (!mounted) return;
                              navigator.maybePop();
                            },
                          ),
                          const SizedBox(width: 8),
                          _compactAction(
                            label: l10n.reasoningBudgetSheetCustomShortLabel,
                            active: customActive,
                            value: customActive ? _selected.toString() : null,
                            icon: Lucide.Hash,
                            onTap: () => _openCustomBudget(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
