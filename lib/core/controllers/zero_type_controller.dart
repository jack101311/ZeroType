import 'dart:async';
import 'package:dio/dio.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:zero_type/core/constants/model_pricing.dart';
import 'package:zero_type/core/constants/app_constants.dart';
import 'package:zero_type/core/di/injection.dart';
import 'package:zero_type/core/services/recording_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zero_type/core/services/sound_service.dart';
import 'package:zero_type/core/services/speech_recognition_service.dart';
import 'package:zero_type/core/state/zero_type_state.dart';
import 'package:zero_type/features/history/domain/entities/transcription_record.dart';
import 'package:zero_type/features/history/domain/repositories/history_repository.dart';
import 'package:zero_type/features/model_config/presentation/controllers/model_config_controller.dart';
import 'package:zero_type/features/prompt/presentation/controllers/prompt_controller.dart';
import 'package:zero_type/features/dictionary/presentation/controllers/dictionary_controller.dart';

part 'zero_type_controller.g.dart';

@Riverpod(keepAlive: true)
class ZeroTypeController extends _$ZeroTypeController {
  late final RecordingService _recordingService;
  bool _cancelled = false;
  bool _starting = false;
  bool _processing = false;
  CancelToken? _requestToken;
  DateTime? _recordingStartTime;
  Timer? _maxDurationTimer;

  @override
  ZeroTypeState build() {
    _recordingService = getIt<RecordingService>();
    ref.onDispose(() {
      _cancelled = true;
      _requestToken?.cancel();
      _maxDurationTimer?.cancel();
      unawaited(_recordingService.dispose());
    });

    // Listen for cancel signals from the native overlay (X button or ESC)
    const controlChannel = MethodChannel('com.zerotype.app/control');
    controlChannel.setMethodCallHandler((call) async {
      if (call.method == 'cancel') await cancel();
    });

    return const ZeroTypeState();
  }

  Future<void> toggleRecording() async {
    print(
      '[ZeroTypeController] Hotkey triggered! Current status: ${state.status}',
    );
    if (_starting) return;
    if (state.status == ZeroTypeStatus.recording) {
      await _stopAndProcess();
    } else if (state.status == ZeroTypeStatus.idle && !_processing) {
      await _startRecording();
    } else if (state.status == ZeroTypeStatus.cancelling) {
      return;
    } else {
      await cancel();
    }
  }

  Future<void> cancel() async {
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
    _cancelled = true;
    _requestToken?.cancel('Cancelled by user');
    final bool wasRecording = state.status == ZeroTypeStatus.recording;
    state = state.copyWith(status: ZeroTypeStatus.cancelling);
    // Start/processing owns cleanup until it finishes; do not reuse its recorder.
    if (_starting || _processing) return;
    try {
      if (wasRecording) await _recordingService.cancelRecording();
      await getIt<SoundService>().playCancelSound();
      await getIt<SoundService>().resumeMusic();
    } finally {
      if (ref.mounted) state = const ZeroTypeState();
      await _hideNativeOverlay();
    }
  }

  Future<void> _startRecording() async {
    if (_starting || _processing) return;
    _starting = true;
    try {
      await _startRecordingInternal();
    } catch (e, s) {
      print('[ZeroType] _startRecordingInternal threw: $e\n$s');
      _cancelled = true;
      await _showNativeOverlay('error', '無法開始錄音，請檢查權限與金鑰設定');
      await Future<void>.delayed(const Duration(seconds: 3));
    } finally {
      try {
        if (_cancelled) {
          await _recordingService.cancelRecording();
          await getIt<SoundService>().resumeMusic();
          if (ref.mounted) state = const ZeroTypeState();
          await _hideNativeOverlay();
        }
      } finally {
        _starting = false;
      }
    }
  }

