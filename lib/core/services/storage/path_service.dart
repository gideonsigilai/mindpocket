import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../constants/app_constants.dart';

/// Single source of truth for app-owned file locations.
///
/// The database stores paths *relative* to [documentsPath] so the collection
/// survives iOS container moves and Android backups.
class PathService {
  PathService({
    Future<Directory> Function()? documentsDirectory,
    Future<Directory> Function()? temporaryDirectory,
  }) : _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory,
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final Future<Directory> Function() _documentsDirectory;
  final Future<Directory> Function() _temporaryDirectory;

  Directory? _documents;
  Directory? _temporary;

  Future<Directory> get documents async =>
      _documents ??= await _ensure(await _documentsDirectory(), 'mindpocket');

  Future<Directory> get temporary async =>
      _temporary ??= await _ensure(await _temporaryDirectory(), 'mindpocket');

  Future<Directory> imagesDir() => _sub(AppConstants.imagesFolder);
  Future<Directory> audioDir() => _sub(AppConstants.audioFolder);
  Future<Directory> thumbnailsDir() => _sub(AppConstants.thumbnailsFolder);
  Future<Directory> modelsDir() => _sub(AppConstants.modelsFolder);

  Future<Directory> _sub(String name) async {
    final Directory dir = Directory(p.join((await documents).path, name));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<Directory> _ensure(Directory base, String name) async {
    final Directory dir = Directory(p.join(base.path, name));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Resolves a stored relative path. Absolute legacy paths are honoured.
  Future<String> absolute(String relativePath) async {
    if (p.isAbsolute(relativePath)) return relativePath;
    return p.join((await documents).path, relativePath);
  }

  Future<File> file(String relativePath) async =>
      File(await absolute(relativePath));

  Future<bool> exists(String relativePath) async =>
      (await file(relativePath)).exists();

  /// Relative path for a new file with the given folder and extension.
  String relativeFor(String folder, String extension) {
    final String stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(
      36,
    );
    final String safe = extension.startsWith('.') ? extension : '.$extension';
    return p.posix.join(folder, '$stamp$safe');
  }
}
