import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/providers/skill_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SkillProvider', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('resolves explicit skills before keyword-triggered skills', () async {
      final provider = SkillProvider();
      final explicitId = await provider.addSkill(
        name: 'Explicit',
        content: 'Always include me.',
      );
      await provider.addSkill(
        name: 'Triggered',
        content: 'Keyword match.',
        triggerKeywords: const ['forecast'],
      );

      final resolved = provider.resolveActiveSkills(
        explicitSkillIds: [explicitId],
        latestUserMessage: 'Build a forecast.',
      );

      expect(resolved.map((skill) => skill.name), ['Explicit', 'Triggered']);
    });

    test('disabled skills are not resolved', () async {
      final provider = SkillProvider();
      final id = await provider.addSkill(
        name: 'Disabled',
        content: 'Nope.',
        triggerKeywords: const ['forecast'],
      );
      await provider.setEnabled(id, false);

      final resolved = provider.resolveActiveSkills(
        explicitSkillIds: [id],
        latestUserMessage: 'forecast',
      );

      expect(resolved, isEmpty);
    });
  });
}
