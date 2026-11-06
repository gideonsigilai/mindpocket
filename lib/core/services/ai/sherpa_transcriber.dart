import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../utils/wav.dart';
import 'model_catalog.dart';
import 'model_manager.dart';

/// Result of one offline transcription run.
class TranscriptResult {
  const TranscriptResult({
    required this.text,
    required this.engine,
    required this.language,
  });

  final String text;
  final String engine;
  final String language;
}

/// Message handed to the worker isolate. Plain data only: FFI handles are not
/// sendable, so the isolate opens the model itself.
class TranscriptionRequest {
  const TranscriptionRequest({
    required this.wavPath,
    required this.encoderPath,
    required this.decoderPath,
    required this.tokensPath,
    required this.language,
    required this.engineLabel,
    this.threads = 2,
  });

  final String wavPath;
  final String encoderPath;
  final String decoderPath;
  final String tokensPath;
  final String language;
  final String engineLabel;
  final int threads;
}

/// Real on-device Whisper inference via sherpa-onnx.
///
/// Decoding a minute of audio can take several seconds, so this runs in a
/// background isolate through `compute(transcribeInIsolate, request)`. There is
/// no network path here at all: missing model files raise an error rather than
/// silently falling back to a cloud recogniser.
abstract final class SherpaTranscriber {
  static TranscriptResult run(TranscriptionRequest request) {
    final File wavFile = File(request.wavPath);
    if (!wavFile.existsSync()) {
      throw TranscriptionException('The recording file is missing.');
    }
    for (final String path in <String>[
      request.encoderPath,
      request.decoderPath,
      request.tokensPath,
    ]) {
      if (!File(path).existsSync()) {
        throw TranscriptionException(
          'Speech model files are missing. Download the model in Settings → Models.',
        );
      }
    }

    final WavData wave;
    try {
      wave = WavReader.readFileSync(wavFile);
    } on WavFormatException catch (error) {
      throw TranscriptionException(error.message);
    }
    if (wave.samples.isEmpty) {
      throw TranscriptionException('The recording contains no audio.');
    }
    final List<double> samples = WavReader.resample(
      wave.samples,
      wave.sampleRate,
      16000,
    );

    // Each isolate owns its FFI binding state.
    sherpa.initBindings();

    sherpa.OfflineRecognizer? recognizer;
    sherpa.OfflineStream? stream;
    try {
      recognizer = sherpa.OfflineRecognizer(
        sherpa.OfflineRecognizerConfig(
          model: sherpa.OfflineModelConfig(
            whisper: sherpa.OfflineWhisperModelConfig(
              encoder: request.encoderPath,
              decoder: request.decoderPath,
              language: request.language,
              task: 'transcribe',
            ),
            tokens: request.tokensPath,
            modelType: 'whisper',
            numThreads: request.threads,
            debug: false,
            provider: 'cpu',
          ),
        ),
      );
      stream = recognizer.createStream();
      stream.acceptWaveform(
        samples: Float32List.fromList(samples),
        sampleRate: 16000,
      );
      recognizer.decode(stream);
      final sherpa.OfflineRecognizerResult result = recognizer.getResult(
        stream,
      );
      final String text = result.text.trim();
      if (text.isEmpty) {
        throw TranscriptionException(
          'No speech was recognised. The audio may be silent or too noisy.',
        );
      }
      return TranscriptResult(
        text: text,
        engine: request.engineLabel,
        language: request.language.isEmpty ? 'auto' : request.language,
      );
    } on TranscriptionException {
      rethrow;
    } catch (error) {
      throw TranscriptionException('On-device transcription failed: $error');
    } finally {
      stream?.free();
      recognizer?.free();
    }
  }
}

class TranscriptionException implements Exception {
  TranscriptionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Re-hashes model files away from the UI isolate, streaming bounded chunks.
abstract final class ModelIntegrity {
  static Future<bool> verify(ModelPaths paths, ModelSpec spec) =>
      Isolate.run(() => _verify(paths, spec), debugName: 'model-integrity');

  static Future<bool> _verify(ModelPaths paths, ModelSpec spec) async {
    for (final ModelFile file in spec.files) {
      final String candidate =
          <String>[paths.encoder, paths.decoder, paths.tokens].firstWhere(
            (String value) => value.endsWith(file.name),
            orElse: () => '',
          );
      if (candidate.isEmpty) return false;
      final String digest = await _digest(candidate);
      if (digest.toLowerCase() != file.sha256.toLowerCase()) return false;
    }
    return true;
  }

  static Future<String> _digest(String path) async {
    final File file = File(path);
    if (!await file.exists()) return '';
    final _Sink sink = _Sink();
    final ByteConversionSink input = sha256.startChunkedConversion(sink);
    await for (final List<int> chunk in file.openRead()) {
      input.add(chunk);
    }
    input.close();
    return sink.value.toString();
  }
}

class _Sink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// Top-level entry point for `compute`.
TranscriptResult transcribeInIsolate(TranscriptionRequest request) =>
    SherpaTranscriber.run(request);

/// Builds the isolate request for an installed model.
TranscriptionRequest buildTranscriptionRequest({
  required String wavPath,
  required ModelSpec spec,
  required ModelPaths paths,
}) => TranscriptionRequest(
  wavPath: wavPath,
  encoderPath: paths.encoder,
  decoderPath: paths.decoder,
  tokensPath: paths.tokens,
  // Empty language lets Whisper auto-detect; the English model is fixed to
  // `en` because it only knows English tokens.
  language: spec.id == 'whisper-tiny-en-int8' ? 'en' : '',
  engineLabel: 'sherpa-onnx · ${spec.displayName}',
);
