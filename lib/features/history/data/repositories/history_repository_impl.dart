import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:synchronized/synchronized.dart';
import 'package:zero_type/core/security/private_files.dart';
import 'package:zero_type/core/security/secure_vault.dart';
import '../../domain/entities/history_stats.dart';
import '../../domain/entities/transcription_record.dart';
import '../../domain/repositories/history_repository.dart';

class HistoryRepositoryImpl implements HistoryRepository {
  HistoryRepositoryImpl({
    required SecureVault vault,
    Future<Directory> Function()? directory,
  }) : _vault = vault,
       _directory = directory ?? getApplicationSupportDirectory;
  final SecureVault _vault;
  final Future<Directory> Function() _directory;
  final Lock _lock = Lock();

  Future<File> _file(String name) async {
    final Directory directory = await _directory();
    await directory.create(recursive: true);
    return File(p.join(directory.path, name));
  }

  Future<Directory> _audioDir() async {
    final Directory directory = Directory(
      p.join((await _directory()).path, 'history_audio'),
    );
    if (await FileSystemEntity.type(directory.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const FileSystemException('Refusing linked history directory');
    }
    await directory.create(recursive: true);
    return directory;
  }

  /// Treat legacy JSON paths as untrusted, including links and non-audio files.
  Future<File?> _safeAudio(String? path) async {
    if (path == null) return null;
    final Directory directory = await _audioDir();
    final String normalized = p.normalize(p.absolute(path));
    if (p.dirname(normalized) != p.normalize(p.absolute(directory.path)) ||
        !RegExp(
          r'^zerotype_\d+\.m4a(?:\.ztenc)?$',
        ).hasMatch(p.basename(normalized)))
      return null;
    if (await FileSystemEntity.type(normalized, followLinks: false) !=
        FileSystemEntityType.file)
      return null;
    return File(normalized);
  }

  Future<void> _saveRecords(List<TranscriptionRecord> records) async {
    final List<int> bytes = utf8.encode(
      jsonEncode(
        records.map((TranscriptionRecord record) => record.toJson()).toList(),
      ),
    );
    await PrivateFiles.writeAtomically(
      await _file('history.ztenc'),
      await _vault.encrypt(bytes),
    );
  }

  Future<List<TranscriptionRecord>> _readRecords() async {
    final File encrypted = await _file('history.ztenc');
    final File legacy = await _file('history.json');
    if (await encrypted.exists()) {
      final List<TranscriptionRecord> records = _decode(
        await _vault.decrypt(await encrypted.readAsBytes()),
      );
      // Recover an interrupted migration only after authenticating the new index.
      if (await legacy.exists()) await _removeLegacyFiles(legacy);
      return records;
    }
    if (!await legacy.exists()) return [];
    final List<TranscriptionRecord> records = _decode(
      await legacy.readAsBytes(),
    );
    final List<TranscriptionRecord> migrated = [];
    for (final TranscriptionRecord record in records) {
      final Map<String, dynamic> json = record.toJson();
      final File? audio = await _safeAudio(record.audioPath);
      json['audioPath'] = audio == null ? null : await _encryptAudio(audio);
      migrated.add(TranscriptionRecord.fromJson(json));
    }
    await _saveRecords(migrated);
    await _removeLegacyFiles(legacy);
    return migrated;
  }

  List<TranscriptionRecord> _decode(List<int> bytes) {
    final List<dynamic> values =
        jsonDecode(utf8.decode(bytes)) as List<dynamic>;
    final List<TranscriptionRecord> records = values
        .map(
          (dynamic value) =>
              TranscriptionRecord.fromJson(value as Map<String, dynamic>),
        )
        .toList();
    records.sort(
      (TranscriptionRecord a, TranscriptionRecord b) =>
          b.createdAt.compareTo(a.createdAt),
    );
    return records;
  }

  Future<void> _removeLegacyFiles(File legacy) async {
    for (final TranscriptionRecord record in _decode(
      await legacy.readAsBytes(),
    )) {
      final File? audio = await _safeAudio(record.audioPath);
      if (audio != null && !audio.path.endsWith('.ztenc')) await audio.delete();
    }
    await legacy.delete();
  }

  Future<String> _encryptAudio(File source) async {
    if (source.path.endsWith('.ztenc')) return source.path;
    final File target = File(
      p.join((await _audioDir()).path, '${p.basename(source.path)}.ztenc'),
    );
    await PrivateFiles.writeAtomically(
      target,
      await _vault.encrypt(await source.readAsBytes()),
    );
    return target.path;
  }

  @override
  Future<List<TranscriptionRecord>> getRecords() =>
      _lock.synchronized(_readRecords);

  @override
  Future<void> addRecord(TranscriptionRecord record) =>
      _lock.synchronized(() async {
        final List<TranscriptionRecord> records = await _readRecords();
        records.insert(0, record);
        await _saveRecords(records);
      });

  @override
  Future<void> deleteRecord(String id) => _lock.synchronized(() async {
    final List<TranscriptionRecord> records = await _readRecords();
    for (final TranscriptionRecord record in records.where(
      (TranscriptionRecord record) => record.id == id,
    )) {
      await _deleteAudio(record.audioPath);
    }
    records.removeWhere((TranscriptionRecord record) => record.id == id);
    await _saveRecords(records);
  });

  Future<void> _deleteAudio(String? path) async {
    final File? file = await _safeAudio(path);
    if (file != null) await file.delete();
  }

  @override
  Future<void> clearAll() => _lock.synchronized(() async {
    // Deletion must work even if the encryption key is lost or the index is corrupt.
    for (final String name in [
      'history.ztenc',
      'history.ztenc.tmp',
      'history.json',
      'history_stats.json',
    ]) {
      final File file = await _file(name);
      if (await file.exists()) await file.delete();
    }
    await for (final FileSystemEntity entry in (await _audioDir()).list(
      followLinks: false,
    )) {
      if (entry is File || entry is Link) await entry.delete();
    }
  });

  @override
  Future<void> purgeExpiredRecords(
    int retentionDays,
  ) => _lock.synchronized(() async {
    if (retentionDays < 1 || retentionDays > 365)
      throw ArgumentError.value(retentionDays);
    final DateTime cutoff = DateTime.now().subtract(
      Duration(days: retentionDays),
    );
    final List<TranscriptionRecord> records = await _readRecords();
    for (final TranscriptionRecord record in records.where(
      (TranscriptionRecord record) => record.createdAt.isBefore(cutoff),
    )) {
      await _deleteAudio(record.audioPath);
    }
    records.removeWhere(
      (TranscriptionRecord record) => record.createdAt.isBefore(cutoff),
    );
    await _saveRecords(records);
    final Set<String> referenced = records
        .map((TranscriptionRecord record) => record.audioPath)
        .whereType<String>()
        .toSet();
    await for (final FileSystemEntity entry in (await _audioDir()).list(
      followLinks: false,
    )) {
      // Do not race an in-flight transcription that has not committed its index yet.
      if (entry is File &&
          !referenced.contains(entry.path) &&
          (await entry.stat()).modified.isBefore(
            DateTime.now().subtract(const Duration(days: 1)),
          )) {
        await entry.delete();
      }
    }
  });

  @override
  Future<String?> moveAudioFile(String srcPath) => _lock.synchronized(() async {
    final File source = File(srcPath);
    if (!RegExp(r'^zerotype_\d+\.m4a$').hasMatch(p.basename(srcPath)))
      throw const FormatException('Invalid recording filename');
    if (!await source.exists()) return null;
    final String destination = await _encryptAudio(source);
    await source.delete();
    return destination;
  });

  @override
  Future<List<int>> readAudio(String path) => _lock.synchronized(() async {
    final File? file = await _safeAudio(path);
    if (file == null || !path.endsWith('.ztenc'))
      throw const FileSystemException('Invalid encrypted recording');
    return _vault.decrypt(await file.readAsBytes());
  });

  @override
  Future<void> discardAudio(String path) =>
      _lock.synchronized(() => _deleteAudio(path));

  Future<HistoryStats> _readStats() async {
    final File file = await _file('history_stats.json');
    if (!await file.exists()) return HistoryStats.zero;
    return HistoryStats.fromJson(
      jsonDecode(await file.readAsString()) as Map<String, dynamic>,
    );
  }

  @override
  Future<HistoryStats> getStats() => _lock.synchronized(_readStats);

  @override
  Future<void> accumulateStats(TranscriptionRecord record) =>
      _lock.synchronized(() async {
        final HistoryStats updated = (await _readStats()).addRecord(
          record.costUsd,
        );
        await PrivateFiles.writeAtomically(
          await _file('history_stats.json'),
          utf8.encode(jsonEncode(updated.toJson())),
        );
      });

  @override
  Future<void> resetStats() => _lock.synchronized(() async {
    final File file = await _file('history_stats.json');
    if (await file.exists()) await file.delete();
  });
}
