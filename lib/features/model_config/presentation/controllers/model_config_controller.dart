import 'package:zero_type/core/security/secure_vault.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:zero_type/core/di/injection.dart';
import 'package:zero_type/features/model_config/data/repositories/model_config_repository_impl.dart';
import 'package:zero_type/features/model_config/domain/entities/ai_provider.dart';
import 'package:zero_type/features/model_config/domain/repositories/model_config_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'model_config_controller.g.dart';

ModelConfigRepository _buildRepository() => ModelConfigRepositoryImpl(
      prefs: getIt<SharedPreferences>(),
      vault: getIt<SecureVault>(),
    );

@riverpod
Future<ProvidersConfig> providersConfig(Ref ref) async {
  final repo = _buildRepository();
  return repo.loadProvidersConfig();
}

@riverpod
class SpeechProviderController extends _$SpeechProviderController {
  ModelConfigRepository get _repo => _buildRepository();

  @override
  Future<({String? providerId, String? modelId, String? apiKey, String? customEndpoint})>
      build() async {
    var providerId = await _repo.getSelectedSpeechProviderId();

    // Auto-select the first provider on first launch so saveApiKey/selectModel work correctly
    if (providerId == null) {
      final config = await _repo.loadProvidersConfig();
      if (config.speechRecognition.isNotEmpty) {
        providerId = config.speechRecognition.first.id;
        await _repo.saveSelectedSpeechProviderId(providerId);
      }
    }

    return (
      providerId: providerId,
      modelId: await _repo.getSelectedSpeechModelId(providerId ?? ''),
      apiKey: await _repo.getSpeechApiKey(providerId ?? ''),
      customEndpoint: await _repo.getCustomEndpoint(providerId ?? ''),
    );
  }

  Future<void> selectProvider(String providerId) async {
    await _repo.saveSelectedSpeechProviderId(providerId);
    ref.invalidateSelf();
  }

  Future<void> selectModel(String modelId) async {
    final state = await future;
    if (state.providerId != null) {
      await _repo.saveSelectedSpeechModelId(state.providerId!, modelId);
      ref.invalidateSelf();
    }
  }

  Future<void> saveApiKey(String apiKey) async {
    final state = await future;
    if (state.providerId != null) {
      await _repo.saveSpeechApiKey(state.providerId!, apiKey);
      ref.invalidateSelf();
    }
  }

  Future<void> saveCustomEndpoint(String endpoint) async {
    final state = await future;
    if (state.providerId != null) {
      await _repo.saveCustomEndpoint(state.providerId!, endpoint);
      ref.invalidateSelf();
    }
  }
}

