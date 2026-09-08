import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zero_type/core/controllers/zero_type_controller.dart';
import 'package:zero_type/core/di/injection.dart';
import 'package:zero_type/core/services/recording_service.dart';
import 'package:zero_type/core/services/sound_service.dart';
import 'package:zero_type/core/services/speech_recognition_service.dart';
import 'package:zero_type/core/state/zero_type_state.dart';
import 'package:zero_type/features/history/domain/repositories/history_repository.dart';
import 'package:zero_type/features/history/domain/entities/transcription_record.dart';
import 'package:zero_type/features/dictionary/domain/repositories/dictionary_repository.dart';
import 'package:zero_type/features/dictionary/presentation/controllers/dictionary_controller.dart';
import 'package:zero_type/features/model_config/presentation/controllers/model_config_controller.dart';
import 'package:zero_type/features/prompt/presentation/controllers/prompt_controller.dart';

class MockRecording extends Mock implements RecordingService {}

class MockSound extends Mock implements SoundService {}

class MockSpeech extends Mock implements SpeechRecognitionService {}

class MockHistory extends Mock implements HistoryRepository {}

class MockDictionary extends Mock implements DictionaryRepository {}

class TestConfig extends SpeechProviderController {
  @override
  Future<
    ({
      String? providerId,
      String? modelId,
      String? apiKey,
      String? customEndpoint,
    })
  >
  build() async => (
    providerId: 'openai',
    modelId: 'test',
    apiKey: 'test-key',
    customEndpoint: null,
  );
}

class TestPrompt extends SpeechPromptController {
  @override
  Future<String> build() async => 'test';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    registerFallbackValue(
      TranscriptionRecord(
        id: 'fallback',
        text: '',
        createdAt: DateTime(2026),
        provider: '',
        model: '',
      ),
    );
  });
  late MockRecording recording;
  late MockSound sound;
  late MockSpeech speech;
  late MockHistory history;
  late ProviderContainer container;
  late int pastes;
  late int clipboardWrites;
  late Completer<TranscriptionResult> response;
  late Completer<void> requested;
  CancelToken? requestToken;
  setUp(() async {
    await getIt.reset();
    recording = MockRecording();
    sound = MockSound();
    speech = MockSpeech();
    history = MockHistory();
    final MockDictionary dictionary = MockDictionary();
    when(() => dictionary.buildDictionaryPrompt()).thenAnswer((_) async => '');
    when(() => recording.requestPermission()).thenAnswer((_) async => true);
    when(
      () => recording.startRecording(onAmplitude: any(named: 'onAmplitude')),
    ).thenAnswer((_) async {});
    when(
      () => recording.stopRecording(),
    ).thenAnswer((_) async => '/tmp/test-recording.m4a');
    when(() => recording.deleteFile(any())).thenAnswer((_) async {});
    when(() => recording.cancelRecording()).thenAnswer((_) async {});
    when(() => recording.dispose()).thenAnswer((_) async {});
    when(() => sound.pauseMusic()).thenAnswer((_) async {});
    when(() => sound.resumeMusic()).thenAnswer((_) async {});
    when(() => sound.playStartSound()).thenAnswer((_) async {});
    when(() => sound.playStopSound()).thenAnswer((_) async {});
    when(() => sound.playCancelSound()).thenAnswer((_) async {});
    response = Completer<TranscriptionResult>();
    requested = Completer<void>();
    when(
      () => speech.transcribe(
        audioFilePath: any(named: 'audioFilePath'),
        apiKey: any(named: 'apiKey'),
        provider: any(named: 'provider'),
        model: any(named: 'model'),
        prompt: any(named: 'prompt'),
        customEndpoint: any(named: 'customEndpoint'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((Invocation invocation) {
      requestToken = invocation.namedArguments[#cancelToken] as CancelToken?;
      requested.complete();
      return response.future;
    });
    SharedPreferences.setMockInitialValues({});
    getIt.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
    getIt.registerSingleton<RecordingService>(recording);
    getIt.registerSingleton<SoundService>(sound);
    getIt.registerSingleton<SpeechRecognitionService>(speech);
    getIt.registerSingleton<HistoryRepository>(history);
    container = ProviderContainer(
      overrides: [
        speechProviderControllerProvider.overrideWith(TestConfig.new),
        speechPromptControllerProvider.overrideWith(TestPrompt.new),
        dictionaryRepositoryProvider.overrideWithValue(dictionary),
      ],
    );
    pastes = 0;
    clipboardWrites = 0;
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.zerotype.app/permission'),
      (_) async => true,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.zerotype.app/overlay'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.zerotype.app/keyboard'),
      (_) async {
        pastes++;
        return null;
      },
    );
    messenger.setMockMethodCallHandler(SystemChannels.platform, (
      MethodCall call,
    ) async {
      if (call.method == 'Clipboard.setData') clipboardWrites++;
      return null;
    });
  });
  tearDown(() async {
    container.dispose();
    await getIt.reset();
  });
  test(
    'Cancel during API request aborts transport and ignores a late successful response',
    () async {
      final ZeroTypeController controller = container.read(
        zeroTypeControllerProvider.notifier,
      );
      await controller.toggleRecording();
      final Future<void> processing = controller.toggleRecording();
      await requested.future;
      await controller.cancel();
      expect(requestToken!.isCancelled, isTrue);
      await controller
          .toggleRecording(); // Cannot start another recording while cleanup is pending.
      response.complete((
        text: 'secret transcript',
        inputTokens: null,
        outputTokens: null,
      ));
      await processing;
      expect(pastes, 0);
      expect(clipboardWrites, 0);
      verifyNever(() => history.moveAudioFile(any()));
      verify(() => recording.deleteFile('/tmp/test-recording.m4a')).called(1);
      verify(
        () => recording.startRecording(onAmplitude: any(named: 'onAmplitude')),
      ).called(1);
      expect(
        container.read(zeroTypeControllerProvider).status,
        ZeroTypeStatus.idle,
      );
    },
  );
  test('API failure removes the temporary recording', () async {
    final ZeroTypeController controller = container.read(
      zeroTypeControllerProvider.notifier,
    );
    await controller.toggleRecording();
    final Future<void> processing = controller.toggleRecording();
    await requested.future;
    response.completeError(StateError('provider failed'));
    await processing;
    verify(() => recording.deleteFile('/tmp/test-recording.m4a')).called(1);
    expect(pastes, 0);
    expect(clipboardWrites, 0);
  });
  test(
    'Cancel while saving rolls back history and encrypted audio without pasting',
    () async {
      final Completer<void> saving = Completer<void>();
      final Completer<void> finishSaving = Completer<void>();
      when(
        () => history.moveAudioFile(any()),
      ).thenAnswer((_) async => '/history/record.ztenc');
      when(() => history.addRecord(any())).thenAnswer((_) {
        saving.complete();
        return finishSaving.future;
      });
      when(() => history.deleteRecord(any())).thenAnswer((_) async {});
      when(() => history.discardAudio(any())).thenAnswer((_) async {});
      final ZeroTypeController controller = container.read(
        zeroTypeControllerProvider.notifier,
      );
      await controller.toggleRecording();
      final Future<void> processing = controller.toggleRecording();
      await requested.future;
      response.complete((
        text: 'secret',
        inputTokens: null,
        outputTokens: null,
      ));
      await saving.future;
      await controller.cancel();
      finishSaving.complete();
      await processing;
      verify(() => history.deleteRecord(any())).called(1);
      verify(() => history.discardAudio('/history/record.ztenc')).called(1);
      expect(pastes, 0);
      expect(clipboardWrites, 0);
    },
  );
}
