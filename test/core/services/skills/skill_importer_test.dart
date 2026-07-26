import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/skills/skill_importer.dart';

void main() {
  group('SkillImporter', () {
    test('parses name description and triggers from markdown', () {
      final skill = SkillImporter.parseMarkdown('''
---
name: Code Review
description: Review code carefully
triggers: review, bug
---
# Ignored Heading

Use a strict review format.
''');

      expect(skill.name, 'Code Review');
      expect(skill.description, 'Review code carefully');
      expect(skill.triggerKeywords, const ['review', 'bug']);
      expect(skill.content, contains('Use a strict review format.'));
    });

    test('imports markdown from bytes', () {
      final skill = SkillImporter.importFromBytes(
        bytes: utf8.encode('# Writing Skill\n\nRewrite clearly.'),
        fileName: 'SKILL.md',
      );

      expect(skill.name, 'Writing Skill');
      expect(skill.content, contains('Rewrite clearly.'));
    });

    test('imports multiple skills from json arrays', () {
      final skills = SkillImporter.importManyFromBytes(
        bytes: utf8.encode('''
[
  {
    "name": "Review Skill",
    "description": "Find risky code",
    "instructions": "Return findings first.",
    "keywords": ["review", "regression"]
  },
  {
    "title": "Writer",
    "content": "Rewrite with a concise tone.",
    "triggers": "rewrite, polish"
  }
]
'''),
        fileName: 'skills.json',
      );

      expect(skills, hasLength(2));
      expect(skills.first.name, 'Review Skill');
      expect(skills.first.description, 'Find risky code');
      expect(skills.first.content, contains('Return findings first.'));
      expect(skills.first.triggerKeywords, const ['review', 'regression']);
      expect(skills.last.name, 'Writer');
      expect(skills.last.triggerKeywords, const ['rewrite', 'polish']);
    });

    test('imports skills from yaml', () {
      final skills = SkillImporter.importManyFromBytes(
        bytes: utf8.encode('''
skills:
  - name: DCF Skill
    description: Build valuation models
    content: Always separate assumptions and outputs.
    triggers:
      - dcf
      - valuation
'''),
        fileName: 'skills.yaml',
      );

      expect(skills, hasLength(1));
      expect(skills.single.name, 'DCF Skill');
      expect(skills.single.description, 'Build valuation models');
      expect(skills.single.content, contains('Always separate assumptions'));
      expect(skills.single.triggerKeywords, const ['dcf', 'valuation']);
    });

    test('imports multiple supported entries from zip archives', () {
      final archive = Archive()
        ..addFile(
          ArchiveFile(
            'review/SKILL.md',
            34,
            utf8.encode('# Review\n\nCheck behavior changes.'),
          ),
        )
        ..addFile(
          ArchiveFile(
            'writer.json',
            87,
            utf8.encode('''
{"name":"Writer","content":"Use short sentences.","keywords":["write"]}
'''),
          ),
        );
      final bytes = ZipEncoder().encode(archive);

      final skills = SkillImporter.importManyFromBytes(
        bytes: bytes,
        fileName: 'bundle.zip',
      );

      expect(skills.map((skill) => skill.name), ['Review', 'Writer']);
      expect(skills.last.triggerKeywords, const ['write']);
    });

    test('imports text from docx files', () {
      const documentXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:r><w:t>Docx Skill</w:t></w:r></w:p>
    <w:p><w:r><w:t>Follow imported document guidance.</w:t></w:r></w:p>
  </w:body>
</w:document>
''';
      final archive = Archive()
        ..addFile(
          ArchiveFile(
            'word/document.xml',
            utf8.encode(documentXml).length,
            utf8.encode(documentXml),
          ),
        );
      final bytes = ZipEncoder().encode(archive);

      final skill = SkillImporter.importFromBytes(
        bytes: bytes,
        fileName: 'docx-skill.docx',
      );

      expect(skill.name, 'docx-skill');
      expect(skill.content, contains('Docx Skill'));
      expect(skill.content, contains('Follow imported document guidance.'));
    });
  });
}