  Future<void> _startRecordingInternal() async {
    _cancelled = false;

    final config = await ref.read(speechProviderControllerProvider.future);
    if (config.providerId == null ||
        config.providerId!.isEmpty ||
        config.apiKey == null ||
        config.apiKey!.isEmpty ||
        config.modelId == null ||
        config.modelId!.isEmpty) {
      await _showNativeOverlay('error', '請先完成語音辨識模型設定');
      await getIt<SoundService>().playCancelSound();
      await Future.delayed(const Duration(seconds: 3));
      if (ref.mounted && !_cancelled) {
        state = const ZeroTypeState();
        await _hideNativeOverlay();
      }
      return;
    }

    // [優化1] 同時檢查 accessibility 與麥克風權限
    const permissionChannel = MethodChannel('com.zerotype.app/permission');
    bool isAccessibilityOk = false;
    bool hasPermission = false;
    try {
      final results = await Future.wait([
        permissionChannel
            .invokeMethod<bool>('checkAccessibility')
            .then((v) => v ?? false)
            .catchError((_) => false),
        _recordingService.requestPermission().catchError((_) => false),
      ]);
      isAccessibilityOk = results[0] as bool;
      hasPermission = results[1] as bool;
    } catch (_) {}

    if (!ref.mounted || _cancelled) return;
    if (!isAccessibilityOk) {
      await _showNativeOverlay('error', '請先授權輔助使用權限');
      await getIt<SoundService>().playCancelSound();
      await Future.delayed(const Duration(seconds: 3));
      if (ref.mounted && !_cancelled) {
        state = const ZeroTypeState();
        await _hideNativeOverlay();
      }
      return;
    }
    if (!hasPermission) {
      await _showNativeOverlay('error', '請先授權麥克風權限');
      await getIt<SoundService>().playCancelSound();
      await Future.delayed(const Duration(seconds: 3));
      if (ref.mounted && !_cancelled) {
        state = const ZeroTypeState();
        await _hideNativeOverlay();
      }
      return;
    }

    // [優化2] 音效不阻塞錄音啟動
    unawaited(getIt<SoundService>().pauseMusic());
    unawaited(getIt<SoundService>().playStartSound());

    if (!ref.mounted || _cancelled) return;
    state = state.copyWith(status: ZeroTypeStatus.recording, amplitude: 0.0);
    _recordingStartTime = DateTime.now();

    // Start max-duration safety timer from user setting (default 1 min, max 5 min)
    final maxMinutes =
        (getIt<SharedPreferences>().getInt(
                  AppConstants.maxRecordingMinutesKey,
                ) ??
                1)
            .clamp(1, 5);
    _maxDurationTimer = Timer(Duration(minutes: maxMinutes), () {
      if (state.status == ZeroTypeStatus.recording) {
        print('[ZeroType] Max recording duration reached, auto-stopping.');
        _stopAndProcess();
      }
    });

    // [優化3] overlay 顯示與錄音初始化同步進行
    try {
      await Future.wait([
        _showNativeOverlay('recording', '錄音中'),
        _recordingService.startRecording(
          onAmplitude: (amp) {
            if (ref.mounted && !_cancelled) {
              state = state.copyWith(amplitude: amp);
              _updateNativeAmplitude(amp);
            }
          },
        ),
      ]);
    } catch (e, s) {
      print('[ZeroType] recorder.start failed: $e\n$s');
      _maxDurationTimer?.cancel();
      await _recordingService.cancelRecording();
      if (!ref.mounted || _cancelled) return;
      state = state.copyWith(
        status: ZeroTypeStatus.error,
        errorMessage: '錄音啟動失敗',
      );
      await _showNativeOverlay('error', '錄音啟動失敗');
      await Future.delayed(const Duration(seconds: 3));
      if (ref.mounted && !_cancelled) {
        state = const ZeroTypeState();
        await _hideNativeOverlay();
      }
    }
  }

  Future<TranscriptionResult?> _transcribe(String filePath) async {
    final config = await ref.read(speechProviderControllerProvider.future);
    final prompt = await ref.read(speechPromptControllerProvider.future);
    final dictionaryPrompt = await ref
        .read(dictionaryRepositoryProvider)
        .buildDictionaryPrompt();

    if (config.providerId == null ||
        config.apiKey == null ||
        config.modelId == null) {
      throw Exception('請先完成語音辨識模型設定');
    }

    final finalPrompt = dictionaryPrompt.isEmpty
        ? prompt
        : '$prompt\n\n$dictionaryPrompt';

    final service = getIt<SpeechRecognitionService>();
    return service.transcribe(
      audioFilePath: filePath,
      apiKey: config.apiKey!,
      provider: config.providerId!,
      model: config.modelId!,
      prompt: finalPrompt,
      customEndpoint: config.customEndpoint,
      cancelToken: _requestToken,
    );
  }

