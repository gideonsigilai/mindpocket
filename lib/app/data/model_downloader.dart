import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/model_info.dart';
import 'http_client_factory.dart';

class ModelDownloadProgress {
  const ModelDownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
  });

  final int receivedBytes;
  final int totalBytes;

  double? get fraction => totalBytes > 0
      ? (receivedBytes / totalBytes).clamp(0.0, 1.0).toDouble()
      : null;
}

class ModelDownloadTask {
  const ModelDownloadTask({
    required this.progress,
    required this.result,
    required this.cancelAction,
  });

  final Stream<ModelDownloadProgress> progress;
  final Future<File> result;
  final void Function() cancelAction;

  void cancel() => cancelAction();
}

class ModelDownloader {
  Future<void> cleanupStaleDownloads(String modelsDirectory) async {
    final root = await Directory(modelsDirectory).resolveSymbolicLinks();
    final stagingPath = p.join(root, '.loom-downloads');
    final stagingType = await FileSystemEntity.type(
      stagingPath,
      followLinks: false,
    );
    if (stagingType == FileSystemEntityType.notFound) return;
    if (stagingType != FileSystemEntityType.directory) {
      throw StateError('The model download staging path is not a directory.');
    }

    final stagingDirectory = Directory(stagingPath);
    final canonicalStaging = await stagingDirectory.resolveSymbolicLinks();
    if (!p.isWithin(root, canonicalStaging)) {
      throw StateError('The model download staging path resolves outside app storage.');
    }
    final partFileName = RegExp(r'^\d+\.part$');
    await for (final entity in Directory(canonicalStaging).list(
      followLinks: false,
    )) {
      if (entity is! File || !partFileName.hasMatch(p.basename(entity.path))) {
        continue;
      }
      if (await FileSystemEntity.type(entity.path, followLinks: false) !=
          FileSystemEntityType.file) {
        continue;
      }
      final target = await entity.resolveSymbolicLinks();
      if (!p.isWithin(canonicalStaging, target)) {
        throw StateError('A partial model file resolves outside app storage.');
      }
      await File(target).delete();
    }
  }

