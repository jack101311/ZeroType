import 'dart:convert';
import '../security/endpoint_policy.dart';
import 'dart:io';

import 'package:dio/dio.dart';

typedef TranscriptionResult = ({
  String text,
  int? inputTokens,
  int? outputTokens,
});

class SpeechRecognitionService {
  SpeechRecognitionService({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<TranscriptionResult> transcribe({
    required String audioFilePath,
    required String apiKey,
    required String provider,
    required String model,
    required String prompt,
    String? customEndpoint,
    CancelToken? cancelToken,
  }) async {
    if (customEndpoint != null)
      customEndpoint = EndpointPolicy.validate(customEndpoint);
    if (cancelToken?.isCancelled ?? false) throw cancelToken!.cancelError!;

    switch (provider) {
      case 'openai':
        return _transcribeWithOpenAI(
          audioFilePath: audioFilePath,
          apiKey: apiKey,
          model: model,
          prompt: prompt,
          customEndpoint: customEndpoint,
          cancelToken: cancelToken,
        );
      case 'gemini':
        return _transcribeWithGemini(
          audioFilePath: audioFilePath,
          apiKey: apiKey,
          model: model,
          prompt: prompt,
          customEndpoint: customEndpoint,
          cancelToken: cancelToken,
        );
      default:
        throw Exception('不支援的語音辨識服務商：$provider');
    }
  }

  Future<TranscriptionResult> _transcribeWithOpenAI({
    required String audioFilePath,
    required String apiKey,
    required String model,
    required String prompt,
    String? customEndpoint,
    CancelToken? cancelToken,
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        audioFilePath,
        filename: File(audioFilePath).uri.pathSegments.last,
      ),
      'model': model,
      'response_format': 'json',
      if (prompt.isNotEmpty) 'prompt': prompt,
    });

    final url = (customEndpoint != null && customEndpoint.isNotEmpty)
        ? customEndpoint
        : 'https://api.openai.com/v1/audio/transcriptions';

    final response = await _dio.post<dynamic>(
      url,
      cancelToken: cancelToken,
      data: formData,
      options: Options(
        followRedirects: false,
        headers: {'Authorization': 'Bearer $apiKey'},
      ),
    );

    // Parse JSON response to extract text and token usage
    Map<String, dynamic>? data;
    if (response.data is Map<String, dynamic>) {
      data = response.data as Map<String, dynamic>;
    } else if (response.data is String) {
      try {
        data = jsonDecode(response.data as String) as Map<String, dynamic>;
      } catch (_) {
        return (
          text: (response.data as String).trim(),
          inputTokens: null,
          outputTokens: null,
        );
      }
    }

    final text = (data?['text'] as String? ?? '').trim();
    final usageMap = data?['usage'] as Map<String, dynamic>?;
    final inputTokens = usageMap?['input_tokens'] as int?;
    final outputTokens = usageMap?['output_tokens'] as int?;

    return (text: text, inputTokens: inputTokens, outputTokens: outputTokens);
  }

  Future<TranscriptionResult> _transcribeWithGemini({
    required String audioFilePath,
    required String apiKey,
    required String model,
    required String prompt,
    String? customEndpoint,
    CancelToken? cancelToken,
  }) async {
    print('[Gemini] Start direct transcription: $audioFilePath');

    final fileToUpload = File(audioFilePath);
    if (!fileToUpload.existsSync()) {
      throw Exception('找不到音檔：$audioFilePath');
    }

    final mimeType = audioFilePath.endsWith('.m4a')
        ? 'audio/mp4'
        : (audioFilePath.endsWith('.mp3') ? 'audio/mpeg' : 'audio/mp4');
    final audioBytes = await fileToUpload.readAsBytes();
    final base64Audio = base64Encode(audioBytes);

    final finalPrompt = prompt.isEmpty
        ? 'Generate a transcript of the speech.'
        : prompt;

    final url = (customEndpoint != null && customEndpoint.isNotEmpty)
        ? '$customEndpoint/$model:generateContent'
        : 'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent';

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        url,
        cancelToken: cancelToken,
        data: {
          'contents': [
            {
              'parts': [
                {'text': finalPrompt},
                {
                  'inline_data': {'mime_type': mimeType, 'data': base64Audio},
                },
              ],
            },
          ],
        },
        options: Options(
          followRedirects: false,
          headers: {
            'x-goog-api-key': apiKey,
            'Content-Type': 'application/json',
          },
        ),
      );

      final candidates = response.data?['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        throw Exception('Gemini 轉譯失敗：無候選回應');
      }

      final parts = candidates[0]['content']?['parts'] as List?;
      if (parts == null || parts.isEmpty) {
        throw Exception('Gemini 轉譯失敗：內容為空');
      }

      final text = (parts[0]['text'] as String? ?? '').trim();

      // Extract token usage from usageMetadata
      final usageMeta =
          response.data?['usageMetadata'] as Map<String, dynamic>?;
      final inputTokens = usageMeta?['promptTokenCount'] as int?;
      final outputTokens = usageMeta?['candidatesTokenCount'] as int?;

      print('[Gemini] Success! tokens: in=$inputTokens out=$outputTokens');
      return (text: text, inputTokens: inputTokens, outputTokens: outputTokens);
    } on DioException catch (e) {
      print('[Gemini] DioException: ${e.message}');
      print('[Gemini] Status: ${e.response?.statusCode}');
      rethrow;
    }
  }
}
