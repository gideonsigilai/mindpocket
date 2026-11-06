import 'dart:io';

import 'package:path/path.dart' as p;

/// Minimal RIFF/WAVE reader for 16-bit PCM files produced by the recorder.
///
/// sherpa-onnx expects 16 kHz mono float32 samples. The recorder writes WAV at
/// a fixed rate we request up front, but files can still differ (device
/// fallbacks), so rates are resampled here instead of failing.
class WavData {
  const WavData({required this.samples, required this.sampleRate});

  final List<double> samples;
  final int sampleRate;
}

class WavReader {
  /// Reads a PCM16 WAV file. Throws [WavFormatException] for unsupported
  /// encodings (float WAV, compressed formats) so the UI can explain itself.
  static WavData readFileSync(File file) {
    final List<int> bytes = file.readAsBytesSync();
    final ByteDataView view = ByteDataView(bytes);
    if (view.length < 44) {
      throw const WavFormatException('Audio file is too short to read.');
    }
    if (view.ascii(0, 4) != 'RIFF' || view.ascii(8, 4) != 'WAVE') {
      throw const WavFormatException('Audio is not a WAV file.');
    }

    int offset = 12;
    int? sampleRate;
    int? channels;
    int? bitsPerSample;
    int? audioFormat;
    int? dataOffset;
    int? dataLength;

    while (offset + 8 <= view.length) {
      final String chunkId = view.ascii(offset, 4);
      final int chunkSize = view.uint32(offset + 4);
      final int body = offset + 8;
      if (chunkId == 'fmt ' && body + 16 <= view.length) {
        audioFormat = view.uint16(body);
        channels = view.uint16(body + 2);
        sampleRate = view.uint32(body + 4);
        bitsPerSample = view.uint16(body + 14);
      } else if (chunkId == 'data') {
        dataOffset = body;
        dataLength = chunkSize.clamp(0, view.length - body);
        break;
      }
      offset = body + chunkSize + (chunkSize.isOdd ? 1 : 0);
    }

    if (audioFormat == null || sampleRate == null || dataOffset == null) {
      throw const WavFormatException(
        'Audio file is missing a readable data chunk.',
      );
    }
    if (audioFormat != 1 || bitsPerSample != 16) {
      throw const WavFormatException(
        'Only 16-bit PCM recordings can be transcribed locally.',
      );
    }
    final int channelCount = channels ?? 1;
    final int frameCount = (dataLength ?? 0) ~/ (2 * channelCount);
    final List<double> samples = List<double>.filled(
      frameCount,
      0,
      growable: false,
    );
    for (int i = 0; i < frameCount; i++) {
      int mixed = 0;
      for (int c = 0; c < channelCount; c++) {
        mixed += view.int16(dataOffset + (i * channelCount + c) * 2);
      }
      samples[i] = (mixed / channelCount) / 32768.0;
    }
    return WavData(samples: samples, sampleRate: sampleRate);
  }

  /// Linear resampler. Good enough for speech at 8–48 kHz; the model uses
  /// 16 kHz so ratios stay close to 1.
  static List<double> resample(List<double> input, int from, int to) {
    if (from == to || input.isEmpty) return input;
    final int outputLength = (input.length * to / from).floor();
    final List<double> output = List<double>.filled(
      outputLength,
      0,
      growable: false,
    );
    final double ratio = from / to;
    for (int i = 0; i < outputLength; i++) {
      final double position = i * ratio;
      final int index = position.floor();
      final double fraction = position - index;
      final double a = input[index.clamp(0, input.length - 1)];
      final double b = input[(index + 1).clamp(0, input.length - 1)];
      output[i] = a + (b - a) * fraction;
    }
    return output;
  }
}

class WavFormatException implements Exception {
  const WavFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ByteDataView {
  ByteDataView(this.bytes);

  final List<int> bytes;

  int get length => bytes.length;

  int uint16(int offset) => bytes[offset] | (bytes[offset + 1] << 8);

  int uint32(int offset) =>
      bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);

  int int16(int offset) {
    final int value = uint16(offset);
    return value >= 0x8000 ? value - 0x10000 : value;
  }

  String ascii(int offset, int length) =>
      String.fromCharCodes(bytes.sublist(offset, offset + length));
}

String relativeAudioName(String absolutePath) => p.basename(absolutePath);