  Future<ModelDownloadTask> start({
    required ModelArtifact artifact,
    required String modelsDirectory,
    String? accessToken,
  }) async {
    final canonicalRoot = await Directory(modelsDirectory).resolveSymbolicLinks();
    final repositorySegments = artifact.repository.split('/');
    final fileSegments = p.posix.split(artifact.filename);
    if (repositorySegments.length != 2 ||
        repositorySegments.any((segment) => segment.isEmpty || segment == '.' || segment == '..') ||
        fileSegments.isEmpty ||
        fileSegments.any((segment) => segment.isEmpty || segment == '.' || segment == '..')) {
      throw const FormatException('The model file path is invalid.');
    }

    final proposedPath = p.joinAll([
      canonicalRoot,
      ...repositorySegments,
      ...fileSegments,
    ]);
    if (!p.isWithin(canonicalRoot, p.normalize(proposedPath))) {
      throw const FormatException('The model file is outside the models folder.');
    }

    final proposedParent = Directory(p.dirname(proposedPath));
    await proposedParent.create(recursive: true);
    final canonicalParent = await proposedParent.resolveSymbolicLinks();
    if (!p.isWithin(canonicalRoot, canonicalParent)) {
      throw const FormatException('The model folder resolves outside app storage.');
    }

    final destination = p.join(canonicalParent, p.basename(proposedPath));
    if (await File(destination).exists()) {
      throw StateError('This model file is already in the library.');
    }
    final stagingDirectory = Directory(p.join(canonicalRoot, '.loom-downloads'));
    await stagingDirectory.create(recursive: true);
    if (await FileSystemEntity.type(stagingDirectory.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw StateError('The model download staging path is not a directory.');
    }
    final canonicalStaging = await stagingDirectory.resolveSymbolicLinks();
    if (!p.isWithin(canonicalRoot, canonicalStaging)) {
      throw StateError('The model download staging path resolves outside app storage.');
    }
    final temporary = p.join(
      canonicalStaging,
      '${DateTime.now().microsecondsSinceEpoch}.part',
    );
    final uri = _downloadUri(artifact);

    final events = ReceivePort();
    final errors = ReceivePort();
    final exits = ReceivePort();
    final progress = StreamController<ModelDownloadProgress>();
    final result = Completer<File>();
    SendPort? cancelPort;
    var cancellationRequested = false;
    var portsClosed = false;

    void closePorts() {
      if (portsClosed) return;
      portsClosed = true;
      events.close();
      errors.close();
      exits.close();
      unawaited(progress.close());
    }

    void fail(Object error, [StackTrace? stackTrace]) {
      if (!result.isCompleted) result.completeError(error, stackTrace);
      closePorts();
    }

    final eventSubscription = events.listen((message) {
      if (message is! Map) return;
      switch (message['type']) {
        case 'ready':
          final port = message['cancelPort'];
          if (port is SendPort) {
            cancelPort = port;
            if (cancellationRequested) port.send('cancel');
          }
        case 'progress':
          final received = message['receivedBytes'];
          final total = message['totalBytes'];
          if (received is int && total is int && !progress.isClosed) {
            progress.add(
              ModelDownloadProgress(receivedBytes: received, totalBytes: total),
            );
          }
        case 'complete':
          final path = message['path'];
          if (path is String && !result.isCompleted) {
            result.complete(File(path));
            closePorts();
          }
        case 'error':
          final messageText = message['message'];
          fail(ModelDownloadException(
            messageText is String ? messageText : 'The model download failed.',
          ));
      }
    });
    final errorSubscription = errors.listen((message) {
      fail(ModelDownloadException('The model download worker stopped unexpectedly.'));
    });
    final exitSubscription = exits.listen((_) {
      if (!result.isCompleted) {
        fail(ModelDownloadException('The model download ended before completion.'));
      }
    });

    try {
      await Isolate.spawn<Map<String, Object?>>(
        _downloadWorker,
        {
          'events': events.sendPort,
          'url': uri.toString(),
          'accessToken': accessToken ?? '',
          'destination': destination,
          'temporary': temporary,
          'expectedBytes': artifact.sizeBytes,
          'expectedSha256': artifact.sha256 ?? '',
        },
        onError: errors.sendPort,
        onExit: exits.sendPort,
        errorsAreFatal: true,
        debugName: 'gguf-model-download',
      );
    } catch (error, stackTrace) {
      await eventSubscription.cancel();
      await errorSubscription.cancel();
      await exitSubscription.cancel();
      fail(ModelDownloadException('Could not start the model download.'), stackTrace);
      rethrow;
    }

    return ModelDownloadTask(
      progress: progress.stream,
      result: result.future,
      cancelAction: () {
        if (result.isCompleted) return;
        cancellationRequested = true;
        cancelPort?.send('cancel');
      },
    );
  }
}

class ModelDownloadException implements Exception {
  const ModelDownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

Uri _downloadUri(ModelArtifact artifact) {
  final segments = [
    ...artifact.repository.split('/'),
    'resolve',
    artifact.revision,
    ...p.posix.split(artifact.filename),
  ];
  final encodedPath = segments.map(Uri.encodeComponent).join('/');
  return Uri.parse('https://huggingface.co/$encodedPath?download=true');
}

void _downloadWorker(Map<String, Object?> arguments) async {
  final events = arguments['events']! as SendPort;
  final control = ReceivePort();
  final client = HttpClient()..findProxy = proxyForUri;
  HttpClientRequest? request;
  var cancelled = false;
  var ownsTemporaryFile = false;

  control.listen((message) {
    if (message == 'cancel') {
      cancelled = true;
      request?.abort();
      client.close(force: true);
    }
  });
  events.send({'type': 'ready', 'cancelPort': control.sendPort});

  final temporaryPath = arguments['temporary']! as String;
  final destinationPath = arguments['destination']! as String;
  final temporaryFile = File(temporaryPath);

  try {
    await temporaryFile.create(exclusive: true);
    ownsTemporaryFile = true;
    if (cancelled) throw const _DownloadCancelled();

    final downloadRequest = await client.getUrl(
      Uri.parse(arguments['url']! as String),
    );
    request = downloadRequest;
    downloadRequest.followRedirects = true;
    final accessToken = arguments['accessToken']! as String;
    if (accessToken.isNotEmpty) {
      downloadRequest.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $accessToken',
      );
    }
    final response = await downloadRequest.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw _DownloadFailure(
        'The model host returned HTTP ${response.statusCode}.',
      );
    }

