import '../core/models/provider_group.dart';

const String providerUngroupedGroupKey = '__ungrouped__';

List<String> buildProviderGroupDisplayKeys({
  required List<ProviderGroup> groups,
  required int ungroupedIndex,
}) {
  final keys = [for (final group in groups) group.id];
  final insertIndex = ungroupedIndex.clamp(0, keys.length);
  keys.insert(insertIndex, providerUngroupedGroupKey);
  return List<String>.unmodifiable(keys);
}

class ProviderGroupDisplayReorderResult {
  const ProviderGroupDisplayReorderResult({
    required this.groups,
    required this.ungroupedIndex,
  });

  final List<ProviderGroup> groups;
  final int ungroupedIndex;
}

ProviderGroupDisplayReorderResult insertProviderGroup({
  required List<ProviderGroup> groups,
  required int ungroupedIndex,
  required ProviderGroup group,
  int? insertIndex,
}) {
  final normalizedInsertIndex = (insertIndex ?? groups.length).clamp(
    0,
    groups.length,
  );
  final nextGroups = List<ProviderGroup>.of(groups)
    ..insert(normalizedInsertIndex, group);
  final nextUngroupedIndex =
      ungroupedIndex.clamp(0, groups.length) >= normalizedInsertIndex
      ? ungroupedIndex.clamp(0, groups.length) + 1
      : ungroupedIndex.clamp(0, groups.length);

  return ProviderGroupDisplayReorderResult(
    groups: List<ProviderGroup>.unmodifiable(nextGroups),
    ungroupedIndex: nextUngroupedIndex.clamp(0, nextGroups.length),
  );
}

ProviderGroupDisplayReorderResult reorderProviderGroupDisplayWithUngrouped({
  required List<ProviderGroup> groups,
  required int ungroupedIndex,
  required int oldIndex,
  required int newIndex,
}) {
  final displayKeys = buildProviderGroupDisplayKeys(
    groups: groups,
    ungroupedIndex: ungroupedIndex,
  );
  if (displayKeys.isEmpty) {
    return ProviderGroupDisplayReorderResult(
      groups: List<ProviderGroup>.unmodifiable(groups),
      ungroupedIndex: 0,
    );
  }
  if (oldIndex < 0 || oldIndex >= displayKeys.length) {
    return ProviderGroupDisplayReorderResult(
      groups: List<ProviderGroup>.unmodifiable(groups),
      ungroupedIndex: ungroupedIndex.clamp(0, groups.length),
    );
  }
  final normalizedNewIndex = newIndex.clamp(0, displayKeys.length);
  if (oldIndex == normalizedNewIndex) {
    return ProviderGroupDisplayReorderResult(
      groups: List<ProviderGroup>.unmodifiable(groups),
      ungroupedIndex: ungroupedIndex.clamp(0, groups.length),
    );
  }

  final mutKeys = List<String>.of(displayKeys);
  final item = mutKeys.removeAt(oldIndex);
  final insertIndex = normalizedNewIndex > oldIndex
      ? normalizedNewIndex - 1
      : normalizedNewIndex;
  mutKeys.insert(insertIndex.clamp(0, mutKeys.length), item);

  final groupById = {for (final group in groups) group.id: group};
  final nextGroups = <ProviderGroup>[];
  int nextUngroupedIndex = mutKeys.length;
  for (int i = 0; i < mutKeys.length; i++) {
    final key = mutKeys[i];
    if (key == providerUngroupedGroupKey) {
      nextUngroupedIndex = i;
      continue;
    }
    final group = groupById[key];
    if (group != null) nextGroups.add(group);
  }

  return ProviderGroupDisplayReorderResult(
    groups: List<ProviderGroup>.unmodifiable(nextGroups),
    ungroupedIndex: nextUngroupedIndex.clamp(0, nextGroups.length),
  );
}

