import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../constants/app_constants.dart';
import 'path_service.dart';

/// Details about an imported file, captured before any OCR/transcription runs
/// so a capture is never lost to a processing failure.
class StoredFile {
  const StoredFile({
    required this.relativePath,
    required this.storedName,
    required this.byteSize,
    required this.sha256,
    required this.mimeType,
  });

  final String relativePath;
  final String storedName;
  final int byteSize;
  final String sha256;
  final String? mimeType;
}

class ImportException implements Exception {
  ImportException(this.message, {this.recoverable = true});

  final String message;
  final bool recoverable;

  @override
  String toString() => message;
}

/// File-level operations: durable copies, hashing, thumbnails, deletion.
class FileStore {
  FileStore(this._paths);

  final PathService _paths;

  static const int thumbnailWidth = 720;

  /// Copies [source] into app-owned storage. The copy is written to a temp file
  /// first and moved into place only when complete, so a killed import can
  /// never leave a half-written attachment that the database points at.
  Future<StoredFile> importImage(File source, {String? extensionHint}) async {
    final String extension = _extensionFor(source.path, extensionHint);
    if (!AppConstants.imageExtensions.contains(extension)) {
      throw ImportException(
        'Unsupported file type "$extension". Images only (.png, .jpg, .webp, .heic).',
        recoverable: false,
      );
    }
    final String relative = _paths.relativeFor(
      AppConstants.imagesFolder,
      extension,
    );
    final String destination = await _paths.absolute(relative);
    final String sourcePath = source.path;
    final (int, String) metadata = await Isolate.run(
      () => _copyAndHash(sourcePath, destination, image: true),
      debugName: 'image-import',
    );
    return StoredFile(
      relativePath: relative,
      storedName: p.basename(destination),
      byteSize: metadata.$1,
      sha256: metadata.$2,
      mimeType: _mimeFor(extension),
    );
  }

  /// Writes a recording produced by the recorder at [tempPath] into permanent
  /// storage and returns its metadata.
  Future<StoredFile> persistAudio(
    String tempPath, {
    required int durationMs,
  }) async {
    final String extension = _extensionFor(tempPath, null);
    final String relative = _paths.relativeFor(
      AppConstants.audioFolder,
      extension,
    );
    final String destination = await _paths.absolute(relative);
    final (int, String) metadata = await Isolate.run(
      () => _copyAndHash(tempPath, destination, image: false),
      debugName: 'audio-import',
    );
    return StoredFile(
      relativePath: relative,
      storedName: p.basename(destination),
      byteSize: metadata.$1,
      sha256: metadata.$2,
      mimeType: _mimeFor(extension),
    );
  }

  /// Streams a SHA-256 digest without loading the whole file (model downloads).
  Future<String> hashFile(File file) {
    final String path = file.path;
    return Isolate.run(() => _hashFile(path), debugName: 'file-integrity');
  }

  /// Generates a bounded-size preview so the timeline never decodes a full
  /// 4000px screenshot for a 90px thumbnail.
  Future<String?> createThumbnail({
    required String relativePath,
    required int? width,
    required int? height,
  }) async {
    try {
      final String source = await _paths.absolute(relativePath);
      // Flutter's engine codecs are root-isolate APIs; decoding itself runs
      // on engine workers. Read directly from the file, not a second Dart copy.
      final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromFilePath(
        source,
      );
      final int targetWidth =
          (width != null && width > 0 && width < thumbnailWidth)
          ? width
          : thumbnailWidth;
      ui.ImageDescriptor? descriptor;
      ui.Codec? codec;
      ui.Image? image;
      final ByteData? png;
      try {
        descriptor = await ui.ImageDescriptor.encoded(buffer);
        codec = await descriptor.instantiateCodec(targetWidth: targetWidth);
        image = (await codec.getNextFrame()).image;
        png = await image.toByteData(format: ui.ImageByteFormat.png);
      } finally {
        image?.dispose();
        codec?.dispose();
        descriptor?.dispose();
        buffer.dispose();
      }
      if (png == null) return null;

      final String relative = _paths.relativeFor(
        AppConstants.thumbnailsFolder,
        '.png',
      );
      final String absolute = await _paths.absolute(relative);
      final TransferableTypedData encoded = TransferableTypedData.fromList(
        <Uint8List>[
          png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
        ],
      );
      await Isolate.run(() async {
        await Directory(p.dirname(absolute)).create(recursive: true);
        await File(absolute)
            .writeAsBytes(encoded.materialize().asUint8List(), flush: true);
      }, debugName: 'thumbnail-write');
      return relative;
    } catch (_) {
      // Thumbnails are an optimisation; the original remains displayable.
      return null;
    }
  }