    final expectedBytes = arguments['expectedBytes']! as int;
    final totalBytes = expectedBytes > 0 ? expectedBytes : response.contentLength;
    final expectedSha256 = arguments['expectedSha256']! as String;
    final digestSink = _DigestSink();
    final hashInput = expectedSha256.isNotEmpty
        ? sha256.startChunkedConversion(digestSink)
        : null;
    final output = await temporaryFile.open(mode: FileMode.write);
    var receivedBytes = 0;
    var lastReportedBytes = 0;
    var lastReportedAt = DateTime.now();
    final signature = <int>[];

    try {
      await for (final chunk in response) {
        if (cancelled) throw const _DownloadCancelled();
        if (signature.length < 4) {
          signature.addAll(chunk.take(4 - signature.length));
        }
        await output.writeFrom(chunk);
        hashInput?.add(chunk);
        receivedBytes += chunk.length;

        final now = DateTime.now();
        if (receivedBytes - lastReportedBytes >= 2 * 1024 * 1024 ||
            now.difference(lastReportedAt) >= const Duration(milliseconds: 250)) {
          events.send({
            'type': 'progress',
            'receivedBytes': receivedBytes,
            'totalBytes': totalBytes,
          });
          lastReportedBytes = receivedBytes;
          lastReportedAt = now;
        }
      }
      await output.flush();
    } finally {
      await output.close();
      hashInput?.close();
    }

    if (cancelled) throw const _DownloadCancelled();
    if (signature.length != 4 ||
        signature[0] != 0x47 ||
        signature[1] != 0x47 ||
        signature[2] != 0x55 ||
        signature[3] != 0x46) {
      throw const _DownloadFailure('The downloaded file is not a GGUF model.');
    }
    if (expectedBytes > 0 && receivedBytes != expectedBytes) {
      throw const _DownloadFailure('The downloaded model size did not match.');
    }
    if (expectedSha256.isNotEmpty && digestSink.digest?.toString() != expectedSha256) {
      throw const _DownloadFailure('The model checksum did not match.');
    }

    final destinationFile = File(destinationPath);
    if (await destinationFile.exists()) {
      throw const _DownloadFailure('A model file already exists at this path.');
    }
    await temporaryFile.rename(destinationPath);
    ownsTemporaryFile = false;
    events.send({'type': 'complete', 'path': destinationPath});
  } catch (error) {
    if (ownsTemporaryFile && await temporaryFile.exists()) {
      await temporaryFile.delete();
    }
    final message = switch (error) {
      _DownloadCancelled() => 'Download cancelled.',
      _DownloadFailure(:final message) => message,
      SocketException() || HandshakeException() =>
        'Could not connect to Hugging Face. Check the internet setting and try again.',
      FileSystemException() => 'Could not save the model in app storage.',
      _ => 'The model download failed (${error.runtimeType}).',
    };
    events.send({'type': 'error', 'message': message});
  } finally {
    control.close();
    client.close(force: true);
  }
}

class _DownloadFailure implements Exception {
  const _DownloadFailure(this.message);

  final String message;
}

class _DownloadCancelled implements Exception {
  const _DownloadCancelled();
}

class _DigestSink implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest value) => digest = value;

  @override
  void close() {}
}
