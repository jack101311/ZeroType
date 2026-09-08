import 'dart:async';
import 'dart:io';

import '../security/private_files.dart';
import 'package:record/record.dart';

typedef AmplitudeCallback = void Function(double amplitude);

class RecordingService {
  RecordingService() : _recorder = AudioRecorder();

  AudioRecorder _recorder;
  String? _currentFilePath;
  Directory? _sessionDirectory;
  // Use a stream subscription instead of a manual timer + getAmplitude() polling.
  // The manual timer approach caused a deadlock on macOS: in-flight getAmplitude()
  // MethodChannel calls would block stop() on the native side indefinitely.
  StreamSubscription<Amplitude>? _amplitudeSubscription;

  Future<bool> checkPermission() async {
    return _recorder.hasPermission();
  }

  Future<bool> requestPermission() async {
    // hasPermission() on macOS will trigger the system dialog if not yet decided
    return _recorder.hasPermission();
  }

  Future<void> startRecording({AmplitudeCallback? onAmplitude}) async {
    final Directory? previousDirectory = _sessionDirectory;
    if (previousDirectory != null && await previousDirectory.exists()) {
      await previousDirectory.delete(recursive: true);
    }
    final Directory dir = await PrivateFiles.createSessionDirectory();
    _sessionDirectory = dir;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    _currentFilePath = '${dir.path}/zerotype_$timestamp.m4a';

    print('[RecordingService] starting at $_currentFilePath');
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 16000,
      ),
      path: _currentFilePath!,
    );

    final isRec = await _recorder.isRecording();
    print('[RecordingService] isRecording after start: $isRec');

    if (onAmplitude != null) {
      _amplitudeSubscription = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((amp) {
            // Map practical speech range (-50 dBFS silence → -5 dBFS loud) to 0–1
            final normalized = ((amp.current + 50) / 45).clamp(0.0, 1.0);
            onAmplitude(normalized);
          });
    }
  }

  Future<String?> stopRecording() async {
    try {
      await _amplitudeSubscription?.cancel();
      _amplitudeSubscription = null;
      if (await _recorder.isRecording()) {
        await _recorder.stop().timeout(const Duration(seconds: 8));
      }
      return _currentFilePath;
    } catch (_) {
      try {
        await _recorder.dispose();
      } finally {
        _recorder = AudioRecorder();
        await _deleteCurrentFile();
      }
      rethrow;
    }
  }

  Future<void> cancelRecording() async {
    try {
      await stopRecording();
    } finally {
      await _deleteCurrentFile();
    }
  }

  Future<void> deleteFile(String filePath) async {
    final file = File(filePath);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  /// Moves [srcPath] to [destPath]. Tries rename first, falls back to copy+delete.
  Future<String> moveFileTo(String srcPath, String destPath) async {
    final srcFile = File(srcPath);
    try {
      await srcFile.rename(destPath);
    } catch (_) {
      await srcFile.copy(destPath);
      await srcFile.delete();
    }
    return destPath;
  }

  Future<void> _deleteCurrentFile() async {
    if (_currentFilePath != null) {
      await deleteFile(_currentFilePath!);
      _currentFilePath = null;
    }
  }

  Future<void> dispose() async {
    try {
      await _recorder.dispose();
    } finally {
      await _deleteCurrentFile();
      final Directory? directory = _sessionDirectory;
      if (directory != null && await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  }
}
