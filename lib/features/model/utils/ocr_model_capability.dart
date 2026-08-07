import '../../../core/models/assistant.dart';
import '../../../core/providers/model_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/model_override_resolver.dart';

bool modelSupportsOcrImageInput(
  SettingsProvider settings,
  String providerKey,
  String modelId,
) {
  final cfg = settings.getProviderConfig(providerKey);
  final rawOverride = cfg.modelOverrides[modelId];
  final override = rawOverride is Map
      ? {for (final e in rawOverride.entries) e.key.toString(): e.value}
      : null;

  var baseId = modelId;
  final rawApiModelId = (override?['apiModelId'] ?? override?['api_model_id'])
      ?.toString()
      .trim();
  if (rawApiModelId != null && rawApiModelId.isNotEmpty) {
    baseId = rawApiModelId;
  }

  var info = ModelRegistry.infer(ModelInfo(id: baseId, displayName: baseId));
  if (override != null) {
    info = ModelOverrideResolver.applyModelOverride(info, override);
  }
  return info.input.contains(Modality.image);
}

bool hasConfiguredOcrModel(SettingsProvider settings) {
  return settings.ocrModelProvider != null && settings.ocrModelId != null;
}

bool resolveOcrActive(
  SettingsProvider settings, {
  required Assistant? assistant,
  required String providerKey,
  required String modelId,
}) {
  if (!hasConfiguredOcrModel(settings)) return false;
  final mode = assistant?.ocrMode ?? Assistant.ocrModeAuto;
  if (mode == Assistant.ocrModeNever) return false;
  if (mode == Assistant.ocrModeAlways) return true;
  return !modelSupportsOcrImageInput(settings, providerKey, modelId);
}