int mapVisibleGroupTargetToActualInsertIndex({
  required List<String> fullDisplayKeys,
  required List<String> visibleHeaderKeys,
  required String movedGroupKey,
  required int targetVisibleIndex,
}) {
  final fullWithoutMoved = List<String>.of(fullDisplayKeys)
    ..remove(movedGroupKey);
  final remainingVisibleHeaderKeys = [
    for (final key in visibleHeaderKeys)
      if (key != movedGroupKey) key,
  ];

  if (remainingVisibleHeaderKeys.isEmpty) {
    return fullWithoutMoved.length;
  }
  if (targetVisibleIndex <= 0) {
    final idx = fullWithoutMoved.indexOf(remainingVisibleHeaderKeys.first);
    return idx >= 0 ? idx : fullWithoutMoved.length;
  }
  if (targetVisibleIndex >= remainingVisibleHeaderKeys.length) {
    final idx = fullWithoutMoved.indexOf(remainingVisibleHeaderKeys.last);
    return idx >= 0 ? idx + 1 : fullWithoutMoved.length;
  }
  final idx = fullWithoutMoved.indexOf(
    remainingVisibleHeaderKeys[targetVisibleIndex],
  );
  return idx >= 0 ? idx : fullWithoutMoved.length;
}

// ----- Reorder analysis (UI-independent) -----

sealed class ProviderGroupingRowVM {
  const ProviderGroupingRowVM();
}

class ProviderGroupingHeaderVM extends ProviderGroupingRowVM {
  const ProviderGroupingHeaderVM({required this.groupKey});
  final String groupKey; // groupId or `__ungrouped__`
}

class ProviderGroupingProviderVM extends ProviderGroupingRowVM {
  const ProviderGroupingProviderVM({
    required this.providerKey,
    required this.groupKey,
  });
  final String providerKey;
  final String groupKey; // groupId or `__ungrouped__` (original group)
}

class ProviderGroupingMoveIntent {
  const ProviderGroupingMoveIntent({
    required this.providerKey,
    required this.targetGroupKey,
    required this.targetPos,
  });

  final String providerKey;

  /// groupId or `__ungrouped__`
  final String targetGroupKey;

  /// Position within the target group's visible provider segment (0-based).
  final int targetPos;
}

class ProviderGroupingHeaderReorderIntent {
  const ProviderGroupingHeaderReorderIntent({
    required this.groupKey,
    required this.targetDisplayIndex,
  });

  final String groupKey;
  final int targetDisplayIndex;
}

enum ProviderGroupingReorderBlockedReason { targetGroupCollapsed }

class ProviderGroupingReorderAnalysis {
  final ProviderGroupingMoveIntent? intent;
  final ProviderGroupingReorderBlockedReason? blockedReason;

  const ProviderGroupingReorderAnalysis._({this.intent, this.blockedReason});

  const ProviderGroupingReorderAnalysis.allowed(
    ProviderGroupingMoveIntent intent,
  ) : this._(intent: intent);

  const ProviderGroupingReorderAnalysis.blocked(
    ProviderGroupingReorderBlockedReason reason,
  ) : this._(blockedReason: reason);

  const ProviderGroupingReorderAnalysis.invalid() : this._();

  bool get isAllowed => intent != null;
  bool get isBlocked => blockedReason != null;
  bool get isInvalid => intent == null && blockedReason == null;
}

ProviderGroupingReorderAnalysis analyzeProviderGroupingReorder({
  required List<ProviderGroupingRowVM> rows,
  required int oldIndex,
  required int newIndex,
  required bool Function(String groupKey) isGroupCollapsed,
  bool disallowInsertBeforeFirstHeader = true,
  bool disallowCrossGroupIntoCollapsedEmpty = true,
}) {
  if (rows.isEmpty) return const ProviderGroupingReorderAnalysis.invalid();
  if (oldIndex < 0 || oldIndex >= rows.length) {
    return const ProviderGroupingReorderAnalysis.invalid();
  }

  // Normalize newIndex because Flutter passes the index after removal.
  if (newIndex > oldIndex) newIndex -= 1;
  newIndex = newIndex.clamp(0, rows.length);
  if (disallowInsertBeforeFirstHeader && newIndex == 0) newIndex = 1;
  if (newIndex == oldIndex) {
    return const ProviderGroupingReorderAnalysis.invalid();
  }

  final moved = rows[oldIndex];
  if (moved is! ProviderGroupingProviderVM) {
    return const ProviderGroupingReorderAnalysis.invalid();
  }
  final oldGroupKey = moved.groupKey;

  final sim = List<ProviderGroupingRowVM>.from(rows);
  final removed = sim.removeAt(oldIndex);
  final insertIndex = newIndex.clamp(0, sim.length);
  sim.insert(insertIndex, removed);
  final movedIndex = insertIndex;

  int headerIndex = -1;
  for (int i = movedIndex - 1; i >= 0; i--) {
    if (sim[i] is ProviderGroupingHeaderVM) {
      headerIndex = i;
      break;
    }
  }
  if (headerIndex < 0) return const ProviderGroupingReorderAnalysis.invalid();

  final targetGroupKey =
      (sim[headerIndex] as ProviderGroupingHeaderVM).groupKey;

  if (disallowCrossGroupIntoCollapsedEmpty) {
    final isCrossGroup = oldGroupKey != targetGroupKey;
    final targetVisibleCount = rows
        .whereType<ProviderGroupingProviderVM>()
        .where(
          (e) => e.groupKey == targetGroupKey && !isGroupCollapsed(e.groupKey),
        )
        .length;
    if (isCrossGroup &&
        isGroupCollapsed(targetGroupKey) &&
        targetVisibleCount == 0) {
      return const ProviderGroupingReorderAnalysis.blocked(
        ProviderGroupingReorderBlockedReason.targetGroupCollapsed,
      );
    }
  }

  int targetPos = 0;
  for (int i = headerIndex + 1; i < movedIndex; i++) {
    if (sim[i] is ProviderGroupingProviderVM &&
        !isGroupCollapsed((sim[i] as ProviderGroupingProviderVM).groupKey)) {
      targetPos++;
    }
  }

  return ProviderGroupingReorderAnalysis.allowed(
    ProviderGroupingMoveIntent(
      providerKey: moved.providerKey,
      targetGroupKey: targetGroupKey,
      targetPos: targetPos,
    ),
  );
}

