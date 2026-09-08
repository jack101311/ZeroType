import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zero_type/core/security/secure_vault.dart';
import 'package:zero_type/features/history/data/repositories/history_repository_impl.dart';
import 'package:zero_type/features/history/domain/entities/transcription_record.dart';
import 'secure_vault_test.dart' show MemoryStorage;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late HistoryRepositoryImpl repository;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('zerotype_history_test_');
    SharedPreferences.setMockInitialValues({});
    final SecureVault vault = SecureVault(
      storage: MemoryStorage(),
      preferences: await SharedPreferences.getInstance(),
    );
    repository = HistoryRepositoryImpl(
      vault: vault,
      directory: () async => directory,
    );
  });
  tearDown(() => directory.delete(recursive: true));
  TranscriptionRecord record(String id, {String? audioPath, DateTime? date}) =>
      TranscriptionRecord(
        id: id,
        text: 'private text',
        createdAt: date ?? DateTime.now(),
        audioPath: audioPath,
        provider: 'openai',
        model: 'test',
      );
  test('Migrates legacy text and audio without retaining plaintext', () async {
    final Directory audioDirectory = await Directory(
      '${directory.path}/history_audio',
    ).create();
    final File source = await File(
      '${audioDirectory.path}/zerotype_123.m4a',
    ).writeAsBytes([1, 2, 3]);
    final File legacy = await File(
      '${directory.path}/history.json',
    ).writeAsString(jsonEncode([record('1', audioPath: source.path).toJson()]));
    final List<TranscriptionRecord> actual = await repository.getRecords();
    expect(actual.single.text, 'private text');
    expect(await source.exists(), isFalse);
    expect(await legacy.exists(), isFalse);
    expect(await repository.readAudio(actual.single.audioPath!), [1, 2, 3]);
    expect(
      await File('${directory.path}/history.ztenc').readAsString(),
      isNot(contains('private text')),
    );
  });
  test(
    'Malicious legacy paths cannot read or delete unrelated files',
    () async {
      final File outside = await File(
        '${directory.path}/important.txt',
      ).writeAsString('keep me');
      await File('${directory.path}/history.json').writeAsString(
        jsonEncode([record('1', audioPath: outside.path).toJson()]),
      );
      expect((await repository.getRecords()).single.audioPath, isNull);
      await repository.deleteRecord('1');
      expect(await outside.readAsString(), 'keep me');
      await expectLater(
        repository.readAudio(outside.path),
        throwsA(isA<FileSystemException>()),
      );
    },
  );
  test('Symlink audio cannot expose files outside history', () async {
    if (Platform.isWindows) return;
    final Directory audioDirectory = await Directory(
      '${directory.path}/history_audio',
    ).create();
    final File outside = await File(
      '${directory.path}/private.txt',
    ).writeAsString('secret');
    final Link link = await Link(
      '${audioDirectory.path}/zerotype_123.m4a.ztenc',
    ).create(outside.path);
    await expectLater(
      repository.readAudio(link.path),
      throwsA(isA<FileSystemException>()),
    );
    await repository.discardAudio(link.path);
    expect(await outside.exists(), isTrue);
  });
  test('Concurrent writes preserve both records', () async {
    await Future.wait([
      repository.addRecord(record('1')),
      repository.addRecord(record('2')),
    ]);
    expect(
      (await repository.getRecords()).map((TranscriptionRecord r) => r.id),
      containsAll(['1', '2']),
    );
  });
  test(
    'Retention deletes expired encrypted audio and preserves current records',
    () async {
      final File source = await File(
        '${directory.path}/zerotype_456.m4a',
      ).writeAsBytes([4, 5, 6]);
      final String? path = await repository.moveAudioFile(source.path);
      await repository.addRecord(
        record(
          'old',
          audioPath: path,
          date: DateTime.now().subtract(const Duration(days: 8)),
        ),
      );
      await repository.addRecord(record('new'));
      await repository.purgeExpiredRecords(7);
      expect((await repository.getRecords()).single.id, 'new');
      expect(await File(path!).exists(), isFalse);
    },
  );
  test(
    'Corrupt history fails closed but can still be explicitly cleared',
    () async {
      await repository.addRecord(record('1'));
      await File('${directory.path}/history.ztenc').writeAsString('corrupt');
      await expectLater(repository.getRecords(), throwsFormatException);
      await repository.clearAll();
      expect(await repository.getRecords(), isEmpty);
    },
  );
}
