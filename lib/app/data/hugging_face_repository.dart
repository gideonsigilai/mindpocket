import 'dart:isolate';

import 'package:http/http.dart' as http;

import 'http_client_factory.dart';
import '../models/model_info.dart';
import 'http_response_limiter.dart';

class HuggingFaceRepository {
  HuggingFaceRepository({http.Client? client})
    : _client = client ?? createAppHttpClient();

  static const int pageSize = 24;
  static const Duration _requestTimeout = Duration(seconds: 30);

  final http.Client _client;

  Future<ModelSearchPage> search({
    required String query,
    String? cursor,
    String? accessToken,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.length > 120) {
      throw ArgumentError.value(query, 'query', 'Search text is too long.');
    }
    if (cursor != null && cursor.length > 4096) {
      throw ArgumentError.value(cursor, 'cursor', 'Invalid pagination cursor.');
    }

    final uri = Uri.https('huggingface.co', '/api/models', {
      'filter': 'gguf',
      'pipeline_tag': 'text-generation',
      'sort': 'downloads',
      'direction': '-1',
      'limit': '$pageSize',
      if (normalizedQuery.isNotEmpty) 'search': normalizedQuery,
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    });
    final request = http.Request('GET', uri)
      ..headers.addAll(_headers(accessToken));
    final response = await _client.send(request).timeout(_requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await discardResponseBody(response.stream);
      _requireSuccess(response.statusCode, 'model search');
    }

    final body = await readUtf8Limited(
      response.stream.timeout(_requestTimeout),
      maxBytes: 2 * 1024 * 1024,
      source: 'Hugging Face model search',
    );
    final nextCursor = parseNextCursor(response.headers['link']);
    return Isolate.run(
      () => parseModelSearchResponse(body, nextCursor: nextCursor),
    );
  }

  Future<List<ModelArtifact>> listArtifacts({
    required String repository,
    String? accessToken,
  }) async {
    if (!isSafeModelRepositoryId(repository)) {
      throw ArgumentError.value(repository, 'repository', 'Invalid model ID.');
    }

    final uri = Uri.https('huggingface.co', '/api/models/$repository', {
      'blobs': 'true',
    });
    final request = http.Request('GET', uri)
      ..headers.addAll(_headers(accessToken));
    final response = await _client.send(request).timeout(_requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await discardResponseBody(response.stream);
      _requireSuccess(response.statusCode, 'model details');
    }

    final body = await readUtf8Limited(
      response.stream.timeout(_requestTimeout),
      maxBytes: 16 * 1024 * 1024,
      source: 'Hugging Face model details',
    );
    return Isolate.run(
      () => parseModelArtifacts(body, repository: repository),
    );
  }

  void close() => _client.close();

  Map<String, String> _headers(String? accessToken) => {
    'Accept': 'application/json',
    if (accessToken != null && accessToken.isNotEmpty)
      'Authorization': 'Bearer $accessToken',
  };

  void _requireSuccess(int statusCode, String operation) {
    if (statusCode >= 200 && statusCode < 300) return;
    final message = switch (statusCode) {
      401 => 'Hugging Face rejected the access token.',
      403 => 'This Hugging Face model is not accessible with the current token.',
      429 => 'Hugging Face rate-limited the request. Try again shortly.',
      _ => 'Hugging Face $operation failed (HTTP $statusCode).',
    };
    throw http.ClientException(message);
  }
}
