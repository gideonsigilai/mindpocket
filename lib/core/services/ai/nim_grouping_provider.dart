import 'dart:convert';

import 'package:dio/dio.dart';

import '../../utils/logger.dart';

/// One item to be grouped: an id plus the text the model may judge it by.
class GroupingItem {
  const GroupingItem({required this.id, required this.text});

  final String id;
  final String text;
}

/// A grouped result. [collection] is a name; the caller decides whether it is
/// new or already exists.
class GroupingAssignment {
  const GroupingAssignment({
    required this.id,
    required this.collection,
    required this.title,
  });

  final String id;
  final String collection;
  final String title;
}

/// Groups screenshots into collections with an instruction model.
///
/// Only extracted text is sent: no images leave the device for grouping, which
/// keeps a few hundred screenshots to a few kilobytes of request.
abstract class GroupingProvider {
  bool get isConfigured;
  Future<List<GroupingAssignment>> group({
    required List<GroupingItem> items,
    required List<String> knownCollections,
  });
}

/// NVIDIA NIM (OpenAI-compatible chat completions).
///
/// The key is supplied by the caller and never logged.
class NimGroupingProvider implements GroupingProvider {
  NimGroupingProvider({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    Dio? dio,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 20),
               receiveTimeout: const Duration(seconds: 120),
               headers: <String, String>{'Content-Type': 'application/json'},
             ),
           );

  final String baseUrl;
  final String apiKey;
  final String model;
  final Dio _dio;

  static const String _systemPrompt = '''
You organise screenshots into collections for a personal knowledge app.
You receive JSON: {"known_collections":[...],"items":[{"id":"...","text":"..."}]}.
Reply with JSON only, no prose, no markdown fences: an array of objects
{"id":"<same id>","collection":"<name>","title":"<max 8 words>"}.
Rules:
- Reuse a known collection name when the content belongs there; otherwise create a short, concrete name (1-3 words).
- Group by what the screenshot is about (money, recipes, social, shopping, work, travel...), not by app name unless the app is the subject.
- Every input id must appear exactly once in the output.
- Titles describe the specific content; never write "Screenshot".
''';

  @override
  bool get isConfigured =>
      baseUrl.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty &&
      model.trim().isNotEmpty;

  @override
  Future<List<GroupingAssignment>> group({
    required List<GroupingItem> items,
    required List<String> knownCollections,
  }) async {
    if (!isConfigured) {
      throw const GroupingException('No AI backend is configured.');
    }
    if (items.isEmpty) return const <GroupingAssignment>[];

    final String endpoint =
        '${baseUrl.trim().replaceAll(RegExp(r'/+$'), '')}/chat/completions';
    try {
      final Response<Object?> response = await _dio.post<Object?>(
        endpoint,
        data: jsonEncode(<String, Object?>{
          'model': model.trim(),
          'temperature': 0.1,
          'max_tokens': 2048,
          'messages': <Map<String, Object?>>[
            <String, Object?>{'role': 'system', 'content': _systemPrompt},
            <String, Object?>{
              'role': 'user',
              'content': jsonEncode(<String, Object?>{
                'known_collections': knownCollections,
                'items': items
                    .map(
                      (GroupingItem item) => <String, Object?>{
                        'id': item.id,
                        'text': item.text,
                      },
                    )
                    .toList(growable: false),
              }),
            },
          ],
        }),
        options: Options(
          headers: <String, String>{'Authorization': 'Bearer ${apiKey.trim()}'},
          validateStatus: (int? status) => status != null && status < 500,
        ),
      );

      if (response.statusCode != 200) {
        throw GroupingException(
          response.statusCode == 401 || response.statusCode == 403
              ? 'The AI backend rejected the key (${response.statusCode}).'
              : 'The AI backend returned HTTP ${response.statusCode}.',
        );
      }

      final String? content = _contentOf(response.data);
      if (content == null || content.trim().isEmpty) {
        throw const GroupingException(
          'The AI backend returned an empty answer.',
        );
      }
      return parseAnswer(content, items.map((GroupingItem i) => i.id).toSet());
    } on DioException catch (error) {
      logWarn('Grouping request failed', error.message);
      throw GroupingException(
        error.type == DioExceptionType.connectionTimeout ||
                error.type == DioExceptionType.receiveTimeout
            ? 'The AI backend timed out. Nothing was changed.'
            : 'Could not reach the AI backend. Nothing was changed.',
      );
    }
  }

  String? _contentOf(Object? data) {
    Object? decoded = data;
    if (decoded is String) {
      try {
        decoded = jsonDecode(decoded);
      } catch (_) {
        return null;
      }
    }
    if (decoded is Map && decoded['choices'] is List) {
      final List<Object?> choices = decoded['choices'] as List<Object?>;
      if (choices.isEmpty) return null;
      final Object? message = (choices.first as Map)['message'];
      if (message is Map) return message['content']?.toString();
    }
    return null;
  }

  /// Tolerant of the ways models wrap JSON: fenced, prefixed, or an object with
  /// the array nested under a key.
  /// Exposed for tests: the parser is where model output is made safe.
  static List<GroupingAssignment> parseAnswer(
    String content,
    Set<String> validIds,
  ) {
    String text = content.trim();
    final RegExp fence = RegExp(r'```(?:json)?([\s\S]*?)```');
    final RegExpMatch? fenced = fence.firstMatch(text);
    if (fenced != null) text = fenced.group(1)!.trim();

    final int start = text.indexOf('[');
    final int end = text.lastIndexOf(']');
    if (start < 0 || end <= start) {
      throw const GroupingException('The AI answer was not a JSON list.');
    }
    final Object? decoded = jsonDecode(text.substring(start, end + 1));
    if (decoded is! List) {
      throw const GroupingException('The AI answer was not a JSON list.');
    }

    final List<GroupingAssignment> out = <GroupingAssignment>[];
    final Set<String> seen = <String>{};
    for (final Object? entry in decoded) {
      if (entry is! Map) continue;
      final String id = '${entry['id'] ?? ''}';
      final String collection = '${entry['collection'] ?? ''}'.trim();
      if (!validIds.contains(id) || seen.contains(id) || collection.isEmpty) {
        continue;
      }
      seen.add(id);
      out.add(
        GroupingAssignment(
          id: id,
          collection: _clip(collection, 40),
          title: _clip('${entry['title'] ?? ''}'.trim(), 80),
        ),
      );
    }
    return out;
  }

  static String _clip(String value, int max) =>
      value.length <= max ? value : value.substring(0, max).trim();
}

class GroupingException implements Exception {
  const GroupingException(this.message);

  final String message;

  @override
  String toString() => message;
}
