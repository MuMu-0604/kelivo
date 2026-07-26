import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/skill.dart';
import '../services/skills/skill_importer.dart';

class SkillProvider extends ChangeNotifier {
  static const String _skillsKey = 'skills_v1';

  final List<Skill> _skills = <Skill>[];
  bool _initialized = false;

  List<Skill> get skills => List.unmodifiable(_skills);
  bool get initialized => _initialized;

  SkillProvider() {
    initialize();
  }

  Future<void> initialize() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_skillsKey);
    if (raw != null && raw.isNotEmpty) {
      _skills
        ..clear()
        ..addAll(Skill.decodeList(raw).where((s) => s.id.isNotEmpty));
      _sortSkills();
    }
    _initialized = true;
    notifyListeners();
  }

  Skill? getById(String id) {
    final index = _skills.indexWhere((skill) => skill.id == id);
    if (index == -1) return null;
    return _skills[index];
  }

  Future<Skill> importFromFile(File file) async {
    await initialize();
    final imported = await SkillImporter.importFromFile(file);
    return _addImported(imported, sourcePath: file.path);
  }

  Future<List<Skill>> importManyFromFile(File file) async {
    await initialize();
    final imported = await SkillImporter.importManyFromFile(file);
    return _addManyImported(imported, sourcePath: file.path);
  }

  Future<Skill> importFromBytes({
    required List<int> bytes,
    required String fileName,
    String? sourcePath,
  }) async {
    await initialize();
    final imported = SkillImporter.importFromBytes(
      bytes: bytes,
      fileName: fileName,
    );
    return _addImported(imported, sourcePath: sourcePath ?? fileName);
  }

  Future<List<Skill>> importManyFromBytes({
    required List<int> bytes,
    required String fileName,
    String? sourcePath,
  }) async {
    await initialize();
    final imported = SkillImporter.importManyFromBytes(
      bytes: bytes,
      fileName: fileName,
    );
    return _addManyImported(imported, sourcePath: sourcePath ?? fileName);
  }

  Future<Skill> _addImported(
    ImportedSkill imported, {
    String? sourcePath,
  }) async {
    final skills = await _addManyImported(<ImportedSkill>[
      imported,
    ], sourcePath: sourcePath);
    return skills.first;
  }

  Future<List<Skill>> _addManyImported(
    List<ImportedSkill> imported, {
    String? sourcePath,
  }) async {
    final now = DateTime.now();
    final skills = imported
        .map(
          (item) => Skill(
            id: const Uuid().v4(),
            name: item.name,
            description: item.description,
            content: item.content,
            triggerKeywords: item.triggerKeywords,
            sourcePath: sourcePath,
            createdAt: now,
            updatedAt: now,
          ),
        )
        .toList(growable: false);
    _skills.addAll(skills);
    _sortSkills();
    await _persist();
    notifyListeners();
    return skills;
  }

  Future<String> addSkill({
    required String name,
    required String content,
    String description = '',
    List<String> triggerKeywords = const <String>[],
    int priority = 0,
  }) async {
    await initialize();
    final now = DateTime.now();
    final skill = Skill(
      id: const Uuid().v4(),
      name: name.trim().isEmpty ? '技能' : name.trim(),
      description: description.trim(),
      content: content,
      triggerKeywords: triggerKeywords,
      priority: priority,
      createdAt: now,
      updatedAt: now,
    );
    _skills.add(skill);
    _sortSkills();
    await _persist();
    notifyListeners();
    return skill.id;
  }

  Future<void> updateSkill(Skill updated) async {
    await initialize();
    final index = _skills.indexWhere((skill) => skill.id == updated.id);
    if (index == -1) return;
    _skills[index] = updated.copyWith(updatedAt: DateTime.now());
    _sortSkills();
    await _persist();
    notifyListeners();
  }

  Future<void> deleteSkill(String id) async {
    await initialize();
    _skills.removeWhere((skill) => skill.id == id);
    await _persist();
    notifyListeners();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final skill = getById(id);
    if (skill == null || skill.enabled == enabled) return;
    await updateSkill(skill.copyWith(enabled: enabled));
  }

  List<Skill> resolveActiveSkills({
    required List<String> explicitSkillIds,
    String latestUserMessage = '',
    int maxSkills = 5,
  }) {
    final explicit = explicitSkillIds.toSet();
    final query = latestUserMessage.toLowerCase();
    final candidates = <({Skill skill, bool explicit})>[];

    for (final skill in _skills) {
      if (!skill.enabled) continue;
      final isExplicit = explicit.contains(skill.id);
      final triggered = !isExplicit && _matchesKeywords(skill, query);
      if (isExplicit || triggered) {
        candidates.add((skill: skill, explicit: isExplicit));
      }
    }

    candidates.sort((a, b) {
      if (a.explicit != b.explicit) return a.explicit ? -1 : 1;
      final priority = b.skill.priority.compareTo(a.skill.priority);
      if (priority != 0) return priority;
      return b.skill.updatedAt.compareTo(a.skill.updatedAt);
    });

    return candidates
        .take(maxSkills)
        .map((candidate) => candidate.skill)
        .toList(growable: false);
  }

  bool _matchesKeywords(Skill skill, String query) {
    if (query.trim().isEmpty || skill.triggerKeywords.isEmpty) return false;
    for (final raw in skill.triggerKeywords) {
      final keyword = raw.trim().toLowerCase();
      if (keyword.isNotEmpty && query.contains(keyword)) return true;
    }
    return false;
  }

  void _sortSkills() {
    _skills.sort((a, b) {
      final priority = b.priority.compareTo(a.priority);
      if (priority != 0) return priority;
      return b.updatedAt.compareTo(a.updatedAt);
    });
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_skillsKey, Skill.encodeList(_skills));
  }
}