ProviderGroupingHeaderReorderIntent? analyzeProviderGroupingHeaderReorder({
  required List<ProviderGroupingRowVM> rows,
  required int oldIndex,
  required int newIndex,
}) {
  if (rows.isEmpty || oldIndex < 0 || oldIndex >= rows.length) return null;

  final moved = rows[oldIndex];
  if (moved is! ProviderGroupingHeaderVM) return null;

  final normalizedNewIndex = newIndex.clamp(0, rows.length);
  final sim = List<ProviderGroupingRowVM>.from(rows);
  final removed = sim.removeAt(oldIndex);
  final insertIndex = normalizedNewIndex > oldIndex
      ? normalizedNewIndex - 1
      : normalizedNewIndex;
  sim.insert(insertIndex.clamp(0, sim.length), removed);

  final headerOrder = [
    for (final row in sim)
      if (row is ProviderGroupingHeaderVM) row.groupKey,
  ];
  final targetDisplayIndex = headerOrder.indexOf(moved.groupKey);
  if (targetDisplayIndex < 0) return null;

  return ProviderGroupingHeaderReorderIntent(
    groupKey: moved.groupKey,
    targetDisplayIndex: targetDisplayIndex,
  );
}

// ----- Provider order + group map updates (pure) -----

class ProviderGroupingMoveResult {
  const ProviderGroupingMoveResult({
    required this.providersOrder,
    required this.providerGroupMap,
  });

  final List<String> providersOrder;

  /// providerKey -> groupId (missing = ungrouped)
  final Map<String, String> providerGroupMap;
}

List<String> buildProviderKeysInGroupedDisplayOrder({
  required List<String> providersOrder,
  required List<ProviderGroup> groups,
  required int ungroupedIndex,
  required Map<String, String> providerGroupMap,
  required Iterable<String> knownProviderKeys,
}) {
  final validGroupIds = {for (final g in groups) g.id};
  final mergedOrder = <String>[];
  final seen = <String>{};

  for (final key in providersOrder) {
    if (!seen.add(key)) continue;
    mergedOrder.add(key);
  }
  for (final key in knownProviderKeys) {
    if (!seen.add(key)) continue;
    mergedOrder.add(key);
  }

  String? groupIdFor(String key) {
    final gid = providerGroupMap[key];
    return (gid != null && validGroupIds.contains(gid)) ? gid : null;
  }

  final result = <String>[];
  final displayKeys = buildProviderGroupDisplayKeys(
    groups: groups,
    ungroupedIndex: ungroupedIndex,
  );
  for (final displayKey in displayKeys) {
    if (displayKey == providerUngroupedGroupKey) {
      for (final key in mergedOrder) {
        if (groupIdFor(key) == null) result.add(key);
      }
      continue;
    }
    for (final key in mergedOrder) {
      if (groupIdFor(key) == displayKey) result.add(key);
    }
  }

  return List<String>.unmodifiable(result);
}