  /// Returns intrinsic dimensions without keeping decoded pixels around.
  Future<(int?, int?)> imageSize(String relativePath) async {
    try {
      final String source = await _paths.absolute(relativePath);
      final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromFilePath(
        source,
      );
      ui.ImageDescriptor? descriptor;
      try {
        descriptor = await ui.ImageDescriptor.encoded(buffer);
        return (descriptor.width, descriptor.height);
      } finally {
        descriptor?.dispose();
        buffer.dispose();
      }
    } catch (_) {
      return (null, null);
    }
  }

  Future<void> deleteRelative(String? relativePath) async {
    if (relativePath == null || relativePath.isEmpty) return;
    final String path = await _paths.absolute(relativePath);
    await Isolate.run(() async {
      try {
        await File(path).delete();
      } on FileSystemException {
        // Best effort: an orphan sweep will collect leftovers.
      }
    }, debugName: 'attachment-delete');
  }

  /// Deletes files under app storage that no database row references.
  Future<int> sweepOrphans(Set<String> referenced) async {
    final String root = (await _paths.documents).path;
    final List<String> directories = <String>[
      (await _paths.imagesDir()).path,
      (await _paths.thumbnailsDir()).path,
      (await _paths.audioDir()).path,
    ];
    return Isolate.run(
      () => _sweepOrphans(root, directories, referenced),
      debugName: 'orphan-sweep',
    );
  }

  Future<int> directorySize(Directory dir) {
    final String path = dir.path;
    return Isolate.run(() => _directorySize(path), debugName: 'storage-size');
  }

  static String _extensionFor(String path, String? hint) {
    final String ext = p.extension(path).toLowerCase();
    if (ext.isNotEmpty && ext != '.tmp') return ext;
    if (hint != null && hint.isNotEmpty) {
      return hint.startsWith('.')
          ? hint.toLowerCase()
          : '.${hint.toLowerCase()}';
    }
    return '.jpg';
  }

  static String? _mimeFor(String extension) =>
      switch (extension.toLowerCase()) {
        '.png' => 'image/png',
        '.jpg' || '.jpeg' => 'image/jpeg',
        '.webp' => 'image/webp',
        '.heic' => 'image/heic',
        '.heif' => 'image/heif',
        '.wav' => 'audio/wav',
        '.m4a' => 'audio/mp4',
        '.aac' => 'audio/aac',
        '.flac' => 'audio/flac',
        '.opus' => 'audio/opus',
        _ => null,
      };
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

Future<(int, String)> _copyAndHash(
  String sourcePath,
  String destination, {
  required bool image,
}) async {
  final File source = File(sourcePath);
  if (!await source.exists()) {
    throw ImportException(
      image
          ? 'That file is no longer available. Pick or share it again.'
          : 'Recording could not be saved: the audio file is missing.',
    );
  }
  final int size = await source.length();
  if (size == 0) throw ImportException('That file is empty.');
  if (image && size > AppConstants.maxImageBytes) {
    throw ImportException('That image is larger than 30 MB.');
  }
  await Directory(p.dirname(destination)).create(recursive: true);
  final File part = File('$destination.part');
  final _DigestSink sink = _DigestSink();
  final ByteConversionSink hash = sha256.startChunkedConversion(sink);
  RandomAccessFile? output;
  int copied = 0;
  try {
    output = await part.open(mode: FileMode.write);
    await for (final List<int> chunk in source.openRead()) {
      copied += chunk.length;
      if (image && copied > AppConstants.maxImageBytes) {
        throw ImportException('That image is larger than 30 MB.');
      }
      hash.add(chunk);
      await output.writeFrom(chunk);
    }
    if (copied == 0) throw ImportException('That file is empty.');
    hash.close();
    await output.flush();
    await output.close();
    output = null;
    await part.rename(destination);
    return (copied, sink.value.toString());
  } catch (_) {
    await output?.close();
    if (await part.exists()) await part.delete();
    rethrow;
  }
}

Future<String> _hashFile(String path) async {
  final _DigestSink sink = _DigestSink();
  final ByteConversionSink hash = sha256.startChunkedConversion(sink);
  await for (final List<int> chunk in File(path).openRead()) {
    hash.add(chunk);
  }
  hash.close();
  return sink.value.toString();
}

Future<int> _sweepOrphans(
  String root,
  List<String> directories,
  Set<String> referenced,
) async {
  int removed = 0;
  for (final String path in directories) {
    final Directory directory = Directory(path);
    if (!await directory.exists()) continue;
    await for (final FileSystemEntity entity in directory.list(
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final String relative = p.posix.joinAll(
        p.split(p.relative(entity.path, from: root)),
      );
      if (referenced.contains(relative)) continue;
      try {
        await entity.delete();
        removed++;
      } on FileSystemException {
        // Skip locked files.
      }
    }
  }
  return removed;
}

Future<int> _directorySize(String path) async {
  final Directory directory = Directory(path);
  if (!await directory.exists()) return 0;
  int total = 0;
  await for (final FileSystemEntity entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is! File) continue;
    try {
      total += await entity.length();
    } on FileSystemException {
      // Ignore transient files.
    }
  }
  return total;
}
