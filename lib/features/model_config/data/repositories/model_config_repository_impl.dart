import 'dart:convert';
import 'package:zero_type/core/security/secure_vault.dart';
import 'package:zero_type/core/security/endpoint_policy.dart';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zero_type/core/constants/app_constants.dart';
import 'package:zero_type/features/model_config/domain/entities/ai_provider.dart';
import 'package:zero_type/features/model_config/domain/repositories/model_config_repository.dart';

class ModelConfigRepositoryImpl implements ModelConfigRepository {
  ModelConfigRepositoryImpl({
    required SharedPreferences prefs,
    required SecureVault vault,
  }) : _prefs = prefs,
       _vault = vault;

  final SharedPreferences _prefs;
  final SecureVault _vault;

  @override
  Future<ProvidersConfig> loadProvidersConfig() async {
    final jsonString = await rootBundle.loadString(
      'assets/config/providers.json',
    );
    final json = jsonDecode(jsonString) as Map<String, dynamic>;

    AiProvider parseProvider(Map<String, dynamic> p) => AiProvider(
      id: p['id'] as String,
      name: p['name'] as String,
      models: (p['models'] as List)
          .map((m) => AiModel(id: m['id'] as String, name: m['name'] as String))
          .toList(),
    );

    return ProvidersConfig(
      speechRecognition: (json['speechRecognition'] as List)
          .map((p) => parseProvider(p as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Future<String?> getSelectedSpeechProviderId() async =>
      _prefs.getString(AppConstants.selectedSpeechProviderKey);

  @override
  Future<void> saveSelectedSpeechProviderId(String providerId) async =>
      _prefs.setString(AppConstants.selectedSpeechProviderKey, providerId);

  @override
  Future<String?> getSelectedSpeechModelId(String providerId) async =>
      _prefs.getString('${AppConstants.selectedSpeechModelKey}_$providerId');

  @override
  Future<void> saveSelectedSpeechModelId(
    String providerId,
    String modelId,
  ) async => _prefs.setString(
    '${AppConstants.selectedSpeechModelKey}_$providerId',
    modelId,
  );

  @override
  Future<String?> getSpeechApiKey(String providerId) async =>
      _vault.readApiKey(providerId);

  @override
  Future<void> saveSpeechApiKey(String providerId, String apiKey) async =>
      _vault.writeApiKey(providerId, apiKey);

  @override
  Future<String?> getCustomEndpoint(String providerId) async =>
      _prefs.getString('custom_endpoint_$providerId');

  @override
  Future<void> saveCustomEndpoint(String providerId, String endpoint) async =>
      _prefs.setString(
        'custom_endpoint_$providerId',
        EndpointPolicy.validate(endpoint),
      );
}
