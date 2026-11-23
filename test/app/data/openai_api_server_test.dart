import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:local_ai_studio/app/data/openai_api_server.dart';

void main() {
  late OpenAiApiServer server;
  late IOClient client;
  late Uri baseUri;

  setUp(() async {
    final reservation = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final port = reservation.port;
    await reservation.close();
    server = OpenAiApiServer(
      validateApiKey: (key) async => key == 'test-key',
      models: () => ['test-model'],
      complete: (model, messages) async => '$model:${messages.last.content}',
    );
    await server.start(port: port);
    baseUri = Uri.parse(server.baseUrl);
    client = IOClient(HttpClient()..findProxy = (_) => 'DIRECT');
  });

  tearDown(() async {
    client.close();
    await server.stop();
  });

  test(
    'serves authenticated OpenAI-compatible models and completions',
    () async {
      final modelResponse = await client.get(
        baseUri.resolve('/v1/models'),
        headers: {'Authorization': 'Bearer test-key'},
      );
      expect(modelResponse.statusCode, HttpStatus.ok);
      expect((jsonDecode(modelResponse.body) as Map<String, dynamic>)['data'], [
        {'id': 'test-model', 'object': 'model', 'owned_by': 'loom'},
      ]);

      final completionResponse = await client.post(
        baseUri.resolve('/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer test-key',
          HttpHeaders.contentTypeHeader: ContentType.json.mimeType,
        },
        body: jsonEncode({
          'model': 'test-model',
          'messages': [
            {'role': 'user', 'content': 'hello'},
          ],
        }),
      );
      expect(completionResponse.statusCode, HttpStatus.ok);
      final completion =
          jsonDecode(completionResponse.body) as Map<String, dynamic>;
      expect(completion['object'], 'chat.completion');
      expect(
        ((completion['choices'] as List).single
            as Map<String, dynamic>)['message'],
        {'role': 'assistant', 'content': 'test-model:hello'},
      );
    },
  );

  test('rejects unauthorized requests', () async {
    final unauthorized = await client.get(baseUri.resolve('/v1/models'));
    expect(unauthorized.statusCode, HttpStatus.unauthorized);
    expect(
      (jsonDecode(unauthorized.body) as Map<String, dynamic>)['error'],
      isA<Map<String, dynamic>>(),
    );
  });

  test('streams OpenAI-compatible SSE chunks', () async {
    final streaming = await client.post(
      baseUri.resolve('/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer test-key',
        HttpHeaders.contentTypeHeader: ContentType.json.mimeType,
      },
      body: jsonEncode({
        'model': 'test-model',
        'messages': [
          {'role': 'user', 'content': 'hello'},
        ],
        'stream': true,
      }),
    );
    expect(streaming.statusCode, HttpStatus.ok);
    expect(
      streaming.headers[HttpHeaders.contentTypeHeader],
      contains('text/event-stream'),
    );
    expect(streaming.body, contains('chat.completion.chunk'));
    expect(streaming.body, contains('"role":"assistant"'));
    expect(streaming.body, contains('test-model:hello'));
    expect(streaming.body, endsWith('data: [DONE]\n\n'));
  });

  test('queues overlapping streaming completions', () async {
    final port = baseUri.port;
    await server.stop();

    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    var activeGenerations = 0;
    var maximumActiveGenerations = 0;

    server = OpenAiApiServer(
      validateApiKey: (key) async => key == 'test-key',
      models: () => ['test-model'],
      complete: (model, messages) async => '$model:${messages.last.content}',
      stream: (model, messages) async {
        return () async* {
          activeGenerations++;
          if (activeGenerations > maximumActiveGenerations) {
            maximumActiveGenerations = activeGenerations;
          }
          try {
            if (messages.last.content == 'first') {
              firstStarted.complete();
              yield '$model:first';
              await releaseFirst.future;
              yield ':finished';
            } else {
              yield '$model:second';
            }
          } finally {
            activeGenerations--;
          }
        }();
      },
    );
    await server.start(port: port);

    http.Request request(String content) =>
        http.Request('POST', baseUri.resolve('/v1/chat/completions'))
          ..headers.addAll({
            'Authorization': 'Bearer test-key',
            HttpHeaders.contentTypeHeader: ContentType.json.mimeType,
          })
          ..body = jsonEncode({
            'model': 'test-model',
            'messages': [
              {'role': 'user', 'content': content},
            ],
            'stream': true,
          });

    final firstResponse = await client.send(request('first'));
    final firstBody = StringBuffer();
    final firstChunkReceived = Completer<void>();
    final firstBodyDone = Completer<void>();
    firstResponse.stream
        .transform(utf8.decoder)
        .listen(
          (chunk) {
            firstBody.write(chunk);
            if (!firstChunkReceived.isCompleted &&
                firstBody.toString().contains('test-model:first')) {
              firstChunkReceived.complete();
            }
          },
          onDone: () {
            if (!firstBodyDone.isCompleted) firstBodyDone.complete();
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!firstBodyDone.isCompleted) {
              firstBodyDone.completeError(error, stackTrace);
            }
          },
        );
    await firstStarted.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () => throw StateError('The first stream did not start.'),
    );
    await firstChunkReceived.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () => throw StateError('The first chunk was not flushed.'),
    );
    final secondResponseFuture = client.send(request('second'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(maximumActiveGenerations, 1);

    releaseFirst.complete();
    final secondResponse = await secondResponseFuture;
    final secondBody = await secondResponse.stream.bytesToString();
    await firstBodyDone.future.timeout(const Duration(seconds: 2));
    expect(firstResponse.statusCode, HttpStatus.ok);
    expect(secondResponse.statusCode, HttpStatus.ok);
    expect(firstBody.toString(), contains('test-model:first'));
    expect(firstBody.toString(), contains(':finished'));
    expect(secondBody, contains('test-model:second'));
    expect(maximumActiveGenerations, 1);
  });

  test('accepts agent system prompts above the old 32 KB limit', () async {
    final completionResponse = await client.post(
      baseUri.resolve('/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer test-key',
        HttpHeaders.contentTypeHeader: ContentType.json.mimeType,
      },
      body: jsonEncode({
        'model': 'test-model',
        'messages': [
          {'role': 'system', 'content': 'x' * 34373},
          {'role': 'user', 'content': 'hi'},
        ],
      }),
    );
    expect(completionResponse.statusCode, HttpStatus.ok);
  });

  test('accepts OpenAI text-part content arrays', () async {
    final completionResponse = await client.post(
      baseUri.resolve('/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer test-key',
        HttpHeaders.contentTypeHeader: ContentType.json.mimeType,
      },
      body: jsonEncode({
        'model': 'test-model',
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': 'hello'},
              {'type': 'text', 'text': 'world'},
            ],
          },
        ],
      }),
    );
    expect(completionResponse.statusCode, HttpStatus.ok);
    final completion =
        jsonDecode(completionResponse.body) as Map<String, dynamic>;
    expect(
      ((completion['choices'] as List).single
          as Map<String, dynamic>)['message']['content'],
      'test-model:hello\nworld',
    );
  });

  test('removes OMP system reminder XML from user input', () {
    const input =
        'Before <system-reminder>secret runtime instructions</system-reminder> after';
    expect(sanitizeApiText(input), 'Before  after');
  });

  test('exports a provider config using the local endpoint', () {
    final yaml = openAiProviderYaml(
      apiKey: 'loom_sk_test',
      modelId: 'my model',
      port: 8765,
    );

    expect(yaml, contains('api: openai-completions'));
    expect(yaml, contains('apiKey: "loom_sk_test"'));
    expect(yaml, contains('baseUrl: http://127.0.0.1:8765/v1'));
    expect(yaml, contains('id: "my model"'));
  });
}
