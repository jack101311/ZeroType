import 'dart:async';
import 'dart:io';
import 'package:zero_type/core/services/history_playback_service.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:zero_type/core/di/injection.dart';
import 'package:zero_type/features/history/domain/entities/history_stats.dart';
import 'package:zero_type/features/history/domain/entities/transcription_record.dart';
import 'package:zero_type/features/history/domain/repositories/history_repository.dart';

part 'history_controller.g.dart';

// ---------------------------------------------------------------------------
// Stats provider — cumulative, persisted independently of the record list
// ---------------------------------------------------------------------------

@riverpod
Future<HistoryStats> historyStats(Ref ref) =>
    getIt<HistoryRepository>().getStats();

// ---------------------------------------------------------------------------
// Playback state — which record id is currently playing
// ---------------------------------------------------------------------------

@riverpod
class PlayingRecordId extends _$PlayingRecordId {
  @override
  String? build() => null;

  void set(String? id) => state = id;
}

// ---------------------------------------------------------------------------
// History controller — manages record list and audio playback
// ---------------------------------------------------------------------------

@riverpod
class HistoryController extends _$HistoryController {
  late HistoryPlaybackService _playback;

  @override
  Future<List<TranscriptionRecord>> build() async {
    final HistoryPlaybackService playback = HistoryPlaybackService(
      repository: getIt<HistoryRepository>(),
      onChanged: (String? id) {
        if (ref.mounted) ref.read(playingRecordIdProvider.notifier).set(id);
      },
    );
    _playback = playback;
    ref.onDispose(() => unawaited(playback.dispose()));
    return getIt<HistoryRepository>().getRecords();
  }

  Future<void> _stopPlayback() => _playback.stop();

  Future<void> togglePlay(TranscriptionRecord record) =>
      _playback.toggle(record);

  Future<void> revealInFinder(String audioPath) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', ['-R', audioPath]);
      } else if (Platform.isWindows) {
        await Process.run('explorer.exe', [
          '/select,',
          audioPath.replaceAll('/', '\\'),
        ]);
      }
    } catch (e) {
      print('[HistoryController] revealInFinder error: $e');
    }
  }

  Future<void> copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> deleteRecord(String id) async {
    final currentId = ref.read(playingRecordIdProvider);
    if (currentId == id) await _stopPlayback();
    await getIt<HistoryRepository>().deleteRecord(id);
    ref.invalidateSelf();
  }

  Future<void> clearAll() async {
    await _stopPlayback();
    await getIt<HistoryRepository>().clearAll();
    ref.invalidateSelf();
  }
}
