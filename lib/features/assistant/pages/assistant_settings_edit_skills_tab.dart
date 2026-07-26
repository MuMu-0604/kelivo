part of 'assistant_settings_edit_page.dart';

class _SkillsTab extends StatelessWidget {
  const _SkillsTab({required this.assistantId});

  final String assistantId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final skillProvider = context.watch<SkillProvider>();
    final assistantProvider = context.watch<AssistantProvider>();
    final assistant = assistantProvider.getById(assistantId);
    final skills = skillProvider.skills;

    if (assistant == null) {
      return const SizedBox.shrink();
    }

    Future<void> updateBinding(String skillId, bool enabled) async {
      final ids = assistant.skillIds.toSet();
      if (enabled) {
        ids.add(skillId);
      } else {
        ids.remove(skillId);
      }
      await context.read<AssistantProvider>().updateAssistant(
        assistant.copyWith(skillIds: ids.toList(growable: false)),
      );
    }

    if (skills.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Lucide.Sparkles,
                size: 64,
                color: cs.primary.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.assistantEditSkillsEmptyMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 24),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 200),
                child: _IosButton(
                  label: l10n.assistantEditManageSkillsButton,
                  icon: Lucide.Sparkles,
                  filled: true,
                  neutral: false,
                  onTap: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const SkillsPage())),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _iosSectionCard(
          children: [
            _iosNavRow(
              context,
              icon: Lucide.Sparkles,
              label: l10n.assistantEditManageSkillsButton,
              detailText: '${skills.length}',
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SkillsPage())),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _iosSectionCard(
          children: [
            for (var i = 0; i < skills.length; i++) ...[
              _SkillBindingRow(
                skill: skills[i],
                enabled: assistant.skillIds.contains(skills[i].id),
                onChanged: (enabled) => updateBinding(skills[i].id, enabled),
              ),
              if (i != skills.length - 1) _iosDivider(context),
            ],
          ],
        ),
      ],
    );
  }
}

class _SkillBindingRow extends StatelessWidget {
  const _SkillBindingRow({
    required this.skill,
    required this.enabled,
    required this.onChanged,
  });

  final Skill skill;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _TactileRow(
      onTap: () => onChanged(!enabled),
      builder: (pressed) {
        final baseColor = cs.onSurface.withValues(alpha: 0.9);
        return _AnimatedPressColor(
          pressed: pressed,
          base: baseColor,
          builder: (color) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 36,
                    child: Icon(
                      Lucide.Sparkles,
                      size: 20,
                      color: enabled ? cs.primary : color,
                    ),
                  ),
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
                            color: color,
                            fontWeight: AppFontWeights.semibold,
                          ),
                        ),
                        if (skill.description.trim().isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            skill.description.trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.25,
                              color: cs.onSurface.withValues(alpha: 0.62),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  IosSwitch(value: enabled, onChanged: onChanged),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
