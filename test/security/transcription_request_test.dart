import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_type/core/services/speech_recognition_service.dart';

void main() {
  late Directory directory;
  late String path;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('zerotype_request_test_');
    path = (await File(
      '${directory.path}/audio.m4a',
    ).writeAsBytes([1, 2, 3])).path;
  });
  tearDown(() => directory.delete(recursive: true));
  for (final String provider in ['openai', 'gemini']) {
    test(
      '$provider attaches credentials only to HTTPS and disables redirects',
      () async {
        final Dio dio = Dio();
        RequestOptions? request;
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest:
                (RequestOptions options, RequestInterceptorHandler handler) {
                  request = options;
                  handler.resolve(
                    Response<dynamic>(
                      requestOptions: options,
                      data: provider == 'openai'
                          ? {'text': 'hello'}
                          : {
                              'candidates': [
                                {
                                  'content': {
                                    'parts': [
                                      {'text': 'hello'},
                                    ],
                                  },
                                },
                              ],
                            },
                    ),
                  );
                },
          ),
        );
        final SpeechRecognitionService service = SpeechRecognitionService(
          dio: dio,
        );
        await service.transcribe(
          audioFilePath: path,
          apiKey: 'test-secret',
          provider: provider,
          model: 'test',
          prompt: 'test',
          customEndpoint: 'https://example.com/api',
        );
        expect(request!.uri.scheme, 'https');
        expect(request!.followRedirects, isFalse);
        expect(
          request!.headers[provider == 'openai'
              ? 'Authorization'
              : 'x-goog-api-key'],
          provider == 'openai' ? 'Bearer test-secret' : 'test-secret',
        );
      },
    );
    test(
      '$provider rejects legacy HTTP endpoint before reading audio or sending credentials',
      () async {
        await expectLater(
          SpeechRecognitionService(dio: Dio()).transcribe(
            audioFilePath: 'missing',
            apiKey: 'test-secret',
            provider: provider,
            model: 'test',
            prompt: '',
            customEndpoint: 'http://example.com',
          ),
          throwsFormatException,
        );
      },
    );
    test('$provider rejects a cancelled operation before sending', () async {
      final CancelToken token = CancelToken()..cancel();
      await expectLater(
        SpeechRecognitionService(dio: Dio()).transcribe(
          audioFilePath: 'missing',
          apiKey: 'test-secret',
          provider: provider,
          model: 'test',
          prompt: '',
          cancelToken: token,
        ),
        throwsA(
          isA<DioException>().having(
            (DioException e) => e.type,
            'type',
            DioExceptionType.cancel,
          ),
        ),
      );
    });
  }
}