  Future<void> _stopAndProcess() async {
    if (_processing) return;
    _processing = true;
    _requestToken = CancelToken();
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
    String? filePath;
    String? savedAudio;
    String? savedRecordId;
    String? clipboardText;
    bool completed = false;
    final HistoryRepository historyRepo = getIt<HistoryRepository>();
    try {
      state = state.copyWith(status: ZeroTypeStatus.saving);
      await _showNativeOverlay('saving', '擷取中');
      final DateTime stopTime = DateTime.now();
      final int? durationMs = _recordingStartTime == null
          ? null
          : stopTime.difference(_recordingStartTime!).inMilliseconds;
      filePath = await _recordingService.stopRecording();
      await getIt<SoundService>().playStopSound();
      if (_cancelled || !ref.mounted || filePath == null) return;
      state = state.copyWith(status: ZeroTypeStatus.transcribing);
      await _showNativeOverlay('transcribing', '辨識中');
      final config = await ref.read(speechProviderControllerProvider.future);
      if (_cancelled || !ref.mounted) return;
      final TranscriptionResult? result = await _transcribe(filePath);
      if (_cancelled || !ref.mounted) return;
      if (result == null || result.text.isEmpty)
        throw StateError('Empty transcription');
      savedAudio = await historyRepo.moveAudioFile(filePath);
      if (_cancelled || !ref.mounted) return;
      savedRecordId = DateTime.now().microsecondsSinceEpoch.toString();
      final TranscriptionRecord record = TranscriptionRecord(
        id: savedRecordId,
        text: result.text,
        createdAt: DateTime.now(),
        audioPath: savedAudio,
        durationMs: durationMs,
        provider: config.providerId ?? '',
        model: config.modelId ?? '',
        inputTokens: result.inputTokens,
        outputTokens: result.outputTokens,
        costUsd: calculateCost(
          config.modelId ?? '',
          result.inputTokens,
          result.outputTokens,
        ),
      );
      await historyRepo.addRecord(record);
      if (_cancelled || !ref.mounted) return;
      clipboardText = result.text;
      await Clipboard.setData(ClipboardData(text: result.text));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (_cancelled || !ref.mounted) return;
      const MethodChannel channel = MethodChannel('com.zerotype.app/keyboard');
      await channel.invokeMethod<void>('simulatePaste');
      if (_cancelled || !ref.mounted) return;
      completed = true;
      await historyRepo.accumulateStats(record);
      state = state.copyWith(status: ZeroTypeStatus.done, result: result.text);
      await _showNativeOverlay('done', '已完成');
      await Future<void>.delayed(const Duration(seconds: 2));
    } catch (_) {
      // Never display request details, credentials or provider response bodies.
      if (!_cancelled && ref.mounted) {
        state = state.copyWith(
          status: ZeroTypeStatus.error,
          errorMessage: '處理失敗，請檢查連線與模型設定',
        );
        await _showNativeOverlay('error', '處理失敗，請檢查連線與模型設定');
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    } finally {
      try {
        if (!completed) {
          try {
            if (savedRecordId != null)
              await historyRepo.deleteRecord(savedRecordId);
          } finally {
            try {
              if (savedAudio != null)
                await historyRepo.discardAudio(savedAudio);
            } finally {
              if (clipboardText != null) {
                try {
                  final ClipboardData? current = await Clipboard.getData(
                    Clipboard.kTextPlain,
                  );
                  if (current?.text == clipboardText) {
                    await Clipboard.setData(const ClipboardData(text: ''));
                  }
                } catch (_) {
                  // Clipboard access must not block recording/history cleanup.
                }
              }
            }
          }
        }
      } finally {
        try {
          if (filePath != null) await _recordingService.deleteFile(filePath);
          await getIt<SoundService>().resumeMusic();
        } finally {
          _requestToken = null;
          _processing = false;
          if (ref.mounted) state = const ZeroTypeState();
          await _hideNativeOverlay();
        }
      }
    }
  }

  Future<void> showOverlay(String status, String message) =>
      _showNativeOverlay(status, message);

  Future<void> hideOverlay() => _hideNativeOverlay();

  Future<void> _showNativeOverlay(String status, String message) async {
    const channel = MethodChannel('com.zerotype.app/overlay');
    try {
      await channel.invokeMethod<void>('show', {
        'status': status,
        'message': message,
      });
    } catch (_) {}
  }

  Future<void> _hideNativeOverlay() async {
    const channel = MethodChannel('com.zerotype.app/overlay');
    try {
      await channel.invokeMethod<void>('hide');
    } catch (_) {}
  }

  Future<void> _updateNativeAmplitude(double amplitude) async {
    const channel = MethodChannel('com.zerotype.app/overlay');
    try {
      await channel.invokeMethod<void>('updateAmplitude', {
        'amplitude': amplitude,
      });
    } catch (_) {}
  }
}
