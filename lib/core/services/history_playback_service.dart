import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:synchronized/synchronized.dart';
import '../security/private_files.dart';
import '../../features/history/domain/entities/transcription_record.dart';
import '../../features/history/domain/repositories/history_repository.dart';

/// Each provider build owns one player, so disposal cannot touch a new session.
class HistoryPlaybackService {
  HistoryPlaybackService({
    required HistoryRepository repository,
    required void Function(String?) onChanged,
    AudioPlayer? player,
    Future<Directory> Function()? createDirectory,
  }) : _repository = repository,
       _onChanged = onChanged,
       _player = player ?? AudioPlayer(),
       _createDirectory =
           createDirectory ?? PrivateFiles.createSessionDirectory {
    _completion = _player.onPlayerComplete.listen((_) => unawaited(stop()));
  }
  final HistoryRepository _repository;
  final void Function(String?) _onChanged;
  final AudioPlayer _player;
  final Future<Directory> Function() _createDirectory;
  final Lock _lock = Lock();
  StreamSubscription<void>? _completion;
  Directory? _directory;
  String? _playingId;
  bool _disposed = false;

  Future<void> _deleteTemporaryAudio() async {
    final Directory? directory = _directory;
    _directory = null;
    if (directory != null && await directory.exists())
      await directory.delete(recursive: true);
  }

  Future<void> _stop() async {
    try {
      await _player.release();
    } finally {
      await _deleteTemporaryAudio();
    }
    _playingId = null;
    if (!_disposed) _onChanged(null);
  }

  Future<void> stop() => _lock.synchronized(() async {
    if (!_disposed) await _stop();
  });

  Future<void> toggle(TranscriptionRecord record) => _lock.synchronized(
    () async {
      if (_disposed || record.audioPath == null) return;
      final bool wasPlaying = _playingId == record.id;
      await _stop();
      if (wasPlaying) return;
      try {
        final List<int> bytes = await _repository.readAudio(record.audioPath!);
        if (_disposed) return;
        final Directory directory = await _createDirectory();
        _directory = directory;
        final File file = File('${directory.path}/playback.m4a');
        await file.writeAsBytes(bytes, flush: true);
        if (_disposed) {
          await _deleteTemporaryAudio();
          return;
        }
        _playingId = record.id;
        _onChanged(record.id);
        await _player.play(DeviceFileSource(file.path));
      } catch (_) {
        await _stop();
      }
    },
  );

  Future<void> dispose() async {
    _disposed = true;
    await _completion?.cancel();
    await _lock.synchronized(() async {
      try {
        await _player.dispose();
      } finally {
        await _deleteTemporaryAudio();
      }
    });
  }
}
