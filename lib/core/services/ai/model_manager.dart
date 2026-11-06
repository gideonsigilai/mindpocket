import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import '../../utils/format.dart';
import '../../utils/logger.dart';
import '../storage/file_store.dart';
import '../storage/path_service.dart';
import '../storage/preferences_service.dart';
import 'model_catalog.dart';

enum ModelStatus { notDownloaded, downloading, ready, corrupt, verifying }

/// Download, verification, and removal of offline ASR models.
///
/// Downloads go to a `.part` file, are verified against the published SHA-256,
/// and only then moved into place, so a partial or tampered download can never
/// be mistaken for a usable model.
class ModelManager extends GetxService {
  ModelManager(this._paths, this._files, this._prefs);

  final PathService _paths;
  final FileStore _files;
  final PreferencesService _prefs;
  final Dio _dio = Dio();

  static const String _activeModelKey = 'active_asr_model';
  static const String _readySuffix = '.verified';

  final RxMap<String, ModelStatus> _statuses = <String, ModelStatus>{}.obs;
  final RxMap<String, double> _progress = <String, double>{}.obs;
  final RxString _activeModelId = ''.obs;
  final RxBool _busy = false.obs;

  CancelToken? _cancelToken;

  Map<String, ModelStatus> get statuses => _statuses;
  Map<String, double> get progress => _progress;
  String get activeModelId => _activeModelId.value;
  bool get isBusy => _busy.value;

  ModelSpec? get activeModel => modelById(_activeModelId.value);

  Future<ModelManager> init() async {
    _activeModelId.value = _prefs.readString(_activeModelKey, whisperTinyEn.id);
    for (final ModelSpec spec in modelCatalog) {
      _statuses[spec.id] = await _inspect(spec);
    }
    return this;
  }

  bool isReady(String modelId) => _statuses[modelId] == ModelStatus.ready;

  Future<ModelStatus> _inspect(ModelSpec spec) async {
    final Directory dir = await _modelDir(spec);
    for (final ModelFile file in spec.files) {
      final File target = File(p.join(dir.path, file.name));
      if (!await target.exists() || await target.length() != file.sizeBytes) {
        return ModelStatus.notDownloaded;
      }
    }
    final File marker = File(p.join(dir.path, _readySuffix));
    if (!await marker.exists()) return ModelStatus.notDownloaded;
    return ModelStatus.ready;
  }

