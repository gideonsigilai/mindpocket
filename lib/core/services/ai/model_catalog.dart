/// Verified model catalogue.
///
/// Every entry is a real download with a published size and SHA-256 taken from
/// the Hugging Face API, so integrity can be checked before the file is used.
/// Licences are recorded because the models ship to end users.
library;

class ModelFile {
  const ModelFile({
    required this.name,
    required this.url,
    required this.sizeBytes,
    required this.sha256,
    this.required = true,
  });

  /// File name on disk inside the model directory.
  final String name;
  final String url;
  final int sizeBytes;
  final String sha256;
  final bool required;
}

class ModelSpec {
  const ModelSpec({
    required this.id,
    required this.displayName,
    required this.version,
    required this.language,
    required this.description,
    required this.license,
    required this.licenseUrl,
    required this.files,
    required this.sampleRate,
    this.requiresNetworkOnFirstUse = true,
  });

  final String id;
  final String displayName;
  final String version;
  final String language;
  final String description;
  final String license;
  final String licenseUrl;
  final List<ModelFile> files;
  final int sampleRate;
  final bool requiresNetworkOnFirstUse;

  int get totalBytes =>
      files.fold<int>(0, (int sum, ModelFile file) => sum + file.sizeBytes);

  /// Rough free-space requirement: download + unpacked copy plus headroom.
  int get requiredFreeBytes => (totalBytes * 2.2).round();

  ModelFile file(String name) =>
      files.firstWhere((ModelFile file) => file.name == name);
}

/// Whisper tiny.en, quantised int8 encoder+decoder, converted for sherpa-onnx.
/// English only; selected as the smallest usable offline model (~103 MB).
const ModelSpec whisperTinyEn = ModelSpec(
  id: 'whisper-tiny-en-int8',
  displayName: 'Whisper Tiny (English)',
  version: 'sherpa-onnx-whisper-tiny.en@2024-03',
  language: 'English',
  description:
      'Offline speech recognition. Fast and small; accurate for clear speech, '
      'weaker with accents, noise, and technical vocabulary.',
  license: 'MIT (model), ONNX conversion by k2-fsa/sherpa-onnx',
  licenseUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny.en',
  sampleRate: 16000,
  files: <ModelFile>[
    ModelFile(
      name: 'tiny.en-encoder.int8.onnx',
      url: 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny.en/resolve/main/tiny.en-encoder.int8.onnx',
      sizeBytes: 12937772,
      sha256:
          '0ce578b827c94a961aacb8fa14b02f096504b337e5c94be37c36238cbe3e8bc6',
    ),
    ModelFile(
      name: 'tiny.en-decoder.int8.onnx',
      url: 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny.en/resolve/main/tiny.en-decoder.int8.onnx',
      sizeBytes: 89853865,
      sha256:
          '06c0e6ff6348d427e51839219d1c886c18cfdf411e629e33f5e1679bff9c1527',
    ),
    ModelFile(
      name: 'tiny.en-tokens.txt',
      url: 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny.en/resolve/main/tiny.en-tokens.txt',
      sizeBytes: 835554,
      sha256:
          '306cd27f03c1a714eca7108e03d66b7dc042abe8c258b44c199a7ed9838dd930',
    ),
  ],
);

/// Multilingual Whisper Tiny for non-English recordings. Offered as an optional
/// extra so English users do not pay the download cost twice.
const ModelSpec whisperTinyMulti = ModelSpec(
  id: 'whisper-tiny-int8',
  displayName: 'Whisper Tiny (99 languages)',
  version: 'sherpa-onnx-whisper-tiny@2024-03',
  language: 'Multilingual',
  description:
      'Same speed as the English model but handles other languages, including '
      'code-switching. Slightly less accurate for English-only speech.',
  license: 'MIT (model), ONNX conversion by k2-fsa/sherpa-onnx',
  licenseUrl: 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny',
  sampleRate: 16000,
  files: <ModelFile>[
    ModelFile(
      name: 'tiny-encoder.int8.onnx',
      url: 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny/resolve/main/tiny-encoder.int8.onnx',
      sizeBytes: 12937772,
      sha256:
          'd24fb083ae3b1041fc24e97971d60e280c9342201fbb67b0ab428a8b4a51a434',
    ),
    ModelFile(
      name: 'tiny-decoder.int8.onnx',
      url: 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny/resolve/main/tiny-decoder.int8.onnx',
      sizeBytes: 89855401,
      sha256:
          'd2fece8dd42771f1df975c6c0445770d0c292bf7547c2cae04a6c0cc57540925',
    ),
    ModelFile(
      name: 'tiny-tokens.txt',
      url: 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny/resolve/main/tiny-tokens.txt',
      sizeBytes: 816730,
      sha256:
          'b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126',
    ),
  ],
);

const List<ModelSpec> modelCatalog = <ModelSpec>[
  whisperTinyEn,
  whisperTinyMulti,
];

ModelSpec? modelById(String id) {
  for (final ModelSpec spec in modelCatalog) {
    if (spec.id == id) return spec;
  }
  return null;
}
