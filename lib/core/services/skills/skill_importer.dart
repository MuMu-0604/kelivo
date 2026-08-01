import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:xml/xml.dart';
import 'package:yaml/yaml.dart';

import '../../../utils/unicode_sanitizer.dart';

class ImportedSkill {
  const ImportedSkill({
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

enum _SkillImportFormat { markdown, json, yaml, pdf, docx, zip }

class SkillImporter {
  static const int maxSkillChars = 30000;
  static const int maxZipEntries = 120;
  static const int maxZipSkills = 40;

  static const List<String> allowedExtensions = <String>[
    'md',
    'markdown',
    'txt',
    'json',
    'yaml',
    'yml',
    'pdf',
    'docx',
    'zip',
  ];

  const SkillImporter._();

  static Future<ImportedSkill> importFromFile(File file) async {
    final skills = await importManyFromFile(file);
    return skills.first;
  }

  static Future<List<ImportedSkill>> importManyFromFile(File file) async {
    return importManyFromBytes(
      bytes: await file.readAsBytes(),
      fileName: file.path,
    );
  }

  static ImportedSkill importFromBytes({
    required List<int> bytes,
    required String fileName,
  }) {
    return importManyFromBytes(bytes: bytes, fileName: fileName).first;
  }

  static List<ImportedSkill> importManyFromBytes({
    required List<int> bytes,
    required String fileName,
  }) {
    final format = _detectFormat(fileName, bytes);
    switch (format) {
      case _SkillImportFormat.zip:
        return _importManyFromZip(bytes);
      case _SkillImportFormat.json:
        return _importManyFromJson(_decodeText(bytes), fallbackName: fileName);
      case _SkillImportFormat.yaml:
        return _importManyFromYaml(_decodeText(bytes), fallbackName: fileName);
      case _SkillImportFormat.pdf:
        return <ImportedSkill>[
          parseMarkdown(
            _extractPdfText(bytes),
            fallbackName: _fallbackNameFromPath(fileName),
          ),
        ];
      case _SkillImportFormat.docx:
        return <ImportedSkill>[
          parseMarkdown(
            _extractDocxText(bytes),
            fallbackName: _fallbackNameFromPath(fileName),
          ),
        ];
      case _SkillImportFormat.markdown:
        return <ImportedSkill>[
          parseMarkdown(
            _decodeText(bytes),
            fallbackName: _fallbackNameFromPath(fileName),
          ),
        ];
    }
  }

  static List<ImportedSkill> _importManyFromZip(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    if (archive.length > maxZipEntries) {
      throw const FormatException('Skill archive has too many entries.');
    }

    final entries =
        archive.files
            .where(
              (entry) => entry.isFile && _isSupportedSkillEntry(entry.name),
            )
            .toList(growable: false)
          ..sort((a, b) {
            final aSkillFile = _isAllowedSkillEntry(a.name);
            final bSkillFile = _isAllowedSkillEntry(b.name);
            if (aSkillFile != bSkillFile) return aSkillFile ? -1 : 1;
            return a.name.compareTo(b.name);
          });
    if (entries.isEmpty) {
      throw const FormatException('No supported skill files found.');
    }

    final imported = <ImportedSkill>[];
    for (final entry in entries.take(maxZipSkills)) {
      try {
        final entryBytes = entry.readBytes();
        if (entryBytes == null) continue;
        imported.addAll(
          importManyFromBytes(bytes: entryBytes, fileName: entry.name),
        );
      } catch (_) {
        // Keep one bad file inside an archive from blocking the rest.
      }
    }
    if (imported.isEmpty) {
      throw const FormatException(
        'No valid skill files imported from archive.',
      );
    }
    return imported;
  }

  static bool _isAllowedSkillEntry(String rawName) {
    final normalized = p.posix.normalize(rawName.replaceAll('\\', '/'));
    if (normalized.startsWith('../') || normalized.startsWith('/')) {
      return false;
    }
    final parts = normalized
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty || parts.length > 3) return false;
    return parts.last.toLowerCase() == 'skill.md';
  }

  static bool _isSupportedSkillEntry(String rawName) {
    final normalized = p.posix.normalize(rawName.replaceAll('\\', '/'));
    if (normalized.startsWith('../') || normalized.startsWith('/')) {
      return false;
    }
    final parts = normalized
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty || parts.length > 4) return false;
    final extension = _extensionWithoutDot(parts.last);
    return allowedExtensions.contains(extension) && extension != 'zip';
  }

  static List<ImportedSkill> _importManyFromJson(
    String raw, {
    required String fallbackName,
  }) {
    final decoded = jsonDecode(raw);
    return _skillsFromStructuredRoot(decoded, fallbackName: fallbackName);
  }

  static List<ImportedSkill> _importManyFromYaml(
    String raw, {
    required String fallbackName,
  }) {
    final decoded = _normalizeYaml(loadYaml(raw));
    return _skillsFromStructuredRoot(decoded, fallbackName: fallbackName);
  }

  static List<ImportedSkill> _skillsFromStructuredRoot(
    dynamic root, {
    required String fallbackName,
  }) {
    final candidates = _extractStructuredSkillCandidates(root);
    final skills = <ImportedSkill>[];
    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      if (candidate is! Map) continue;
      final map = candidate.cast<String, dynamic>();
      final skill = _skillFromStructuredMap(
        map,
        fallbackName: candidates.length == 1
            ? _fallbackNameFromPath(fallbackName)
            : '${_fallbackNameFromPath(fallbackName)} ${i + 1}',
      );
      skills.add(skill);
    }
    if (skills.isEmpty) {
      throw const FormatException('No valid structured skills found.');
    }
    return skills;
  }

