import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;

import '../../utils/logger.dart';
import '../storage/path_service.dart';

class OcrResult {
  const OcrResult({
    required this.text,
    required this.engine,
    required this.language,
    required this.hasText,
    this.confidence,
  });

  final String text;
  final String engine;
  final String language;
  final bool hasText;
  final double? confidence;
}

/// Contract the processing queue depends on, so job transitions can be tested
/// with a deterministic fake instead of native ML Kit.
abstract interface class TextExtractor {
  Future<OcrResult> recognize(File imageFile);
}

/// On-device OCR: ML Kit's bundled Latin recogniser on Android/iOS, Apple's
/// Vision framework on macOS, and a bundled Tesseract build on Windows/Linux.
///
/// The bundled mobile model ships inside the app, so there is no first-use
/// network fetch. OCR returns text only; it is never presented as understanding
/// the image.
class OcrService extends GetxService implements TextExtractor {
  OcrService(this._paths, {String? tesseractExecutable})
    : _tesseractOverride = tesseractExecutable;

  final PathService _paths;
  /// Test seam for the desktop engine path; production resolves the bundled
  /// build next to the executable so a release never depends on PATH.
  final String? _tesseractOverride;

  bool _closed = false;

  @override
  Future<OcrResult> recognize(File imageFile) {
    if (_closed) throw StateError('OCR service was disposed.');
    final String path = imageFile.path;
    if (Platform.isMacOS) {
      final RootIsolateToken? token = RootIsolateToken.instance;
      if (token == null) {
        throw StateError('Start OCR from the application isolate.');
      }
      return Isolate.run(
        () => _recognizeWithAppleVision(path, token),
        debugName: 'image-ocr',
      );
    }
    if (Platform.isWindows || Platform.isLinux) {
      final bool windows = Platform.isWindows;
      final String executable =
          _tesseractOverride ?? _tesseractExecutable(windows);
      final String? tessdata = _tesseractOverride == null
          ? _tesseractDataDirectory(windows)
          : _tessdataFor(_tesseractOverride);
      return Isolate.run(
        () => _recognizeWithTesseract(
          path,
          executable: executable,
          tessdataDirectory: tessdata,
        ),
        debugName: 'image-ocr',
      );
    }
    final RootIsolateToken? token = RootIsolateToken.instance;
    if (token == null) {
      throw StateError('Start OCR from the application isolate.');
    }
    return Isolate.run(
      () => _recognizeOnWorker(path, token),
      debugName: 'image-ocr',
    );
  }

  /// Stops accepting work; each worker releases its native recogniser.
  Future<void> shutdown() async {
    _closed = true;
  }

  Future<String> absolutePath(String relativePath) =>
      _paths.absolute(relativePath);
}

/// Windows releases ship Tesseract beside the executable; Linux distributions
/// depend on the system package. A missing binary is a real, reported failure.
String _tesseractExecutable(bool windows) {
  if (!windows) return 'tesseract';
  return p.join(
    p.dirname(Platform.resolvedExecutable),
    'tesseract',
    'tesseract.exe',
  );
}

String? _tesseractDataDirectory(bool windows) {
  if (!windows) return null;
  return _tessdataFor(_tesseractExecutable(windows));
}

/// Tesseract resolves `tessdata` beside its own binary unless told otherwise.
String? _tessdataFor(String executable) {
  final String path = p.join(p.dirname(executable), 'tessdata');
  return Directory(path).existsSync() ? path : null;
}

