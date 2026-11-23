import 'dart:convert';

import 'package:path/path.dart' as p;

class ModelSearchPage {
  const ModelSearchPage({required this.models, this.nextCursor});

  final List<AvailableModel> models;
  final String? nextCursor;
}

class AvailableModel {
  const AvailableModel({
    required this.id,
    required this.downloads,
    required this.likes,
    required this.tags,
    required this.isGated,
  });

  final String id;
  final int downloads;
  final int likes;
  final List<String> tags;
  final bool isGated;

  String get author => id.split('/').first;
  String get name => id.split('/').last;
}

class ModelArtifact {
  const ModelArtifact({
    required this.repository,
    required this.revision,
    required this.filename,
    required this.sizeBytes,
    required this.isGated,
    this.sha256,
  });

  final String repository;
  final String revision;
  final String filename;
  final int sizeBytes;
  final String? sha256;
  final bool isGated;

  String get name => p.posix.basename(filename);
}

ModelSearchPage parseModelSearchResponse(
  String body, {
  String? nextCursor,
}) {
  final decoded = jsonDecode(body);
  if (decoded is! List) {
    throw const FormatException('The model search response was not a list.');
  }

  final models = <AvailableModel>[];
  for (final item in decoded) {
    if (item is! Map<String, dynamic>) continue;
    final id = item['id'];
    if (id is! String || !isSafeModelRepositoryId(id)) continue;

    final tags = item['tags'] is List
        ? (item['tags'] as List).whereType<String>().toList(growable: false)
        : const <String>[];
    if (!tags.contains('gguf')) continue;

    models.add(
      AvailableModel(
        id: id,
        downloads: _readInt(item['downloads']),
        likes: _readInt(item['likes']),
        tags: tags,
        isGated: item['gated'] != null && item['gated'] != false,
      ),
    );
  }

  return ModelSearchPage(models: models, nextCursor: nextCursor);
}

List<ModelArtifact> parseModelArtifacts(
  String body, {
  required String repository,
}) {
  if (!isSafeModelRepositoryId(repository)) {
    throw const FormatException('Invalid model repository identifier.');
  }
  final decoded = jsonDecode(body);

  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('The model details response was invalid.');
  }

  final responseId = decoded['id'] ?? decoded['modelId'];
  if (responseId is String && responseId != repository) {
    throw const FormatException('The model details did not match the request.');
  }

  final revisionValue = decoded['sha'];
  final revision = revisionValue is String &&
          RegExp(r'^[a-fA-F0-9]{7,64}$').hasMatch(revisionValue)
      ? revisionValue
      : 'main';
  final isGated = decoded['gated'] != null && decoded['gated'] != false;
  final siblings = decoded['siblings'];
  if (siblings is! List) {
    throw const FormatException('The model repository did not include files.');
  }

  final artifacts = <ModelArtifact>[];
  for (final sibling in siblings) {
    if (sibling is! Map<String, dynamic>) continue;
    final filename = sibling['rfilename'];
    if (filename is! String || !_isSafeModelFilename(filename)) continue;
    if (p.posix.extension(filename).toLowerCase() != '.gguf') continue;

    final lfs = sibling['lfs'];
    final lfsMap = lfs is Map<String, dynamic> ? lfs : const <String, dynamic>{};
    final shaValue = lfsMap['sha256'];
    final sha256 = shaValue is String && RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(shaValue)
        ? shaValue.toLowerCase()
        : null;
    artifacts.add(
      ModelArtifact(
        repository: repository,
        revision: revision,
        filename: filename,
        sizeBytes: _readInt(sibling['size'] ?? lfsMap['size']),
        sha256: sha256,
        isGated: isGated,
      ),
    );
  }

  artifacts.sort((left, right) => left.sizeBytes.compareTo(right.sizeBytes));
  return artifacts;
}

String? parseNextCursor(String? linkHeader) {
  if (linkHeader == null || linkHeader.isEmpty) return null;

  for (final link in linkHeader.split(',')) {
    final match = RegExp(r'<([^>]+)>\s*;\s*rel="?next"?').firstMatch(link);
    if (match == null) continue;
    return Uri.tryParse(match.group(1)!)?.queryParameters['cursor'];
  }
  return null;
}

String formatByteSize(int bytes) {
  if (bytes <= 0) return 'Unknown size';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unitIndex = 0;
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex++;
  }
  final decimals = unitIndex >= 2 ? 1 : 0;
  return '${size.toStringAsFixed(decimals)} ${units[unitIndex]}';
}

int _readInt(Object? value) => value is num && value.isFinite ? value.toInt() : 0;

bool isSafeModelRepositoryId(String value) =>
    RegExp(r'^[\w.-]+/[\w.-]+$').hasMatch(value) &&
    !value.split('/').any((segment) => segment == '.' || segment == '..');

bool _isSafeModelFilename(String value) {
  if (value.isEmpty || value.startsWith('/') || value.contains('\\')) return false;
  final invalidSegment = RegExp(r'[<>:"|?*\u0000-\u001f]');
  final segments = p.posix.split(value);
  return segments.every(
    (segment) =>
        segment.isNotEmpty &&
        segment != '.' &&
        segment != '..' &&
        !invalidSegment.hasMatch(segment),
  );
}