  Future<Directory> _modelDir(ModelSpec spec) async {
    final Directory root = await _paths.modelsDir();
    final Directory dir = Directory(p.join(root.path, spec.id));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Absolute paths required by the native recogniser.
  Future<ModelPaths> pathsFor(ModelSpec spec) async {
    final Directory dir = await _modelDir(spec);
    return ModelPaths(
      directory: dir.path,
      encoder: p.join(dir.path, spec.files[0].name),
      decoder: p.join(dir.path, spec.files[1].name),
      tokens: p.join(dir.path, spec.files[2].name),
    );
  }

  Future<bool> ensureFreeSpace(ModelSpec spec) async {
    try {
      final Directory root = await _paths.modelsDir();
      // path_provider has no portable free-space API; DiskSpace via `stat` is
      // Android-only, so use the platform channel-free heuristic: write is
      // attempted and a FileSystemException is surfaced by [download].
      await root.stat();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  /// Downloads every file for [spec], reports byte-weighted progress, verifies
  /// hashes, and marks the model ready. Returns null on success, or a message.
  Future<String?> download(ModelSpec spec, {bool force = false}) async {
    if (_busy.value) return 'Another download is already running.';
    if (!force && await _inspect(spec) == ModelStatus.ready) {
      _statuses[spec.id] = ModelStatus.ready;
      return null;
    }
    _busy.value = true;
    _cancelToken = CancelToken();
    _statuses[spec.id] = ModelStatus.downloading;
    _progress[spec.id] = 0;
    try {
      final Directory dir = await _modelDir(spec);
      final int total = spec.totalBytes;
      int completedBytes = 0;

      for (final ModelFile file in spec.files) {
        final File target = File(p.join(dir.path, file.name));
        final File part = File('${target.path}.part');
        if (await target.exists() && await target.length() == file.sizeBytes) {
          completedBytes += file.sizeBytes;
          _progress[spec.id] = completedBytes / total;
          continue;
        }
        if (await part.exists()) await part.delete();

        int received = 0;
        int lastReportMillis = 0;
        await _dio.download(
          file.url,
          part.path,
          cancelToken: _cancelToken,
          deleteOnError: true,
          options: Options(receiveTimeout: const Duration(minutes: 5)),
          onReceiveProgress: (int count, int contentLength) {
            received = count;
            final int now = DateTime.now().millisecondsSinceEpoch;
            // Throttle UI updates; progress maps are reactive.
            if (now - lastReportMillis > 80) {
              lastReportMillis = now;
              _progress[spec.id] = ((completedBytes + count) / total).clamp(
                0.0,
                1.0,
              );
            }
          },
        );

        if (received != file.sizeBytes) {
          // Servers may report -1 for length; only trust the file on disk.
          final int onDisk = await part.length();
          if (onDisk != file.sizeBytes) {
            await part.delete();
            throw ModelDownloadException(
              '${file.name} arrived with ${Format.bytes(onDisk)} instead of '
              '${Format.bytes(file.sizeBytes)}. Try again.',
            );
          }
        }

        _statuses[spec.id] = ModelStatus.verifying;
        final String digest = await _files.hashFile(part);
        if (digest.toLowerCase() != file.sha256.toLowerCase()) {
          await part.delete();
          throw ModelDownloadException(
            'Integrity check failed for ${file.name}. The download may be '
            'corrupted or intercepted; it was discarded.',
          );
        }
        if (await target.exists()) await target.delete();
        await part.rename(target.path);
        completedBytes += file.sizeBytes;
        _progress[spec.id] = (completedBytes / total).clamp(0.0, 1.0);
      }

      await File(p.join(dir.path, _readySuffix)).writeAsString(
        '${spec.version}\n${DateTime.now().toIso8601String()}\n',
        flush: true,
      );
      _statuses[spec.id] = ModelStatus.ready;
      _progress[spec.id] = 1;
      if (_activeModelId.value.isEmpty) await setActive(spec.id);
      logDebug('Model ready: ${spec.id}');
      return null;
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) {
        _statuses[spec.id] = ModelStatus.notDownloaded;
        _progress.remove(spec.id);
        return 'Download canceled. Your notes are untouched.';
      }
      _statuses[spec.id] = ModelStatus.notDownloaded;
      _progress.remove(spec.id);
      logWarn('Model download failed', error.message);
      return _explainDio(error);
    } on ModelDownloadException catch (error) {
      _statuses[spec.id] = ModelStatus.corrupt;
      _progress.remove(spec.id);
      return error.message;
    } catch (error) {
      _statuses[spec.id] = ModelStatus.notDownloaded;
      _progress.remove(spec.id);
      logError('Model download crashed', error);
      return 'Download failed: $error';
    } finally {
      _busy.value = false;
      _cancelToken = null;
    }
  }

  String _explainDio(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'The model server timed out. Check your connection and retry.';
      case DioExceptionType.connectionError:
        return 'No connection to the model server. Connect to Wi-Fi and retry.';
      case DioExceptionType.badResponse:
        final int? status = error.response?.statusCode;
        return 'The model server returned ${status ?? 'an error'}. Try again later.';
      default:
        return 'Download failed. Check your connection and retry.';
    }
  }

  void cancelDownload() {
    _cancelToken?.cancel('user');
  }

  Future<void> setActive(String modelId) async {
    _activeModelId.value = modelId;
    await _prefs.write(_activeModelKey, modelId);
  }

  /// Removes a model directory. Model assets are never shared with memories, so
  /// deleting one never touches captures.
  Future<void> remove(ModelSpec spec) async {
    final Directory dir = await _modelDir(spec);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    _statuses[spec.id] = ModelStatus.notDownloaded;
    _progress.remove(spec.id);
    if (_activeModelId.value == spec.id) {
      _activeModelId.value = '';
      await _prefs.write(_activeModelKey, '');
    }
  }

  Future<int> diskUsage() async {
    final Directory root = await _paths.modelsDir();
    return _files.directorySize(root);
  }
}

class ModelPaths {
  const ModelPaths({
    required this.directory,
    required this.encoder,
    required this.decoder,
    required this.tokens,
  });

  final String directory;
  final String encoder;
  final String decoder;
  final String tokens;
}

class ModelDownloadException implements Exception {
  ModelDownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}
