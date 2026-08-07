import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/assistant.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tactile.dart';

Future<void> showDocumentProcessingSheet(
  BuildContext context, {
  String? assistantId,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: DocumentProcessingConfigContent(assistantId: assistantId),
      ),
    ),
  );
}

class DocumentProcessingConfigContent extends StatelessWidget {
  const DocumentProcessingConfigContent({super.key, this.assistantId});

  final String? assistantId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final assistantProvider = context.watch<AssistantProvider>();
    final settings = context.watch<SettingsProvider>();
    final assistant = assistantId == null
        ? assistantProvider.currentAssistant
        : assistantProvider.getById(assistantId!);
    final hasOcrModel =
        settings.ocrModelProvider != null && settings.ocrModelId != null;

    Future<void> update(Assistant next) async {
      await context.read<AssistantProvider>().updateAssistant(next);
    }

    Widget section(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );

    if (assistant == null) {
      return Text(l10n.documentProcessingNoAssistant);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(
              Lucide.FileText,
              size: 22,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.documentProcessingTitle,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        section(l10n.documentProcessingImageOcr),
        _ModeGroup(
          value: assistant.ocrMode,
          options: [
            _ModeOption(Assistant.ocrModeAuto, l10n.documentProcessingOcrAuto),
            _ModeOption(
              Assistant.ocrModeAlways,
              l10n.documentProcessingOcrAlways,
            ),
            _ModeOption(
              Assistant.ocrModeNever,
              l10n.documentProcessingOcrNever,
            ),
          ],
          enabled: hasOcrModel,
          disabledText: l10n.documentProcessingOcrModelMissing,
          onChanged: (value) => update(assistant.copyWith(ocrMode: value)),
        ),
        section(l10n.documentProcessingDocx),
        _ModeGroup(
          value: assistant.docxMode,
          options: _documentModeOptions(l10n),
          onChanged: (value) => update(assistant.copyWith(docxMode: value)),
        ),
        section(l10n.documentProcessingPdf),
        _ModeGroup(
          value: assistant.pdfMode,
          options: _documentModeOptions(l10n),
          onChanged: (value) => update(assistant.copyWith(pdfMode: value)),
        ),
        section(l10n.documentProcessingOtherOffice),
        _ModeGroup(
          value: assistant.otherOfficeMode,
          options: _documentModeOptions(l10n),
          onChanged: (value) =>
              update(assistant.copyWith(otherOfficeMode: value)),
        ),
      ],
    );
  }

  List<_ModeOption> _documentModeOptions(AppLocalizations l10n) => [
    _ModeOption(
      Assistant.documentModeExtract,
      l10n.documentProcessingModeExtract,
    ),
    _ModeOption(
      Assistant.documentModeDirect,
      l10n.documentProcessingModeDirect,
    ),
    _ModeOption(
      Assistant.documentModeDiscard,
      l10n.documentProcessingModeDiscard,
    ),
  ];
}

class _ModeOption {
  const _ModeOption(this.value, this.label);
  final String value;
  final String label;
}

class _ModeGroup extends StatelessWidget {
  const _ModeGroup({
    required this.value,
    required this.options,
    required this.onChanged,
    this.enabled = true,
    this.disabledText,
  });

  final String value;
  final List<_ModeOption> options;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final String? disabledText;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final option in options) ...[
          _ModeTile(
            label: option.label,
            selected: value == option.value,
            enabled: enabled,
            onTap: () => onChanged(option.value),
          ),
          const SizedBox(height: 8),
        ],
        if (!enabled && disabledText != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
            child: Text(
              disabledText!,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = selected ? cs.primary : cs.onSurface;
    return SizedBox(
      height: 44,
      child: IosCardPress(
        borderRadius: BorderRadius.circular(14),
        baseColor: selected
            ? cs.primary.withValues(alpha: 0.10)
            : cs.surfaceContainerHighest.withValues(alpha: 0.45),
        onTap: enabled ? onTap : null,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: enabled ? color : cs.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            if (selected) Icon(Lucide.Check, size: 18, color: cs.primary),
          ],
        ),
      ),
    );
  }
}
