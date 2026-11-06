import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mindpocket/core/services/screenshots/screenshot_source.dart';

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('mindpocket_desktop_shots_');
  });

  tearDown(() async {
    if (await home.exists()) await home.delete(recursive: true);
  });

  Directory folder(String relative) =>
      Directory('${home.path}${Platform.pathSeparator}$relative')
        ..createSync(recursive: true);

  File screenshot(String relative, {int seed = 0}) {
    final List<int> png = <int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
      ...List<int>.filled(64 + seed, seed),
    ];
    return File('${home.path}${Platform.pathSeparator}$relative')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png);
  }

  ScreenshotSource linux() => ScreenshotSource.desktop(
    operatingSystem: 'linux',
    environment: <String, String>{
      'HOME': home.path,
      'XDG_PICTURES_DIR': '${home.path}/Pictures',
      'XDG_DESKTOP_DIR': '${home.path}/Desktop',
    },
  );

  ScreenshotSource windows() => ScreenshotSource.desktop(
    operatingSystem: 'windows',
    environment: <String, String>{
      'USERPROFILE': home.path,
      'PICTURES': '${home.path}\\Pictures',
    },
  );

  ScreenshotSource macos() => ScreenshotSource.desktop(
    operatingSystem: 'macos',
    environment: <String, String>{'HOME': home.path},
    macCaptureDirectory: '${home.path}/Screenshots',
  );

  test('a missing screenshots folder is an empty library, not a denial', () async {
    folder('Pictures');
    final ScreenshotSource source = linux();
    expect(await source.hasPermission(), isTrue);
    expect(await source.count(), 0);
    expect(await source.list(), isEmpty);
  });

  test('only real screenshots are imported, and unrelated images are ignored', () async {
    screenshot('Pictures/Screenshots/travel.png');
    screenshot('Pictures/Screenshots/Screenshot 2026-11-06 at 10.15.00.png', seed: 1);
    // A photo library is not a screenshot library.
    screenshot('Pictures/holiday.jpg', seed: 2);
    screenshot('Pictures/Screenshots/notes.txt', seed: 3);

    final List<DeviceScreenshot> found = await linux().list();
    expect(found.map((DeviceScreenshot s) => s.name), <String>[
      'Screenshot 2026-11-06 at 10.15.00.png',
      'travel.png',
    ]);
    expect(
      DateTime(2026, 11, 6, 10, 15),
      found.first.takenAt,
      reason: 'capture time comes from the screenshot filename',
    );
  });

  test('pages are bounded and resume strictly after the previous cursor', () async {
    for (int i = 0; i < 7; i++) {
      screenshot('Pictures/Screenshots/shot_$i.png', seed: i);
    }
    final ScreenshotSource source = linux();
    final List<DeviceScreenshot> first = await source.list(limit: 3);
    expect(first, hasLength(3));
    final List<DeviceScreenshot> second = await source.list(
      afterId: first.last.id,
      limit: 3,
    );
    expect(second, hasLength(3));
    expect(
      second.map((DeviceScreenshot s) => s.id).toSet()
        ..retainAll(first.map((DeviceScreenshot s) => s.id).toSet()),
      isEmpty,
    );
    final List<DeviceScreenshot> third = await source.list(
      afterId: second.last.id,
      limit: 3,
    );
    expect(third, hasLength(1));
  });

  test('a screenshot modified in place gets a new revision key', () async {
    final File file = screenshot('Pictures/Screenshots/travel.png');
    final DeviceScreenshot before = (await linux().list()).single;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    file.writeAsBytesSync(<int>[...file.readAsBytesSync(), 7]);
    final DeviceScreenshot after = (await linux().list()).single;
    expect(after.key, isNot(before.key));
    expect(after.id, before.id);
  });

  test('copying preserves the original bytes and refuses a moved file', () async {
    final File original = screenshot('Pictures/Screenshots/travel.png');
    final ScreenshotSource source = linux();
    final DeviceScreenshot entry = (await source.list()).single;
    final String staging = '${home.path}/staging.png';
    await source.copyTo(entry.contentUri, staging);
    expect(File(staging).readAsBytesSync(), original.readAsBytesSync());

    original.renameSync('${home.path}/Pictures/travel.png');
    await expectLater(
      source.copyTo(entry.contentUri, staging),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('shared screenshot folders are matched by filename per platform', () async {
    screenshot('Pictures/Screenshots/win.png');
    // macOS names captures "Screenshot <date> at <time>"; the Desktop folder is
    // matched by filename so unrelated desktop files never import.
    screenshot('Desktop/Screenshot 2026-11-06 at 09.00.00.png');
    screenshot('Desktop/receipt.pdf', seed: 9);
    screenshot('Screenshots/region.png', seed: 2);

    expect(
      (await macos().list()).map((DeviceScreenshot s) => s.name).toList(),
      containsAll(<String>[
        'Screenshot 2026-11-06 at 09.00.00.png',
        'region.png',
      ]),
    );
    // `package:path` follows the host platform, so the Windows maps only hold on
    // a Windows host; the Linux and macOS cases above run everywhere.
    if (Platform.isWindows) {
      expect((await windows().list()).single.name, 'win.png');
    }
  });

  test('links are never followed out of a screenshot folder', () async {
    final Directory outside = await Directory.systemTemp.createTemp('mindpocket_outside_');
    addTearDown(() => outside.delete(recursive: true));
    File('${outside.path}/private.png').writeAsBytesSync(<int>[0x89, 0x50, 0x4E, 0x47]);
    final Directory shots = folder('Pictures/Screenshots');
    try {
      Link('${shots.path}/linked.png').createSync('${outside.path}/private.png');
    } on FileSystemException {
      return; // Creating links can require privileges on Windows.
    }
    expect(await linux().list(), isEmpty);
  });
}
