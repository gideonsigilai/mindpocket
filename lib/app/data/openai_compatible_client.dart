import 'dart:convert';

import 'package:http/http.dart' as http;

import 'http_client_factory.dart';
import '../models/chat_message.dart';
import 'http_response_limiter.dart';

Uri apiResourceUri(String baseUrl, String resourcePath) {
  final base = _validatedBaseUri(baseUrl);
  const allowedResources = {'models', 'chat/completions'};
  if (!allowedResources.contains(resourcePath)) {
    throw ArgumentError.value(resourcePath, 'resourcePath');
  }

  final baseSegments = base.pathSegments.where((segment) => segment.isNotEmpty);
  return base.replace(
    pathSegments: [...baseSegments, ...resourcePath.split('/')],
    query: null,
    fragment: null,
  );
}

Uri _validatedBaseUri(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || !uri.hasAuthority || uri.host.isEmpty) {
    throw const FormatException('Enter a valid API address.');
  }
  if (uri.scheme != 'https' && uri.scheme != 'http') {
    throw const FormatException('The API address must use HTTP or HTTPS.');
  }
  if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
    throw const FormatException(
      'Keep credentials, query parameters, and fragments out of the API address.',
    );
  }
  final pathSegments = uri.pathSegments;
  if (pathSegments.any((segment) => segment == '.' || segment == '..')) {
    throw const FormatException('The API address contains an invalid path.');
  }

  final isLoopback = isLoopbackAddress(uri);
  if (uri.scheme == 'http' && !isLoopback) {
    throw const FormatException(
      'Use HTTPS for network APIs. Plain HTTP is allowed only on this device.',
    );
  }
  return uri;
}

class OpenAiCompatibleClient {
  OpenAiCompatibleClient({http.Client? client})
    : _client = client ?? createAppHttpClient();

  static const _timeout = Duration(seconds: 45);
  final http.Client _client;

  Future<List<String>> listModels({
    required String baseUrl,
    required String apiToken,
  }) async {
    final request = http.Request('GET', apiResourceUri(baseUrl, 'models'))
      ..headers.addAll(_headers(apiToken));
    final response = await _client.send(request).timeout(_timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await discardResponseBody(response.stream);
      _requireSuccess(response.statusCode);
    }
    final body = await readUtf8Limited(
      response.stream.timeout(_timeout),
      maxBytes: 4 * 1024 * 1024,
      source: 'API model list',
    );
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic> || decoded['data'] is! List) {
      throw const FormatException('The API returned an invalid model list.');
    }

    final models = <String>[];
    for (final item in decoded['data'] as List) {
      if (item is! Map<String, dynamic>) continue;
      final id = item['id'];
      if (id is String && id.isNotEmpty && id.length <= 256) models.add(id);
    }
    return models;
  }

  Future<String> complete({
    required String baseUrl,
    required String apiToken,
    required String model,
    required List<ChatMessage> messages,
  }) async {
    if (model.trim().isEmpty || model.length > 256) {
      throw const FormatException('Choose a model in the API settings first.');
    }
    if (messages.isEmpty || messages.length > 64) {
      throw const FormatException('The conversation is too long to send.');
    }
    if (messages.any((message) => message.content.length > 128 * 1024)) {
      throw const FormatException('A message exceeds the API size limit.');
    }

    final request =
        http.Request('POST', apiResourceUri(baseUrl, 'chat/completions'))
          ..headers.addAll({
            ..._headers(apiToken),
            'Content-Type': 'application/json',
          })
          ..body = jsonEncode({
            'model': model,
            'messages': messages
                .map(
                  (message) => {
                    'role': message.role == MessageRole.user
                        ? 'user'
                        : 'assistant',
                    'content': message.content,
                  },
                )
                .toList(growable: false),
            'stream': false,
          });
    final response = await _client.send(request).timeout(_timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await discardResponseBody(response.stream);
      _requireSuccess(response.statusCode);
    }
    final body = await readUtf8Limited(
      response.stream.timeout(_timeout),
      maxBytes: 8 * 1024 * 1024,
      source: 'API chat completion',
    );
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic> || decoded['choices'] is! List) {
      throw const FormatException('The API returned an invalid chat response.');
    }
    final choices = decoded['choices'] as List;
    if (choices.isEmpty || choices.first is! Map<String, dynamic>) {
      throw const FormatException('The API returned no chat response.');
    }
    final choice = choices.first as Map<String, dynamic>;
    final message = choice['message'];
    if (message is! Map<String, dynamic>) {
      throw const FormatException('The API returned an invalid chat message.');
    }

    final content = message['content'];
    if (content is String) return content;
    if (content is List) {
      return content
          .whereType<Map<String, dynamic>>()
          .where((part) => part['type'] == 'text' && part['text'] is String)
          .map((part) => part['text'] as String)
          .join();
    }
    throw const FormatException('The API returned no text content.');
  }

  void close() => _client.close();

  Map<String, String> _headers(String apiToken) => {
    'Accept': 'application/json',
    if (apiToken.isNotEmpty) 'Authorization': 'Bearer $apiToken',
  };

  void _requireSuccess(int statusCode) {
    if (statusCode >= 200 && statusCode < 300) return;
    final message = switch (statusCode) {
      401 => 'The API rejected the saved token (HTTP 401).',
      403 => 'The API denied access to this model (HTTP 403).',
      429 => 'The API rate-limited the request. Try again shortly.',
      _ => 'The API request failed (HTTP $statusCode).',
    };
    throw http.ClientException(message);
  }
}
