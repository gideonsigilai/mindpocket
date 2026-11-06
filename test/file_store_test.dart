import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mindpocket/core/services/storage/file_store.dart';
import 'package:mindpocket/core/services/storage/path_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'generated previews bound decoding size and preserve image proportions',
    () async {
      final Directory directory = await Directory.systemTemp.createTemp(
        'mindpocket_preview_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final PathService paths = PathService(
        documentsDirectory: () async => directory,
      );
      final FileStore files = FileStore(paths);
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      ui.Canvas(recorder)
          .drawColor(const ui.Color(0xFF457C63), ui.BlendMode.src);
      final ui.Picture picture = recorder.endRecording();
      final ui.Image original = await picture.toImage(1200, 1600);
      final bytes = (await original.toByteData(
        format: ui.ImageByteFormat.png,
      ))!;
      original.dispose();
      picture.dispose();
      final File source = File('${directory.path}/large.png');
      await source.writeAsBytes(bytes.buffer.asUint8List());
      final StoredFile imported = await files.importImage(source);
      final String? preview = await files.createThumbnail(
        relativePath: imported.relativePath,
        width: 1200,
        height: 1600,
      );
      expect(preview, isNotNull);
      final ui.Codec codec = await ui.instantiateImageCodec(
        await (await paths.file(preview!)).readAsBytes(),
      );
      final ui.FrameInfo frame = await codec.getNextFrame();
      expect(frame.image.width, 720);
      expect(frame.image.height, 960);
      frame.image.dispose();
      codec.dispose();
    },
  );
}
