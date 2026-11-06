import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../models/attachment.dart';
import '../../models/memory.dart';
import '../../utils/logger.dart';

/// What a cloud request would include. Shown to the user before sending, so the
/// consent dialog can be specific instead of generic.
class CloudDisclosure {
  const CloudDisclosure({
    required this.includesTitle,
    required this.includesNote,
    required this.includesOcrText,
    required this.includesTranscript,
    required this.includesImage,
    required this.characterCount,
    required this.imageCount,
    this.providerLabel = 'your configured backend',
  });

  final bool includesTitle;
  final bool includesNote;
  final bool includesOcrText;
  final bool includesTranscript;
  final bool includesImage;
  final int characterCount;
  final int imageCount;
  final String providerLabel;

  List<String> get includedLabels => <String>[
    if (includesTitle) 'title',
    if (includesNote) 'your note',
    if (includesOcrText) 'extracted image text',
    if (includesTranscript) 'voice transcript',
    if (includesImage) '$imageCount image${imageCount == 1 ? '' : 's'}',
  ];

  bool get hasAnything => includedLabels.isNotEmpty;
}

/// Provider-neutral analysis contract. Implementations must return structured
/// data validated by [CloudAnalysisResult.fromJson].
abstract class AiAnalysisProvider {
  String get id;
  String get label;
  bool get isConfigured;
  Future<CloudAnalysisResult> analyse(CloudAnalysisRequest request);
}

class CloudAnalysisRequest {
  const CloudAnalysisRequest({
    required this.memory,
    required this.includeImages,
    required this.imageBase64,
    required this.existingCollections,
  });

  final Memory memory;
  final bool includeImages;
  final List<String> imageBase64;
  final List<String> existingCollections;

  CloudDisclosure get disclosure => CloudDisclosure(
    includesTitle: memory.title.trim().isNotEmpty,
    includesNote: memory.note.trim().isNotEmpty,
    includesOcrText: memory.ocrText.trim().isNotEmpty,
    includesTranscript: memory.transcriptText.trim().isNotEmpty,
    includesImage: includeImages && imageBase64.isNotEmpty,
    characterCount: memory.combinedText.length,
    imageCount: imageBase64.length,
  );
}

/// Validated, structured output. Everything is optional and inert until the user
/// accepts individual fields.
class CloudAnalysisResult {
  const CloudAnalysisResult({
    this.title = '',
    this.summary = '',
    this.tags = const <String>[],
    this.category = '',
    this.collectionName = '',
    this.tasks = const <AiTask>[],
    this.provider = '',
  });

  final String title;
  final String summary;
  final List<String> tags;
  final String category;
  final String collectionName;
  final List<AiTask> tasks;
  final String provider;

  bool get isEmpty =>
      title.isEmpty &&
      summary.isEmpty &&
      tags.isEmpty &&
      category.isEmpty &&
      collectionName.isEmpty &&
      tasks.isEmpty;

  /// Strict parser. Unknown fields are ignored, wrong types are rejected, and
  /// all strings are clipped. The payload is data: any instruction-like text in
  /// it stays text and is never executed.
  static CloudAnalysisResult fromJson(
    Map<String, dynamic> json, {
    required String provider,
  }) {
    String str(Object? value, {int max = 500}) {
      if (value is! String) return '';
      final String trimmed = value.trim();
      return trimmed.length > max ? trimmed.substring(0, max) : trimmed;
    }

    final List<String> tags = <String>[];
    final Object? rawTags = json['tags'];
    if (rawTags is List) {
      for (final Object? entry in rawTags) {
        final String tag = str(
          entry,
          max: 40,
        ).replaceAll(RegExp(r'[^\w\s&/-]'), '');
        if (tag.isNotEmpty && !tags.contains(tag) && tags.length < 12) {
          tags.add(tag);
        }
      }
    }

    final List<AiTask> tasks = <AiTask>[];
    final Object? rawTasks = json['tasks'];
    if (rawTasks is List) {
      for (final Object? entry in rawTasks) {
        if (entry is Map) {
          final String title = str(entry['title'], max: 140);
          if (title.isNotEmpty && tasks.length < 8) {
            tasks.add(AiTask(title: title));
          }
        } else if (entry is String) {
          final String title = str(entry, max: 140);
          if (title.isNotEmpty && tasks.length < 8) {
            tasks.add(AiTask(title: title));
          }
        }
      }
    }

    return CloudAnalysisResult(
      title: str(json['title'], max: 120),
      summary: str(json['summary'], max: 1200),
      tags: tags,
      category: str(json['category'], max: 60),
      collectionName: str(json['collection'], max: 80),
      tasks: tasks,
      provider: provider,
    );
  }
}