ProviderGroupingMoveResult moveProviderInGroupedOrder({
  required List<String> providersOrder,
  required Map<String, String> providerGroupMap,
  required Set<String> knownProviderKeys,
  required Set<String> validGroupIds,
  required String providerKey,
  required String? targetGroupId,
  required int targetPos,
}) {
  if (!knownProviderKeys.contains(providerKey)) {
    return ProviderGroupingMoveResult(
      providersOrder: List<String>.unmodifiable(providersOrder),
      providerGroupMap: Map<String, String>.unmodifiable(providerGroupMap),
    );
  }

  final normalizedTargetGroupId =
      (targetGroupId != null && validGroupIds.contains(targetGroupId))
      ? targetGroupId
      : null;

  // Clean mapping first (best-effort) and apply providerKey update.
  final nextMap = <String, String>{};
  for (final entry in providerGroupMap.entries) {
    final k = entry.key;
    final gid = entry.value;
    if (!knownProviderKeys.contains(k)) continue;
    if (!validGroupIds.contains(gid)) continue;
    nextMap[k] = gid;
  }
  if (normalizedTargetGroupId == null) {
    nextMap.remove(providerKey);
  } else {
    nextMap[providerKey] = normalizedTargetGroupId;
  }

  // Normalize order: keep known keys, dedupe, and remove the moved key.
  final nextOrder = <String>[];
  final seen = <String>{};
  for (final k in providersOrder) {
    if (!knownProviderKeys.contains(k)) continue;
    if (!seen.add(k)) continue;
    if (k == providerKey) continue;
    nextOrder.add(k);
  }

  String? groupIdFor(String key) {
    final gid = nextMap[key];
    return (gid != null && validGroupIds.contains(gid)) ? gid : null;
  }

  final targetKeys = [
    for (final k in nextOrder)
      if (groupIdFor(k) == normalizedTargetGroupId) k,
  ];
  final clampedPos = targetPos.clamp(0, targetKeys.length);

  int insertIndex;
  if (targetKeys.isEmpty) {
    insertIndex = nextOrder.length;
  } else if (clampedPos <= 0) {
    insertIndex = nextOrder.indexOf(targetKeys.first);
  } else if (clampedPos >= targetKeys.length) {
    insertIndex = nextOrder.indexOf(targetKeys.last) + 1;
  } else {
    insertIndex = nextOrder.indexOf(targetKeys[clampedPos]);
  }
  insertIndex = insertIndex.clamp(0, nextOrder.length);
  nextOrder.insert(insertIndex, providerKey);

  return ProviderGroupingMoveResult(
    providersOrder: List<String>.unmodifiable(nextOrder),
    providerGroupMap: Map<String, String>.unmodifiable(nextMap),
  );
}

class ProviderGroupingDeleteGroupResult {
  const ProviderGroupingDeleteGroupResult({
    required this.groups,
    required this.ungroupedIndex,
    required this.providerGroupMap,
    required this.collapsed,
  });

  final List<ProviderGroup> groups;
  final int ungroupedIndex;
  final Map<String, String> providerGroupMap;
  final Map<String, bool> collapsed;
}

ProviderGroupingDeleteGroupResult deleteProviderGroup({
  required List<ProviderGroup> groups,
  required int ungroupedIndex,
  required Map<String, String> providerGroupMap,
  required Map<String, bool> collapsed,
  required String groupId,
}) {
  final removedGroupIndex = groups.indexWhere((g) => g.id == groupId);
  final nextGroups = [
    for (final g in groups)
      if (g.id != groupId) g,
  ];
  final normalizedUngroupedIndex = ungroupedIndex.clamp(0, groups.length);
  final nextUngroupedIndex =
      removedGroupIndex >= 0 && removedGroupIndex < normalizedUngroupedIndex
      ? normalizedUngroupedIndex - 1
      : normalizedUngroupedIndex;
  final nextMap = Map<String, String>.from(providerGroupMap)
    ..removeWhere((_, gid) => gid == groupId);
  final nextCollapsed = Map<String, bool>.from(collapsed)..remove(groupId);
  return ProviderGroupingDeleteGroupResult(
    groups: List<ProviderGroup>.unmodifiable(nextGroups),
    ungroupedIndex: nextUngroupedIndex.clamp(0, nextGroups.length),
    providerGroupMap: Map<String, String>.unmodifiable(nextMap),
    collapsed: Map<String, bool>.unmodifiable(nextCollapsed),
  );
}
