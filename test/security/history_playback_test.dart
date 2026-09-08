import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zero_type/core/services/history_playback_service.dart';
import 'package:zero_type/features/history/domain/entities/transcription_record.dart';
import 'package:zero_type/features/history/domain/repositories/history_repository.dart';

class MockAudioPlayer extends Mock implements AudioPlayer {}

class MockPlaybackRepository extends Mock implements HistoryRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => registerFallbackValue(DeviceFileSource('/unused')));
  late MockAudioPlayer player;
  late MockPlaybackRepository repository;
  late HistoryPlaybackService service;
  late Directory root;
  late StreamController<void> completion;
  late List<String?> states;
  final TranscriptionRecord record = TranscriptionRecord(
    id: '1',
    text: 'test',
    createdAt: DateTime(2026),
    provider: 'test',
    model: 'test',
    audioPath: '/history/zerotype_1.m4a.ztenc',
  );
  setUp(() async {
    player = MockAudioPlayer();
    repository = MockPlaybackRepository();
    states = [];
    completion = StreamController<void>.broadcast();
    root = await Directory.systemTemp.createTemp('zerotype_playback_test_');
    when(() => player.onPlayerComplete).thenAnswer((_) => completion.stream);
    when(() => player.release()).thenAnswer((_) async {});
    when(() => player.dispose()).thenAnswer((_) async {});
    when(() => player.play(any())).thenAnswer((_) async {});
    when(() => repository.readAudio(any())).thenAnswer((_) async => [1, 2, 3]);
    service = HistoryPlaybackService(
      repository: repository,
      player: player,
      onChanged: states.add,
      createDirectory: () => root.createTemp('private_'),
    );
  });
  tearDown(() async {
    await service.dispose();
    await completion.close();
    await root.delete(recursive: true);
  });
  test(
    'Only decrypted bytes reach a native local-file source and stop releases/deletes them',
    () async {
      await service.toggle(record);
      final Source source =
          verify(() => player.play(captureAny())).captured.single as Source;
      expect(source, isA<DeviceFileSource>());
      final File file = File((source as DeviceFileSource).path);
      expect(await file.readAsBytes(), [1, 2, 3]);
      await service.stop();
      expect(await file.exists(), isFalse);
      expect(states.last, isNull);
      verify(() => player.release()).called(2);
    },
  );
  test(
    'Disposal while decrypting cannot create a late plaintext file or start playback',
    () async {
      final Completer<List<int>> decoded = Completer<List<int>>();
      final Completer<void> reading = Completer<void>();
      when(() => repository.readAudio(any())).thenAnswer((_) {
        reading.complete();
        return decoded.future;
      });
      final Future<void> playing = service.toggle(record);
      await reading.future;
      final Future<void> disposing = service.dispose();
      decoded.complete([1, 2, 3]);
      await Future.wait([playing, disposing]);
      expect(await root.list().toList(), isEmpty);
      verifyNever(() => player.play(any()));
    },
  );
  test('Playback failures remove decrypted temporary files', () async {
    when(() => player.play(any())).thenThrow(StateError('device unavailable'));
    await service.toggle(record);
    expect(await root.list().toList(), isEmpty);
    expect(states.last, isNull);
  });
}
