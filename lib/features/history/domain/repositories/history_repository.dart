import '../entities/history_stats.dart';
import '../entities/transcription_record.dart';

abstract class HistoryRepository {
  Future<List<TranscriptionRecord>> getRecords();
  Future<List<int>> readAudio(String path);
  Future<void> discardAudio(String path);
  Future<void> addRecord(TranscriptionRecord record);
  Future<void> deleteRecord(String id);
  Future<void> clearAll();
  Future<void> purgeExpiredRecords(int retentionDays);

  /// Moves audio from [srcPath] to persistent history dir.
  /// Returns the new absolute path, or null if src does not exist.
  Future<String?> moveAudioFile(String srcPath);

  /// Returns cumulative stats (never reduced by individual deletes).
  Future<HistoryStats> getStats();

  /// Accumulates [record]'s cost into the persisted stats.
  Future<void> accumulateStats(TranscriptionRecord record);

  /// Resets persisted stats to zero.
  Future<void> resetStats();
}
