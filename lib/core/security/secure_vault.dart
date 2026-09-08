import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';

/// Keys never fall back to ordinary preferences if the OS vault is unavailable.
class SecureVault {
  SecureVault({
    required FlutterSecureStorage storage,
    required SharedPreferences preferences,
  }) : _storage = storage,
       _preferences = preferences;
  final FlutterSecureStorage _storage;
  final SharedPreferences _preferences;
  final Lock _lock = Lock();
  final AesGcm _cipher = AesGcm.with256bits();
  SecretKey? _historyKey;

  Future<void> migrateApiKeys() async {
    for (final String key
        in _preferences
            .getKeys()
            .where((String key) => key.startsWith('api_key_speech_'))
            .toList()) {
      await readApiKey(key.substring('api_key_speech_'.length));
    }
  }

  Future<String?> readApiKey(String provider) => _lock.synchronized(() async {
    final String key = 'api_key_speech_$provider';
    final String? secureValue = await _storage.read(key: key);
    final String? legacyValue = _preferences.getString(key);
    if (legacyValue == null) return secureValue;
    final String value = secureValue ?? legacyValue;
    await _writeVerified(key, value);
    if (!await _preferences.remove(key))
      throw StateError('Could not remove legacy API key.');
    return value;
  });

  Future<void> writeApiKey(String provider, String value) =>
      _lock.synchronized(() async {
        final String key = 'api_key_speech_$provider';
        await _writeVerified(key, value);
        if (!await _preferences.remove(key))
          throw StateError('Could not remove legacy API key.');
      });

  Future<void> _writeVerified(String key, String value) async {
    await _storage.write(key: key, value: value);
    if (await _storage.read(key: key) != value)
      throw StateError('Secure storage verification failed.');
  }

  Future<SecretKey> _getHistoryKey({
    bool allowCreate = true,
  }) => _lock.synchronized(() async {
    if (_historyKey != null) return _historyKey!;
    const String keyName = 'history_aes_gcm_v1';
    String? encoded = await _storage.read(key: keyName);
    if (encoded == null) {
      if (!allowCreate) throw StateError('History encryption key is missing.');
      final SecretKey key = await _cipher.newSecretKey();
      encoded = base64Encode(await key.extractBytes());
      await _writeVerified(keyName, encoded);
    }
    final List<int> bytes = base64Decode(encoded);
    if (bytes.length != 32) throw StateError('Invalid history encryption key.');
    return _historyKey = SecretKey(bytes);
  });

  Future<List<int>> encrypt(List<int> bytes) async {
    final SecretBox box = await _cipher.encrypt(
      bytes,
      secretKey: await _getHistoryKey(),
    );
    return utf8.encode(
      jsonEncode({
        'version': 1,
        'nonce': base64Encode(box.nonce),
        'ciphertext': base64Encode(box.cipherText),
        'mac': base64Encode(box.mac.bytes),
      }),
    );
  }

  Future<List<int>> decrypt(List<int> bytes) async {
    final Map<String, dynamic> data =
        jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (data['version'] != 1)
      throw const FormatException('Unsupported encrypted history version.');
    final SecretBox box = SecretBox(
      base64Decode(data['ciphertext'] as String),
      nonce: base64Decode(data['nonce'] as String),
      mac: Mac(base64Decode(data['mac'] as String)),
    );
    return _cipher.decrypt(
      box,
      secretKey: await _getHistoryKey(allowCreate: false),
    );
  }
}
