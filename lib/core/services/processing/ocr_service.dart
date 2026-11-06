import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

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

/// On-device OCR with ML Kit's bundled Latin recogniser.
///
/// The bundled model is downloaded as part of the APK by the ML Kit SDK, so
/// there is no first-use network fetch. Latin script is included; Chinese,
/// Devanagari, Japanese, and Korean need extra Gradle dependencies that are not
/// shipped here (see README).
///
/// OCR returns text only. It is never presented as understanding the image.
class OcrService extends GetxService implements TextExtractor {
  OcrService(this._paths);

  final PathService _paths;

  bool _closed = false;

  @override
  Future<OcrResult> recognize(File imageFile) {
    if (_closed) throw StateError('OCR service was disposed.');
    final RootIsolateToken? token = RootIsolateToken.instance;
    if (token == null) {
      throw StateError('Start OCR from the application isolate.');
    }
    final String path = imageFile.path;
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
