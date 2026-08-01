import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';

import '../../../core/models/skill.dart';
import '../../../core/providers/skill_provider.dart';
import '../../../core/services/skills/skill_importer.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/app_font_weights.dart';

class SkillsPage extends StatefulWidget {
  const SkillsPage({super.key});

  @override
  State<SkillsPage> createState() => _SkillsPageState();
}

class _SkillsPageState extends State<SkillsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SkillProvider>().initialize();
    });
  }

  Future<void> _importSkill() async {
    final l10n = AppLocalizations.of(context)!;
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
        type: FileType.custom,
        allowedExtensions: SkillImporter.allowedExtensions,
      );
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.skillsImportFailed(e.toString()),
        type: NotificationType.error,
      );
      return;
    }
    if (!mounted || result == null || result.files.isEmpty) return;

    var imported = 0;
    final provider = context.read<SkillProvider>();
    for (final picked in result.files) {
      try {
        final bytes = picked.bytes;
        final path = picked.path;
        if (bytes != null && bytes.isNotEmpty) {
          final skills = await provider.importManyFromBytes(
            bytes: bytes,
            fileName: picked.name,
            sourcePath: path,
          );
          imported += skills.length;
        } else if (!kIsWeb && path != null && path.isNotEmpty) {
          final skills = await provider.importManyFromFile(File(path));
          imported += skills.length;
        } else {
          continue;
        }
      } catch (_) {}
    }
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: imported == 0
          ? l10n.skillsNoValidImported
          : l10n.skillsImportedCount(imported),
      type: imported == 0 ? NotificationType.warning : NotificationType.success,
    );
  }

  Future<void> _showAddEditSheet({Skill? skill}) async {
    final result = await showModalBottomSheet<_SkillEditResult?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _SkillEditSheet(skill: skill),
    );
    if (!mounted || result == null) return;
    final provider = context.read<SkillProvider>();
    if (skill == null) {
      await provider.addSkill(
        name: result.name,
        description: result.description,
        content: result.content,
        triggerKeywords: result.triggerKeywords,
      );
    } else {
      await provider.updateSkill(
        skill.copyWith(
          name: result.name,
          description: result.description,
          content: result.content,
          triggerKeywords: result.triggerKeywords,
        ),
      );
    }
  }

  Future<void> _deleteSkill(Skill skill) async {
    await context.read<SkillProvider>().deleteSkill(skill.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final skills = context.watch<SkillProvider>().skills;
    return Scaffold(
      appBar: AppBar(
        leading: Tooltip(
          message: MaterialLocalizations.of(context).backButtonTooltip,
          child: IosIconButton(
            icon: Lucide.ArrowLeft,
            color: cs.onSurface,
            size: 22,
            minSize: 44,
            semanticLabel: MaterialLocalizations.of(context).backButtonTooltip,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(l10n.skillsTitle),
        actions: [
          Tooltip(
            message: l10n.skillsImportTooltip,
            child: IosIconButton(
              icon: Lucide.Import,
              color: cs.onSurface,
              size: 21,
              minSize: 44,
              semanticLabel: l10n.skillsImportTooltip,
              onTap: _importSkill,
            ),
          ),
          Tooltip(
            message: l10n.skillsAddTooltip,
            child: IosIconButton(
              icon: Lucide.Plus,
              color: cs.onSurface,
              size: 22,
              minSize: 44,
              semanticLabel: l10n.skillsAddTooltip,
              onTap: () => _showAddEditSheet(),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: skills.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Lucide.Sparkles,
                      size: 68,
                      color: cs.primary.withValues(alpha: 0.55),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.skillsEmptyMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.35,
                        color: cs.onSurface.withValues(alpha: 0.68),
                      ),
                    ),
                    const SizedBox(height: 22),
                    FilledButton.icon(
                      onPressed: _importSkill,
                      icon: const Icon(Lucide.Import, size: 18),
                      label: Text(l10n.skillsImportButton),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              itemCount: skills.length,
              itemBuilder: (context, index) {
                final skill = skills[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Slidable(
                    key: ValueKey('skill-${skill.id}'),
                    endActionPane: ActionPane(
                      motion: const StretchMotion(),
                      extentRatio: 0.34,
                      children: [
                        CustomSlidableAction(
                          autoClose: true,
                          backgroundColor: Colors.transparent,
                          onPressed: (_) => _deleteSkill(skill),
                          child: _DeleteActionLabel(
                            label: l10n.skillsDeleteAction,
                          ),
                        ),
                      ],
                    ),
                    child: _SkillTile(
                      skill: skill,
                      onTap: () => _showAddEditSheet(skill: skill),
                      onEnabledChanged: (enabled) => context
                          .read<SkillProvider>()
                          .setEnabled(skill.id, enabled),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _SkillTile extends StatelessWidget {
  const _SkillTile({
    required this.skill,
    required this.onTap,
    required this.onEnabledChanged,
  });

  final Skill skill;
  final VoidCallback onTap;
  final ValueChanged<bool> onEnabledChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: isDark ? Colors.white10 : Colors.white.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Icon(Lucide.Sparkles, size: 20, color: cs.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      skill.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: AppFontWeights.semibold,
                      ),
                    ),
                    if (skill.description.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        skill.description.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.25,
                          color: cs.onSurface.withValues(alpha: 0.62),
                        ),
                      ),
                    ],
                    if (skill.triggerKeywords.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        l10n.skillsTriggersLine(
                          skill.triggerKeywords.join(', '),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.primary.withValues(alpha: 0.82),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch.adaptive(
                value: skill.enabled,
                onChanged: onEnabledChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeleteActionLabel extends StatelessWidget {
  const _DeleteActionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: isDark
            ? cs.error.withValues(alpha: 0.22)
            : cs.error.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.error.withValues(alpha: 0.35)),
      ),
      alignment: Alignment.center,
      child: FittedBox(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Lucide.Trash2, color: cs.error, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: cs.error,
                fontWeight: AppFontWeights.emphasis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkillEditResult {
  const _SkillEditResult({
    required this.name,
    required this.description,
    required this.content,
    required this.triggerKeywords,
  });

  final String name;
  final String description;
  final String content;
  final List<String> triggerKeywords;
}

class _SkillEditSheet extends StatefulWidget {
  const _SkillEditSheet({this.skill});
  final Skill? skill;

  @override
  State<_SkillEditSheet> createState() => _SkillEditSheetState();
}

class _SkillEditSheetState extends State<_SkillEditSheet> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.skill?.name ?? '',
  );
  late final TextEditingController _descriptionController =
      TextEditingController(text: widget.skill?.description ?? '');
  late final TextEditingController _contentController = TextEditingController(
    text: widget.skill?.content ?? '',
  );
  late final TextEditingController _triggersController = TextEditingController(
    text: widget.skill?.triggerKeywords.join(', ') ?? '',
  );

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _contentController.dispose();
    _triggersController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    final content = _contentController.text.trim();
    if (name.isEmpty || content.isEmpty) return;
    Navigator.of(context).pop(
      _SkillEditResult(
        name: name,
        description: _descriptionController.text.trim(),
        content: content,
        triggerKeywords: _triggersController.text
            .split(RegExp(r'[,;]'))
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty)
            .toList(growable: false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.9,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 10, 16, bottom + 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: Text(
                    MaterialLocalizations.of(context).closeButtonLabel,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _save,
                  child: Text(l10n.skillsSaveButton),
                ),
              ],
            ),
            TextField(
              controller: _nameController,
              autofocus: widget.skill == null,
              decoration: InputDecoration(labelText: l10n.skillsNameLabel),
            ),
            TextField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: l10n.skillsDescriptionLabel,
              ),
            ),
            TextField(
              controller: _triggersController,
              decoration: InputDecoration(
                labelText: l10n.skillsTriggerKeywordsLabel,
                hintText: l10n.skillsTriggerKeywordsHint,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white10
                      : const Color(0xFFF7F7F9),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.2),
                  ),
                ),
                child: TextField(
                  controller: _contentController,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  keyboardType: TextInputType.multiline,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: InputDecoration(
                    hintText: l10n.skillsContentHint,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