Future<OcrResult> _recognizeWithAppleVision(
  String path,
  RootIsolateToken token,
) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  await _assertReadableImage(path);
  try {
    final Map<String, Object?>? result =
        await const MethodChannel('mindpocket/ocr')
            .invokeMapMethod<String, Object?>('recognize', <String, Object?>{
              'path': path,
            });
    final String text = '${result?['text'] ?? ''}'.trim();
    return OcrResult(
      text: text,
      engine: 'Apple Vision text recognition',
      language: '${result?['language'] ?? 'und'}',
      hasText: text.isNotEmpty,
    );
  } on PlatformException catch (error) {
    logWarn('Apple Vision OCR failure', error.code);
    throw OcrException(
      'Text extraction failed on this Mac (${error.code}). The image is still saved.',
      code: error.code,
    );
  } on MissingPluginException {
    throw OcrException(
      'Text extraction is unavailable in this build. The image is still saved.',
      code: 'ocr_unavailable',
    );
  }
}

Future<OcrResult> _recognizeWithTesseract(
  String path, {
  required String executable,
  required String? tessdataDirectory,
}) async {
  await _assertReadableImage(path);
  final List<String> arguments = <String>[
    path,
    'stdout',
    '-l',
    'eng',
    '--psm',
    '3',
    if (tessdataDirectory != null) ...<String>[
      '--tessdata-dir',
      tessdataDirectory,
    ],
  ];
  final ProcessResult result;
  try {
    // Null encodings keep stdout/stderr as raw bytes: Dart would otherwise
    // decode with the Windows ANSI code page and corrupt non-ASCII text.
    result = await Process.run(
      executable,
      arguments,
      runInShell: false,
      stdoutEncoding: null,
      stderrEncoding: null,
    );
  } on ProcessException catch (error) {
    logWarn('Tesseract could not start', error.message);
    throw OcrException(
      'Text extraction needs the Tesseract OCR component, which is missing from this installation.',
      code: 'ocr_unavailable',
    );
  }
  if (result.exitCode != 0) {
    final String details = utf8
        .decode(result.stderr as List<int>, allowMalformed: true)
        .trim();
    logWarn('Tesseract failed', details);
    throw OcrException(
      details.isEmpty
          ? 'Text extraction failed (Tesseract exit ${result.exitCode}). The image is still saved.'
          : 'Text extraction failed: $details',
      code: 'ocr_failed',
    );
  }
  final String text = utf8
      .decode(result.stdout as List<int>, allowMalformed: true)
      .trim();
  return OcrResult(
    text: text,
    engine: 'Tesseract OCR (bundled English model)',
    language: 'eng',
    hasText: text.isNotEmpty,
  );
}

Future<void> _assertReadableImage(String path) async {
  final File file = File(path);
  if (!await file.exists()) throw OcrException('The image file is missing.');
  if (await file.length() == 0) throw OcrException('The image file is empty.');
}

Future<OcrResult> _recognizeOnWorker(
  String path,
  RootIsolateToken token,
) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  final File file = File(path);
  if (!await file.exists()) throw OcrException('The image file is missing.');
  if (await file.length() == 0) throw OcrException('The image file is empty.');
  final TextRecognizer recognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );
  try {
    final RecognizedText result = await recognizer.processImage(
      InputImage.fromFile(file),
    );
    final String text = result.text.trim();
    final String languages = result.blocks
        .expand((TextBlock block) => block.recognizedLanguages)
        .toSet()
        .take(3)
        .join(', ');
    return OcrResult(
      text: text,
      engine: 'ML Kit text recognition v2 (bundled Latin)',
      language: languages.isEmpty ? 'latin' : languages,
      hasText: text.isNotEmpty,
    );
  } on PlatformException catch (error) {
    logWarn('OCR platform failure', error.code);
    throw OcrException(switch (error.code) {
      'errorImage' =>
        'That image could not be decoded. Try another screenshot.',
      'errorFile' => 'The image file could not be read.',
      'errorLanguageNotInstalled' => 'The OCR language model is not installed.',
      _ =>
        'Text extraction failed on this device (${error.code}). The image is still saved.',
    }, code: error.code);
  } catch (error) {
    throw OcrException('Text extraction failed: $error');
  } finally {
    await recognizer.close();
  }
}

class OcrException implements Exception {
  OcrException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}
