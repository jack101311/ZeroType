import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zero_type/core/security/secure_vault.dart';

class MemoryStorage extends FlutterSecureStorage {
  final Map<String, String> values = {};
  bool failWrites = false;
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];
  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (failWrites) throw StateError('Vault locked');
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences preferences;
  late MemoryStorage storage;
  late SecureVault vault;
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'api_key_speech_openai': 'legacy-secret',
    });
    preferences = await SharedPreferences.getInstance();
    storage = MemoryStorage();
    vault = SecureVault(storage: storage, preferences: preferences);
  });
  test('Migrates plaintext key only after verified secure write', () async {
    await vault.migrateApiKeys();
    expect(storage.values['api_key_speech_openai'], 'legacy-secret');
    expect(preferences.containsKey('api_key_speech_openai'), isFalse);
  });
  test(
    'Failed vault write preserves legacy key and does not silently fall back',
    () async {
      storage.failWrites = true;
      await expectLater(vault.readApiKey('openai'), throwsStateError);
      expect(preferences.getString('api_key_speech_openai'), 'legacy-secret');
    },
  );
  test('Existing secure key wins over stale plaintext migration', () async {
    storage.values['api_key_speech_openai'] = 'new-secret';
    expect(await vault.readApiKey('openai'), 'new-secret');
    expect(preferences.containsKey('api_key_speech_openai'), isFalse);
  });
  test('New keys are never written to preferences', () async {
    await vault.writeApiKey('gemini', 'new-key');
    expect(await vault.readApiKey('gemini'), 'new-key');
    expect(preferences.containsKey('api_key_speech_gemini'), isFalse);
  });
  test(
    'History encryption uses fresh nonces and survives a vault restart',
    () async {
      final List<int> input = utf8.encode('confidential transcript');
      final List<int> first = await vault.encrypt(input);
      final List<int> second = await vault.encrypt(input);
      expect(first, isNot(second));
      expect(utf8.decode(first), isNot(contains('confidential transcript')));
      final SecureVault restarted = SecureVault(
        storage: storage,
        preferences: preferences,
      );
      expect(await restarted.decrypt(first), input);
    },
  );
  test('Modified ciphertext fails authentication', () async {
    final List<int> encrypted = await vault.encrypt([1, 2, 3]);
    final Map<String, dynamic> envelope =
        jsonDecode(utf8.decode(encrypted)) as Map<String, dynamic>;
    envelope['ciphertext'] = base64Encode([9, 9, 9]);
    await expectLater(
      vault.decrypt(utf8.encode(jsonEncode(envelope))),
      throwsA(isA<Exception>()),
    );
  });
  test(
    'A missing history key fails closed without creating a replacement',
    () async {
      final List<int> encrypted = await vault.encrypt([1, 2, 3]);
      storage.values.remove('history_aes_gcm_v1');
      final SecureVault restarted = SecureVault(
        storage: storage,
        preferences: preferences,
      );
      await expectLater(restarted.decrypt(encrypted), throwsStateError);
      expect(storage.values.containsKey('history_aes_gcm_v1'), isFalse);
    },
  );
}