/// Talks to a user-configured backend proxy.
///
/// There is deliberately no provider API key in the app: secrets cannot be kept
/// in an APK, and secure local storage only protects a token *after* it was
/// shipped. The proxy URL is stored in preferences; an optional bearer token is
/// stored in secure storage.
class ProxyAiProvider implements AiAnalysisProvider {
  ProxyAiProvider({
    required this.baseUrl,
    required this.secureStorage,
    Dio? dio,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 20),
               receiveTimeout: const Duration(seconds: 60),
               headers: <String, String>{'Content-Type': 'application/json'},
             ),
           );

  static const String _tokenKey = 'cloud_proxy_token';

  final String baseUrl;
  final FlutterSecureStorage secureStorage;
  final Dio _dio;

  @override
  String get id => 'proxy';

  @override
  String get label => 'Your AI backend';

  @override
  bool get isConfigured => baseUrl.trim().isNotEmpty;

  Future<void> saveToken(String token) async {
    if (token.trim().isEmpty) {
      await secureStorage.delete(key: _tokenKey);
    } else {
      await secureStorage.write(key: _tokenKey, value: token.trim());
    }
  }

  Future<bool> hasToken() async =>
      (await secureStorage.read(key: _tokenKey))?.isNotEmpty ?? false;

  @override
  Future<CloudAnalysisResult> analyse(CloudAnalysisRequest request) async {
    if (!isConfigured) {
      throw AiConfigurationException(
        'No AI backend is configured. Add your proxy URL in Settings, or keep '
        'using the fully offline features.',
      );
    }
    final Memory memory = request.memory;
    final Map<String, Object?> payload = <String, Object?>{
      'schema_version': 1,
      'task': 'organise_memory',
      'content': <String, Object?>{
        'title': memory.title,
        'note': memory.note,
        'ocr_text': memory.ocrText,
        'transcript': memory.transcriptText,
        'tags': memory.tags,
      },
      'images': request.includeImages ? request.imageBase64 : const <String>[],
      'known_collections': request.existingCollections,
      'response_format': <String, Object?>{
        'type': 'json',
        'fields': <String>[
          'title',
          'summary',
          'tags',
          'category',
          'collection',
          'tasks',
        ],
      },
    };

    try {
      final Response<Object?> response = await _dio.post<Object?>(
        baseUrl.trim(),
        data: jsonEncode(payload),
        options: Options(
          headers: <String, String>{
            'Authorization':
                'Bearer ${await secureStorage.read(key: _tokenKey) ?? ''}',
          },
          validateStatus: (int? status) => status != null && status < 500,
        ),
      );

      if (response.statusCode != 200) {
        throw AiRequestException(
          response.statusCode == 401 || response.statusCode == 403
              ? 'The backend rejected this request (${response.statusCode}). Check the token in Settings.'
              : 'The backend returned HTTP ${response.statusCode}. Nothing was saved.',
        );
      }

      final Object? data = response.data;
      final Map<String, dynamic> decoded;
      if (data is String) {
        final Object? parsed = jsonDecode(data);
        if (parsed is! Map<String, dynamic>) {
          throw const AiRequestException(
            'The backend returned malformed data. Nothing was saved.',
          );
        }
        decoded = parsed;
        // Accept a nested `result` object from proxies that wrap output.
        if (decoded['result'] case final Map<String, dynamic> inner) {
          return _validate(inner);
        }
      } else if (data is Map<String, dynamic>) {
        decoded = data;
        if (decoded['result'] case final Map<String, dynamic> inner) {
          return _validate(inner);
        }
      } else {
        throw const AiRequestException(
          'The backend returned an unexpected format.',
        );
      }
      return _validate(decoded);
    } on DioException catch (error) {
      logWarn('Cloud analysis failed', error.type.name);
      throw AiRequestException(_explain(error));
    } on FormatException {
      throw const AiRequestException(
        'The backend returned invalid JSON. Nothing was saved.',
      );
    }
  }

  CloudAnalysisResult _validate(Map<String, dynamic> map) {
    final CloudAnalysisResult result = CloudAnalysisResult.fromJson(
      map,
      provider: id,
    );
    if (result.isEmpty) {
      throw const AiRequestException(
        'The backend returned no usable fields. Nothing was saved.',
      );
    }
    return result;
  }

  String _explain(DioException error) => switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.sendTimeout =>
      'The backend timed out. Nothing was uploaded beyond the request.',
    DioExceptionType.connectionError =>
      'Could not reach the backend. Check the URL and your connection.',
    _ => 'Cloud analysis failed. Nothing was saved.',
  };
}

class AiConfigurationException implements Exception {
  AiConfigurationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AiRequestException implements Exception {
  const AiRequestException(this.message);

  final String message;

  @override
  String toString() => message;
}
