import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'http_response_limiter.dart';

class ApiMessage {
  const ApiMessage({required this.role, required this.content});

  final String role;
  final String content;
}

class ApiRequestException implements Exception {
  const ApiRequestException(this.statusCode, this.code, this.message);

  final int statusCode;
  final String code;
  final String message;
}

String sanitizeApiText(String text) {
  return text
      .replaceAll(
        RegExp(
          r'<system-reminder>[\s\S]*?</system-reminder>',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(
        RegExp(
          r'<project-context>[\s\S]*?</project-context>',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(
        RegExp(r'<critical>[\s\S]*?</critical>', caseSensitive: false),
        '',
      )
      .trim();
}

typedef ApiKeyValidator = Future<bool> Function(String key);
typedef ApiModelsProvider = List<String> Function();
typedef ApiCompletionHandler = Future<String> Function(
  String model,
  List<ApiMessage> messages,
);
typedef ApiStreamCompletionHandler = Future<Stream<String>> Function(
  String model,
  List<ApiMessage> messages,
);

class OpenAiApiServer {
  OpenAiApiServer({
    required this.validateApiKey,
    required this.models,
    required this.complete,
    this.stream,
  });

  static const defaultPort = 8765;
  static const _maxRequestBytes = 1024 * 1024;
  static const _maxMessages = 64;
  static const _maxMessageCharacters = 128 * 1024;

  final ApiKeyValidator validateApiKey;
  final ApiModelsProvider models;
  final ApiCompletionHandler complete;
  final ApiStreamCompletionHandler? stream;
  HttpServer? _server;
  Future<void> _generationQueue = Future<void>.value();

  bool get isRunning => _server != null;
  int? get port => _server?.port;
  String get baseUrl => 'http://127.0.0.1:${port ?? defaultPort}/v1';

  Future<void> start({int port = defaultPort}) async {
    if (_server != null) return;
    if (port < 1 || port > 65535) {
      throw const FormatException('Choose a port between 1 and 65535.');
    }
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server!.listen((request) => unawaited(_handle(request)));
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final token = _bearerToken(request);
      if (token == null || !await validateApiKey(token)) {
        throw const ApiRequestException(
          HttpStatus.unauthorized,
          'invalid_api_key',
          'A valid Bearer API key is required.',
        );
      }

      final path = request.uri.path;
      if (request.method == 'GET' && path == '/v1/models') {
        _writeJson(request.response, HttpStatus.ok, {
          'object': 'list',
          'data': [
            for (final model in models())
              {'id': model, 'object': 'model', 'owned_by': 'loom'},
          ],
        });
        return;
      }
      if (request.method == 'POST' && path == '/v1/chat/completions') {
        await _handleCompletion(request);
        return;
      }
      throw const ApiRequestException(
        HttpStatus.notFound,
        'not_found',
        'The requested API endpoint was not found.',
      );
    } on ApiRequestException catch (error) {
      _writeError(request.response, error);
    } on FormatException catch (error) {
      _writeError(
        request.response,
        ApiRequestException(
          HttpStatus.badRequest,
          'invalid_request',
          error.message.toString(),
        ),
      );
    } on Object {
      _writeError(
        request.response,
        const ApiRequestException(
          HttpStatus.internalServerError,
          'internal_error',
          'The API could not complete this request.',
        ),
      );
    }
  }

  Future<void> _handleCompletion(HttpRequest request) async {
    if (request.headers.contentLength > _maxRequestBytes) {
      throw const ApiRequestException(
        413,
        'request_too_large',
        'The request body exceeds the 1 MB limit.',
      );
    }
    final body = await readUtf8Limited(
      request,
      maxBytes: _maxRequestBytes,
      source: 'API request',
    );
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('The request body must be a JSON object.');
    }
    final model = decoded['model'];
    if (model is! String || model.trim().isEmpty || model.length > 256) {
      throw const FormatException('Provide a model ID of 1 to 256 characters.');
    }
    if (!models().contains(model)) {
      throw const ApiRequestException(
        HttpStatus.notFound,
        'model_not_found',
        'The requested model is not currently available.',
      );
    }
    final messagesValue = decoded['messages'];
    if (messagesValue is! List ||
        messagesValue.isEmpty ||
        messagesValue.length > _maxMessages) {
      throw const FormatException('Provide between 1 and 64 messages.');
    }
    final messages = <ApiMessage>[];
    for (final value in messagesValue) {
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Each message must be a JSON object.');
      }
      final role = value['role'];
      final contentValue = value['content'];
      final content = switch (contentValue) {
        String() => contentValue,
        List() =>
          contentValue
              .whereType<Map<String, dynamic>>()
              .where((part) => part['type'] == 'text')
              .map((part) => part['text'])
              .whereType<String>()
              .join('\n'),
        _ => null,
      };
      if (role is! String ||
          !const {'system', 'user', 'assistant'}.contains(role)) {
        throw const FormatException(
          'Message roles must be system, user, or assistant.',
        );
      }
      final sanitizedContent = content == null
          ? null
          : sanitizeApiText(content);
      if (sanitizedContent == null ||
          sanitizedContent.length > _maxMessageCharacters) {
        throw const FormatException(
          'Message content must be text of 32,768 characters or fewer.',
        );
      }
      messages.add(ApiMessage(role: role, content: sanitizedContent));
    }

    if (decoded['stream'] == true) {
      await _writeStreamingCompletion(request.response, model, messages);
      return;
    }
    final content = await _runGeneration(() => complete(model, messages));
    final now = DateTime.now().toUtc();
    _writeJson(request.response, HttpStatus.ok, {
      'id': 'chatcmpl-${now.microsecondsSinceEpoch}',
      'object': 'chat.completion',
      'created': now.millisecondsSinceEpoch ~/ 1000,
      'model': model,
      'choices': [
        {
          'index': 0,
          'message': {'role': 'assistant', 'content': content},
          'finish_reason': 'stop',
        },
      ],
    });
  }

  Future<void> _writeStreamingCompletion(
    HttpResponse response,
    String model,
    List<ApiMessage> messages,
  ) async {
    final now = DateTime.now().toUtc();
    final id = 'chatcmpl-${now.microsecondsSinceEpoch}';
    final created = now.millisecondsSinceEpoch ~/ 1000;

    response
      ..bufferOutput = false
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      )
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
      ..headers.set('Connection', 'keep-alive');

    Future<void> writeChunk(
      Map<String, dynamic> delta, {
      String? finishReason,
    }) async {
      response.write(
        'data: ${jsonEncode({
          'id': id,
          'object': 'chat.completion.chunk',
          'created': created,
          'model': model,
          'choices': [
            {'index': 0, 'delta': delta, 'finish_reason': ?finishReason},
          ],
        })}\n\n',
      );
      await response.flush();
    }

    try {
      await writeChunk({'role': 'assistant', 'content': ''});
      await for (final content in _runStreamingGeneration(model, messages)) {
        if (content.isNotEmpty) await writeChunk({'content': content});
      }
      await writeChunk({}, finishReason: 'stop');
      response.write('data: [DONE]\n\n');
      await response.close();
    } on ApiRequestException catch (error) {
      response.write(
        'data: ${jsonEncode({
          'error': {'message': error.message, 'type': 'api_error', 'code': error.code},
        })}\n\n',
      );
      await response.close();
    } on StateError catch (error) {
      response.write(
        'data: ${jsonEncode({
          'error': {'message': error.message.toString(), 'type': 'api_error', 'code': 'generation_failed'},
        })}\n\n',
      );
      await response.close();
    } on Object catch (error) {
      response.write(
        'data: ${jsonEncode({
          'error': {'message': 'The API could not complete this streaming request: ${error.runtimeType}: $error', 'type': 'api_error', 'code': 'internal_error'},
        })}\n\n',
      );
      await response.close();
    }
  }

  Future<T> _runGeneration<T>(Future<T> Function() operation) {
    final previous = _generationQueue;
    final release = Completer<void>();
    _generationQueue = release.future;

    return () async {
      await previous;
      try {
        return await operation();
      } finally {
        release.complete();
      }
    }();
  }

  Stream<String> _runStreamingGeneration(
    String model,
    List<ApiMessage> messages,
  ) async* {
    final previous = _generationQueue;
    final release = Completer<void>();
    _generationQueue = release.future;
    await previous;

    try {
      final handler = stream;
      if (handler == null) {
        yield await complete(model, messages);
      } else {
        yield* await handler(model, messages);
      }
    } finally {
      release.complete();
    }
  }

  String? _bearerToken(HttpRequest request) {
    final authorization = request.headers.value(
      HttpHeaders.authorizationHeader,
    );
    if (authorization == null) return null;
    final match = RegExp(
      r'^Bearer\s+(\S+)$',
      caseSensitive: false,
    ).firstMatch(authorization.trim());
    return match?.group(1);
  }

  void _writeError(HttpResponse response, ApiRequestException error) {
    _writeJson(response, error.statusCode, {
      'error': {
        'message': error.message,
        'type': 'api_error',
        'code': error.code,
      },
    });
  }

  void _writeJson(HttpResponse response, int statusCode, Object body) {
    response
      ..statusCode = statusCode
      ..headers.contentType = ContentType.json
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
      ..write(jsonEncode(body));
    unawaited(response.close());
  }
}

String openAiProviderYaml({
  required String apiKey,
  required String modelId,
  required int port,
}) =>
    '''
providers:
  loom-local:
    api: openai-completions
    apiKey: "$apiKey"
    baseUrl: http://127.0.0.1:$port/v1
    models:
      - id: ${jsonEncode(modelId)}
        name: ${jsonEncode(modelId)}
''';
