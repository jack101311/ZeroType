import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../security/secure_vault.dart';
import '../services/recording_service.dart';
import 'package:get_it/get_it.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/sound_service.dart';
import '../services/speech_recognition_service.dart';
import '../services/hotkey_service.dart';
import '../services/tray_service.dart';
import '../../features/history/domain/repositories/history_repository.dart';
import '../../features/history/data/repositories/history_repository_impl.dart';

final GetIt getIt = GetIt.instance;

Future<void> configureDependencies() async {
  final sharedPreferences = await SharedPreferences.getInstance();
  getIt.registerSingleton<SharedPreferences>(sharedPreferences);

  final SecureVault vault = SecureVault(
    storage: const FlutterSecureStorage(),
    preferences: sharedPreferences,
  );
  getIt.registerSingleton<SecureVault>(vault);
  getIt.registerSingleton<RecordingService>(RecordingService());
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(minutes: 2),
      receiveTimeout: const Duration(minutes: 3),
      followRedirects: false,
    ),
  );
  getIt.registerSingleton<Dio>(dio);
  getIt.registerSingleton<SpeechRecognitionService>(
    SpeechRecognitionService(dio: dio),
  );
  getIt.registerSingleton<HotkeyService>(
    HotkeyService(prefs: sharedPreferences),
  );
  getIt.registerSingleton<TrayService>(TrayService());
  getIt.registerSingleton<SoundService>(SoundService(prefs: sharedPreferences));
  getIt.registerSingleton<HistoryRepository>(
    HistoryRepositoryImpl(vault: vault),
  );
}