  static List<dynamic> _extractStructuredSkillCandidates(dynamic root) {
    if (root is List) return root;
    if (root is Map) {
      for (final key in const <String>['skills', 'items', 'data']) {
        final value = root[key];
        if (value is List) return value;
      }
      final nested = root['skill'];
      if (nested is Map) return <dynamic>[nested];
      return <dynamic>[root];
    }
    return const <dynamic>[];
  }

  static ImportedSkill _skillFromStructuredMap(
    Map<String, dynamic> map, {
    required String fallbackName,
  }) {
    final normalized = <String, dynamic>{};
    for (final entry in map.entries) {
      normalized[entry.key.toString().trim().toLowerCase()] = entry.value;
    }

    final name = _firstString(normalized, const <String>[
      'name',
      'title',
      'id',
    ], fallback: fallbackName);
    final description = _firstString(normalized, const <String>[
      'description',
      'summary',
    ]);
    final content = _firstString(normalized, const <String>[
      'content',
      'instructions',
      'instruction',
      'prompt',
      'system_prompt',
      'systemprompt',
      'body',
      'text',
      'markdown',
      'md',
    ]);
    final triggers = _parseTriggerValue(
      normalized['triggers'] ??
          normalized['triggerkeywords'] ??
          normalized['trigger_keywords'] ??
          normalized['keywords'] ??
          normalized['tags'],
    );

    final normalizedContent = content.trim().isEmpty
        ? _structuredMapAsMarkdown(map)
        : content.trim();
    return parseMarkdown(
      normalizedContent,
      fallbackName: name.trim().isEmpty ? fallbackName : name.trim(),
      fallbackDescription: description,
      fallbackTriggers: triggers,
    );
  }

  static ImportedSkill parseMarkdown(
    String raw, {
    String fallbackName = 'Skill',
    String fallbackDescription = '',
    List<String> fallbackTriggers = const <String>[],
  }) {
    final normalized = UnicodeSanitizer.sanitize(
      raw.replaceAll('\r\n', '\n'),
    ).trim();
    if (normalized.isEmpty) {
      throw const FormatException('Skill content is empty.');
    }
    final content = normalized.length > maxSkillChars
        ? '${normalized.substring(0, maxSkillChars)}\n\n[Skill content truncated by Kelivo due to context budget.]'
        : normalized;

    final frontMatter = _parseFrontMatter(content);
    final heading = RegExp(
      r'^#\s+(.+)$',
      multiLine: true,
    ).firstMatch(content)?.group(1)?.trim();
    final name =
        (frontMatter['name'] ?? frontMatter['title'] ?? heading ?? fallbackName)
            .trim();
    final description =
        (frontMatter['description'] ??
                (fallbackDescription.trim().isNotEmpty
                    ? fallbackDescription
                    : null) ??
                _firstParagraph(content))
            .trim();
    final triggers = _parseTriggers(
      frontMatter['triggers'] ?? frontMatter['keywords'],
    );

    return ImportedSkill(
      name: name.isEmpty ? fallbackName : name,
      description: description,
      content: content,
      triggerKeywords: triggers.isEmpty ? fallbackTriggers : triggers,
    );
  }

  static Map<String, String> _parseFrontMatter(String content) {
    if (!content.startsWith('---\n')) return const <String, String>{};
    final end = content.indexOf('\n---', 4);
    if (end <= 0) return const <String, String>{};
    final block = content.substring(4, end);
    final result = <String, String>{};
    for (final line in block.split('\n')) {
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final key = line.substring(0, colon).trim().toLowerCase();
      final value = line.substring(colon + 1).trim();
      if (key.isNotEmpty && value.isNotEmpty) {
        result[key] = _stripQuotes(value);
      }
    }
    return result;
  }

  static List<String> _parseTriggers(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const <String>[];
    return _parseTriggerValue(raw);
  }

  static List<String> _parseTriggerValue(dynamic raw) {
    if (raw == null) return const <String>[];
    if (raw is Iterable) {
      return raw
          .map((part) => _stripQuotes(part.toString().trim()))
          .where((part) => part.isNotEmpty)
          .toList(growable: false);
    }
    return raw
        .toString()
        .replaceAll('[', '')
        .replaceAll(']', '')
        .split(RegExp(r'[,;]'))
        .map((part) => _stripQuotes(part.trim()))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
  }

