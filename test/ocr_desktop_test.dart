import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mindpocket/core/services/processing/ocr_service.dart';
import 'package:mindpocket/core/services/storage/path_service.dart';
import 'package:path/path.dart' as p;

/// The Windows/Linux OCR path shells out to Tesseract and decodes its bytes
/// itself. Both failure modes are silent — a missing binary reported as "no
/// text", and UTF-8 text decoded with the ANSI code page — so they are pinned
/// against the real engine rather than a fake.
void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mindpocket_ocr_');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  OcrService service(String? executable) => OcrService(
    PathService(
      documentsDirectory: () async => temp,
      temporaryDirectory: () async => temp,
    ),
    tesseractExecutable: executable,
  );

  test('a missing engine is reported as unavailable, not as empty text', () async {
    final File image = File(p.join(temp.path, 'shot.png'));
    image.writeAsBytesSync(<int>[0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0]);
    await expectLater(
      service(p.join(temp.path, 'absent', 'tesseract')).recognize(image),
      throwsA(
        isA<OcrException>().having(
          (OcrException error) => error.code,
          'code',
          'ocr_unavailable',
        ),
      ),
    );
  }, skip: !(Platform.isWindows || Platform.isLinux));

  test('an empty image is rejected before the engine runs', () async {
    final File image = File(p.join(temp.path, 'empty.png'))
      ..writeAsBytesSync(const <int>[]);
    await expectLater(
      service(null).recognize(image),
      throwsA(isA<OcrException>()),
    );
  }, skip: !(Platform.isWindows || Platform.isLinux));

  test(
    'real Tesseract output keeps non-ASCII characters intact',
    () async {
      final String? engine = _findTesseract();
      if (engine == null) {
        markTestSkipped('Tesseract is not installed on this machine.');
        return;
      }
      // "Cafe Menu — KSh 1,250" rendered with a real font. The em dash is the
      // character Windows-1252 decoding destroys.
      final List<int> fixture = File(
        p.join('test', 'fixtures', 'ocr_text.png'),
      ).readAsBytesSync();
      final File image = File(p.join(temp.path, 'fixture.png'))
        ..writeAsBytesSync(fixture);

      final OcrResult result = await service(engine).recognize(image);
      expect(result.engine, contains('Tesseract'));
      expect(result.hasText, isTrue);
      expect(result.text, contains('Cafe Menu'));
      expect(result.text, contains('—'));
      expect(result.text, contains('1,250'));
      expect(result.text, isNot(contains('\uFFFD')));
      // The em dash is three UTF-8 bytes; a code-page round trip would have
      // produced three separate characters instead.
      expect(result.text, isNot(contains('â')));
      expect(utf8.encode(result.text).length, greaterThan(result.text.length));
    },
    skip: !(Platform.isWindows || Platform.isLinux),
  );
}

/// Mirrors the resolution order `windows.ps1` packages and `_tesseractExecutable`
/// probes, so the test finds the same bundled build a release would use.
String? _findTesseract() {
  final Map<String, String> environment = Platform.environment;
  final List<String> candidates = <String>[
    p.join(p.dirname(Platform.resolvedExecutable), 'tesseract', 'tesseract.exe'),
    p.join(
      environment['LOCALAPPDATA'] ?? '',
      'Programs',
      'Tesseract-OCR',
      'tesseract.exe',
    ),
    p.join(
      environment['ProgramFiles'] ?? '',
      'Tesseract-OCR',
      'tesseract.exe',
    ),
    '/usr/bin/tesseract',
  ];
  for (final String candidate in candidates) {
    if (candidate.isNotEmpty && File(candidate).existsSync()) return candidate;
  }
  return null;
}