  static String _firstParagraph(String content) {
    final withoutFrontMatter = content.startsWith('---\n')
        ? content.substring(content.indexOf('\n---', 4) + 4).trim()
        : content;
    for (final part in withoutFrontMatter.split(RegExp(r'\n\s*\n'))) {
      final clean = part.trim();
      if (clean.isEmpty || clean.startsWith('#') || clean.startsWith('---')) {
        continue;
      }
      return clean.split('\n').first.trim();
    }
    return '';
  }

  static String _stripQuotes(String value) {
    if (value.length >= 2) {
      final first = value[0];
      final last = value[value.length - 1];
      if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
        return value.substring(1, value.length - 1);
      }
    }
    return value;
  }

  static String _fallbackNameFromPath(String path) {
    final base = p.basenameWithoutExtension(path).trim();
    if (base.isEmpty || base.toLowerCase() == 'skill') return 'Skill';
    return base;
  }

  static _SkillImportFormat _detectFormat(String fileName, List<int> bytes) {
    final extension = _extensionWithoutDot(fileName);
    switch (extension) {
      case 'zip':
        return _SkillImportFormat.zip;
      case 'json':
        return _SkillImportFormat.json;
      case 'yaml':
      case 'yml':
        return _SkillImportFormat.yaml;
      case 'pdf':
        return _SkillImportFormat.pdf;
      case 'docx':
        return _SkillImportFormat.docx;
    }
    if (_hasPrefix(bytes, const <int>[0x50, 0x4b, 0x03, 0x04])) {
      return _SkillImportFormat.zip;
    }
    if (_hasPrefix(bytes, const <int>[0x25, 0x50, 0x44, 0x46])) {
      return _SkillImportFormat.pdf;
    }
    return _SkillImportFormat.markdown;
  }

  static bool _hasPrefix(List<int> bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }

  static String _extensionWithoutDot(String path) {
    final extension = p.extension(path).toLowerCase();
    if (extension.startsWith('.')) return extension.substring(1);
    return extension;
  }

  static String _decodeText(List<int> bytes) {
    return UnicodeSanitizer.sanitize(utf8.decode(bytes, allowMalformed: true));
  }

  static String _extractPdfText(List<int> bytes) {
    PdfDocument? document;
    try {
      document = PdfDocument(inputBytes: bytes);
      final text = UnicodeSanitizer.sanitize(
        PdfTextExtractor(document).extractText(),
      );
      if (text.trim().isEmpty) {
        throw const FormatException('PDF contains no extractable text.');
      }
      return text;
    } finally {
      document?.dispose();
    }
  }

  static String _extractDocxText(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    final docXml = archive.findFile('word/document.xml');
    if (docXml == null) {
      throw const FormatException('DOCX document.xml not found.');
    }

    final docXmlBytes = docXml.readBytes();
    if (docXmlBytes == null) {
      throw const FormatException('DOCX document.xml could not be read.');
    }
    final xml = XmlDocument.parse(utf8.decode(docXmlBytes));
    final buffer = StringBuffer();
    for (final paragraph in xml.findAllElements('w:p')) {
      final texts = paragraph.findAllElements('w:t');
      if (texts.isEmpty) {
        buffer.writeln();
        continue;
      }
      for (final text in texts) {
        buffer.write(text.innerText);
      }
      buffer.writeln();
    }
    final text = UnicodeSanitizer.sanitize(buffer.toString()).trim();
    if (text.isEmpty) {
      throw const FormatException('DOCX contains no extractable text.');
    }
    return text;
  }

  static dynamic _normalizeYaml(dynamic value) {
    if (value is YamlMap) {
      return <String, dynamic>{
        for (final entry in value.entries)
          entry.key.toString(): _normalizeYaml(entry.value),
      };
    }
    if (value is YamlList) {
      return value.map(_normalizeYaml).toList(growable: false);
    }
    return value;
  }

  static String _firstString(
    Map<String, dynamic> map,
    List<String> keys, {
    String fallback = '',
  }) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
      if (value is num || value is bool) return value.toString();
    }
    return fallback;
  }

  static String _structuredMapAsMarkdown(Map<String, dynamic> map) {
    final buffer = StringBuffer();
    for (final entry in map.entries) {
      final key = entry.key.toString();
      final value = entry.value;
      if (value == null) continue;
      buffer.writeln('## $key');
      if (value is Iterable) {
        for (final item in value) {
          buffer.writeln('- $item');
        }
      } else if (value is Map) {
        buffer.writeln(const JsonEncoder.withIndent('  ').convert(value));
      } else {
        buffer.writeln(value.toString());
      }
      buffer.writeln();
    }
    final text = buffer.toString().trim();
    if (text.isEmpty) throw const FormatException('Skill content is empty.');
    return text;
  }
}
