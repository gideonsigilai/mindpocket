import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindpocket/core/models/attachment.dart';
import 'package:mindpocket/core/models/enums.dart';
import 'package:mindpocket/core/models/memory.dart';
import 'package:mindpocket/core/services/ai/nim_grouping_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mindpocket/core/services/ai/nim_key_store.dart';
import 'package:mindpocket/core/services/screenshots/screenshot_autopilot.dart';
import 'package:mindpocket/core/services/screenshots/screenshot_source.dart';
import 'package:mindpocket/core/services/screenshots/screenshot_sync_service.dart';

import 'support/harness.dart';

/// Stands in for the platform media store: serves the files handed to it and
/// copies their bytes the way the content resolver would.
class FakeScreenshotSource implements ScreenshotSource {
  FakeScreenshotSource(this.files, {this.pageSize = 500});

  final List<FakeShot> files;
  final int pageSize;
  bool permission = true;
  bool grantOnRequest = false;
  int requests = 0;
  int listed = 0;
  int copied = 0;
  int? failOnListCall;
  Completer<bool>? permissionGate;
  Future<void> Function()? onCopy;
  final Set<String> failingCopies = <String>{};
  final List<String?> cursors = <String?>[];

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<bool> requestPermission() async {
    requests++;
    if (permissionGate != null) {
      permission = await permissionGate!.future;
    } else if (grantOnRequest) {
      permission = true;
    }
    return permission;
  }

  @override
  Future<int> count() async => files.length;

  @override
  Future<List<DeviceScreenshot>> list({
    String? afterId,
    int limit = 500,
  }) async {
    listed++;
    cursors.add(afterId);
    if (listed == failOnListCall) {
      throw PlatformException(
        code: 'query_failed',
        message: 'Interrupted scan',
      );
    }
    if (!permission) {
      throw PlatformException(code: 'permission_denied');
    }
    final List<DeviceScreenshot> out =
        files
            .map((FakeShot shot) => shot.meta)
            .where(
              (DeviceScreenshot shot) =>
                  afterId == null || shot.id.compareTo(afterId) > 0,
            )
            .toList()
          ..sort(
            (DeviceScreenshot a, DeviceScreenshot b) => a.id.compareTo(b.id),
          );
    return out.take(limit < pageSize ? limit : pageSize).toList();
  }

  @override
  Future<void> copyTo(String contentUri, String destination) async {
    copied++;
    await onCopy?.call();
    if (failingCopies.contains(contentUri)) {
      throw const FileSystemException('Screenshot is temporarily unreadable');
    }
    final FakeShot shot = files.firstWhere(
      (FakeShot file) => file.meta.contentUri == contentUri,
    );
    if (!await shot.file.exists()) throw const FileSystemException('expired');
    await shot.file.copy(destination);
  }
}

class RecordingSource extends FakeScreenshotSource {
  RecordingSource(super.files);
}

class EmptySecureStorage implements FlutterSecureStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<String?>.value();
}

class FakeShot {
  FakeShot({required this.meta, required this.file});

  final DeviceScreenshot meta;
  final File file;
}

/// Deterministic grouping: money-ish text goes to "Money", everything else to
/// "Other", and it never invents ids.
class FakeGrouping implements GroupingProvider {
  FakeGrouping({this.omit = const <String>{}, this.fail});

  final Set<String> omit;
  final String? fail;
  final List<List<String>> batches = <List<String>>[];

  @override
  bool get isConfigured => true;

  @override
  Future<List<GroupingAssignment>> group({
    required List<GroupingItem> items,
    required List<String> knownCollections,
  }) async {
    batches.add(items.map((GroupingItem item) => item.id).toList());
    if (fail != null) throw GroupingException(fail!);
    return items
        .where((GroupingItem item) => !omit.contains(item.id))
        .map(
          (GroupingItem item) => GroupingAssignment(
            id: item.id,
            collection: item.text.toLowerCase().contains('kes')
                ? 'Money'
                : 'Other',
            title: 'Grouped ${item.text.length}',
          ),
        )
        .toList();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Harness harness;
  final List<File> created = <File>[];

  setUp(() async {
    harness = await Harness.create();
  });

  tearDown(() async {
    for (final File file in created) {
      if (await file.exists()) await file.delete();
    }
    created.clear();
    await harness.dispose();
  });

  Future<FakeShot> shot(
    String name, {
    required DateTime takenAt,
    int color = 40,
  }) async {
    final File file = await harness.writePng(name, size: color);
    created.add(file);
    return FakeShot(
      meta: DeviceScreenshot(
        id: name,
        name: name,
        contentUri: 'content://media/external/images/media/$name',
        takenAt: takenAt,
        width: 2,
        height: 2,
        byteSize: await file.length(),
        bucket: 'Screenshots',
        mimeType: 'image/png',
      ),
      file: file,
    );
  }

  ScreenshotSyncService serviceFor(FakeScreenshotSource source) =>
      ScreenshotSyncService(
        source: source,
        memories: harness.memories,
        taxonomy: harness.taxonomy,
        paths: harness.paths,
      );

  group('screenshot import', () {
    test(
      'imports every screenshot on the first pass, with capture times',
      () async {
        final DateTime morning = DateTime(2026, 11, 1, 9);
        final FakeScreenshotSource source = FakeScreenshotSource(<FakeShot>[
          await shot('a.png', takenAt: morning, color: 41),
          await shot(
            'b.png',
            takenAt: morning.add(const Duration(hours: 2)),
            color: 42,
          ),
        ]);
        final ScreenshotSyncService service = serviceFor(source);

        final ScreenshotSyncResult result = await service.sync(full: false);

        expect(result.found, 2);
        expect(result.imported, 2);
        expect(result.duplicates, 0);
        final List<Memory> memories = await harness.memoryDao.timeline(
          limit: 10,
        );
        expect(memories, hasLength(2));
        expect(
          memories.every((Memory m) => m.source == MemorySource.gallery),
          isTrue,
        );
        // Capture time comes from the device, not from import order.
        final List<DateTime> times =
            memories.map((Memory m) => m.createdAt).toList()..sort();
        expect(times.first, morning);
      },
    );

    test('the next pass only takes new items', () async {
      final DateTime base = DateTime(2026, 11, 1, 9);
      final FakeScreenshotSource source = FakeScreenshotSource(<FakeShot>[
        await shot('first.png', takenAt: base, color: 43),
      ]);
      final ScreenshotSyncService service = serviceFor(source);

      await service.sync(full: false);
      final ScreenshotSyncResult second = await service.sync(full: false);
      expect(second.found, 0, reason: 'nothing new since the marker');

      final FakeShot later = await shot(
        'second.png',
        takenAt: base.add(const Duration(days: 1)),
        color: 44,
      );
      source.files.add(later);
      final ScreenshotSyncResult third = await service.sync(full: false);
      expect(third.imported, 1);
      expect(await harness.memoryDao.timeline(limit: 10), hasLength(2));
    });

    test('a full rescan skips copies already saved', () async {
      final FakeScreenshotSource source = FakeScreenshotSource(<FakeShot>[
        await shot('same.png', takenAt: DateTime(2026, 11, 2, 8), color: 45),
      ]);
      final ScreenshotSyncService service = serviceFor(source);

      await service.sync(full: false);
      final ScreenshotSyncResult again = await service.sync(full: true);

      expect(again.imported, 0);
      expect(again.duplicates, 1);
      expect(await harness.memoryDao.attachmentCount(), 1);
      // A duplicate must not leave an imageless, empty entry in the timeline.
      final List<Memory> timeline = await harness.memoryDao.timeline(limit: 10);
      expect(timeline, hasLength(1));
      expect(timeline.single.title, isNotEmpty);
    });

    test(
      '"last import" is the run time, not the newest capture time',
      () async {
        // A gallery whose newest screenshot is old must not report a stale import.
        final FakeScreenshotSource source = FakeScreenshotSource(<FakeShot>[
          await shot('old.png', takenAt: DateTime(2024, 3, 1, 10), color: 51),
        ]);
        final ScreenshotSyncService service = serviceFor(source);

        final DateTime before = DateTime.now();
        await service.sync(full: true);
        final DateTime? reported = await service.lastSyncedAt();

        expect(reported, isNotNull);
        expect(
          reported!.isBefore(before),
          isFalse,
          reason:
              'the run happened now, even though the screenshot is from 2024',
        );
      },
    );

    test('a denied permission imports nothing and says so', () async {
      final FakeScreenshotSource source = FakeScreenshotSource(<FakeShot>[
        await shot('blocked.png', takenAt: DateTime(2026, 11, 2, 8), color: 46),
      ])..permission = false;
      final ScreenshotSyncService service = serviceFor(source);

      final ScreenshotSyncResult result = await service.sync(full: true);

      expect(result.imported, 0);
      expect(result.groupingError, contains('not granted'));
      expect(await harness.memoryDao.timeline(limit: 5), isEmpty);
    });

    test('one unreadable screenshot does not abort the pass', () async {
      final DateTime at = DateTime(2026, 11, 3, 7);
      final FakeShot broken = await shot('gone.png', takenAt: at, color: 47);
      await broken.file.delete();
      final FakeScreenshotSource source = FakeScreenshotSource(<FakeShot>[
        broken,
        await shot(
          'good.png',
          takenAt: at.add(const Duration(minutes: 1)),
          color: 48,
        ),
      ]);
      final ScreenshotSyncService service = serviceFor(source);

      final ScreenshotSyncResult result = await service.sync(full: true);

      expect(result.skipped, 1);
      expect(result.imported, 1);
    });
  });

  group('receipt recovery', () {
    test(
      'pages equal timestamps and finds later additions with older dates',
      () async {
        final DateTime capture = DateTime(2026, 11, 1);
        final FakeScreenshotSource source = FakeScreenshotSource(<FakeShot>[
          for (int index = 0; index < 5; index++)
            await shot('$index.png', takenAt: capture, color: 70 + index),
        ], pageSize: 2);
        final ScreenshotSyncResult initial = await serviceFor(source)
            .sync(full: false);
        expect(initial.imported, 5);
        expect(initial.completed, isTrue);
        expect(
          source.listed,
          4,
          reason: 'every bounded page, including the final empty page',
        );
        expect(source.copied, 5);

        source.files.add(
          await shot('00-older.png', takenAt: DateTime(2020), color: 76),
        );
        final ScreenshotSyncResult next = await serviceFor(source)
            .sync(full: false);
        expect(next.found, 1);
        expect(next.imported, 1);
        expect(source.copied, 6, reason: 'receipts survive service restarts');
        await serviceFor(source).sync(full: false);
        expect(source.copied, 6);
      },
    );

    test(
      'handles a real 500-item page boundary without recopying receipts',
      () async {
        final FakeShot bytes = await shot(
          'seed.png',
          takenAt: DateTime(2026),
          color: 77,
        );
        final List<FakeShot> files = <FakeShot>[
          for (int index = 0; index < 501; index++)
            FakeShot(
              meta: DeviceScreenshot(
                id: index.toString().padLeft(4, '0'),
                name: '$index.png',
                contentUri: 'content://media/external/images/media/$index',
                takenAt: DateTime(2026),
                width: 2,
                height: 2,
                byteSize: bytes.meta.byteSize,
                bucket: 'Screenshots',
                mimeType: 'image/png',
              ),
              file: bytes.file,
            ),
        ];
        final Directory documents = await harness.paths.documents;
        await File('${documents.path}/screenshot_import_receipts.jsonl')
            .writeAsString(
              files
                  .take(500)
                  .map((FakeShot item) => jsonEncode(item.meta.key))
                  .join(String.fromCharCode(10)),
            );
        final FakeScreenshotSource source = FakeScreenshotSource(files);
        final ScreenshotSyncResult result = await serviceFor(source)
            .sync(full: false);
        expect(result.found, 1);
        expect(result.imported, 1);
        expect(source.copied, 1);
        expect(source.cursors, <String?>[null, '0499', '0500']);
      },
    );

    test(
      'a failed page preserves receipts but not successful-run state',
      () async {
        final FakeScreenshotSource source = FakeScreenshotSource(<FakeShot>[
          for (int index = 0; index < 3; index++)
            await shot(
              'page-$index.png',
              takenAt: DateTime(2026),
              color: 78 + index,
            ),
        ], pageSize: 1)..failOnListCall = 2;
        final ScreenshotSyncService first = serviceFor(source);
        await expectLater(
          first.sync(full: true),
          throwsA(isA<PlatformException>()),
        );
        expect(await first.lastSyncedAt(), isNull);
        source.failOnListCall = null;
        final ScreenshotSyncResult retry = await serviceFor(source)
            .sync(full: false);
        expect(retry.imported, 2);
        expect(
          source.copied,
          3,
          reason: 'the completed first page must not be copied again',
        );
        expect(retry.completed, isTrue);
      },
    );

    test('failed copies retry without advancing first-run state', () async {
      final FakeShot retryable = await shot(
        'retry.png',
        takenAt: DateTime(2026),
        color: 81,
      );
      final FakeScreenshotSource source = FakeScreenshotSource(<FakeShot>[
        await shot('good.png', takenAt: DateTime(2026), color: 82),
        retryable,
      ])..failingCopies.add(retryable.meta.contentUri);
      final ScreenshotSyncService sync = serviceFor(source);
      final ScreenshotAutopilot autopilot = ScreenshotAutopilot(
        sync: sync,
        preferences: harness.prefs,
        keys: NimKeyStore(storage: EmptySecureStorage()),
      );
      await autopilot.run();
      expect(harness.prefs.screenshotFirstRunDone, isFalse);
      expect(await sync.lastSyncedAt(), isNull);
      source.failingCopies.clear();
      await autopilot.run();
      expect(harness.prefs.screenshotFirstRunDone, isTrue);
      expect(source.copied, 3);
      expect(await harness.memoryDao.timeline(limit: 10), hasLength(2));
    });

    test('torn journal appends cannot swallow subsequent receipts', () async {
      final FakeScreenshotSource source = FakeScreenshotSource(<FakeShot>[
        await shot('first.png', takenAt: DateTime(2026), color: 83),
      ]);
      await serviceFor(source).sync(full: false);
      final Directory documents = await harness.paths.documents;
      await File('${documents.path}/screenshot_import_receipts.jsonl')
          .writeAsString(
            '${String.fromCharCode(10)}"incomplete',
            mode: FileMode.append,
          );
      source.files.add(
        await shot('later.png', takenAt: DateTime(2026), color: 84),
      );
      await serviceFor(source).sync(full: false);
      await serviceFor(source).sync(full: false);
      expect(source.copied, 2);
    });

    test(
      'overlapping manual and automatic scans serialize without losing work',
      () async {
        final Completer<void> started = Completer<void>();
        final Completer<void> release = Completer<void>();
        final FakeScreenshotSource source = FakeScreenshotSource(<FakeShot>[
          await shot('z-first.png', takenAt: DateTime(2026), color: 88),
        ]);
        source.onCopy = () async {
          source.onCopy = null;
          started.complete();
          await release.future;
        };
        final ScreenshotSyncService sync = serviceFor(source);
        final Future<ScreenshotSyncResult> first = sync.sync(full: false);
        await started.future;
        source.files.add(
          await shot('a-new.png', takenAt: DateTime(2020), color: 89),
        );
        final Future<ScreenshotSyncResult> queued = sync.sync(full: false);
        release.complete();
        final List<ScreenshotSyncResult> results = await Future.wait(
          <Future<ScreenshotSyncResult>>[first, queued],
        );
        expect(
          results.map((ScreenshotSyncResult result) => result.imported),
          <int>[1, 1],
        );
        expect(source.copied, 2);
      },
    );
  });

  group('autopilot', () {
    test('disabled automatic import never touches the gallery', () async {
      final FakePreferences prefs = harness.prefs;
      await prefs.setScreenshotAutoImport(false);
      final RecordingSource source = RecordingSource(<FakeShot>[
        await shot('auto.png', takenAt: DateTime(2026, 11, 4, 11), color: 53),
      ]);
      final ScreenshotAutopilot autopilot = ScreenshotAutopilot(
        sync: ScreenshotSyncService(
          source: source,
          memories: harness.memories,
          taxonomy: harness.taxonomy,
          paths: harness.paths,
        ),
        preferences: prefs,
        keys: NimKeyStore(storage: EmptySecureStorage()),
      );

      await autopilot.run();

      expect(
        source.listed,
        0,
        reason: 'the switch is off, so nothing may be read',
      );
      expect(await harness.memoryDao.timeline(limit: 5), isEmpty);
    });

    test(
      'the first automatic pass is a full scan and marks itself done',
      () async {
        final RecordingSource source = RecordingSource(<FakeShot>[
          await shot('one.png', takenAt: DateTime(2026, 10, 1, 9), color: 54),
        ]);
        final ScreenshotAutopilot autopilot = ScreenshotAutopilot(
          sync: ScreenshotSyncService(
            source: source,
            memories: harness.memories,
            taxonomy: harness.taxonomy,
            paths: harness.paths,
          ),
          preferences: harness.prefs,
          keys: NimKeyStore(storage: EmptySecureStorage()),
        );

        await autopilot.run();

        expect(
          source.cursors.first,
          isNull,
          reason: 'first run enumerates every screenshot',
        );
        expect(await harness.memoryDao.timeline(limit: 5), hasLength(1));
        expect(harness.prefs.screenshotFirstRunDone, isTrue);

        final int copiesAfterFirstRun = source.copied;
        await autopilot.run();
        expect(
          source.copied,
          copiesAfterFirstRun,
          reason: 'receipted screenshots are not read or processed again',
        );
      },
    );
  });

  group('automatic consent and lifecycle', () {
    ScreenshotAutopilot automatic(FakeScreenshotSource source) =>
        ScreenshotAutopilot(
          sync: serviceFor(source),
          preferences: harness.prefs,
          keys: NimKeyStore(storage: EmptySecureStorage()),
        );

    test(
      'startup requests access after onboarding and imports automatically',
      () async {
        harness.prefs.onboardingDone = true;
        final FakeScreenshotSource source =
            FakeScreenshotSource(<FakeShot>[
                await shot('consent.png', takenAt: DateTime(2026), color: 85),
              ])
              ..permission = false
              ..grantOnRequest = true;
        final ScreenshotAutopilot autopilot = automatic(source);
        await autopilot.run();
        await autopilot.run();
        expect(source.requests, 1);
        expect(source.copied, 1);
        expect(harness.prefs.screenshotFirstRunDone, isTrue);
      },
    );

    test(
      'denial is remembered across startup orchestration instances',
      () async {
        harness.prefs.onboardingDone = true;
        final FakeScreenshotSource source = FakeScreenshotSource(<FakeShot>[])
          ..permission = false;
        await automatic(source).run();
        await automatic(source).run();
        expect(source.requests, 1);
        expect(harness.prefs.screenshotFirstRunDone, isFalse);
      },
    );

    test(
      'onboarding completion can start consent without a lifecycle event',
      () async {
        final FakeScreenshotSource source = FakeScreenshotSource(<FakeShot>[])
          ..permission = false
          ..grantOnRequest = true;
        final ScreenshotAutopilot autopilot = automatic(source);
        await autopilot.run();
        expect(source.requests, 0);
        harness.prefs.onboardingDone = true;
        await autopilot.run(requestAccess: true);
        expect(source.requests, 1);
        expect(harness.prefs.screenshotFirstRunDone, isTrue);
      },
    );

    test(
      'resume during permission presentation never presents twice',
      () async {
        harness.prefs.onboardingDone = true;
        final Completer<bool> permission = Completer<bool>();
        final FakeScreenshotSource source = FakeScreenshotSource(<FakeShot>[])
          ..permission = false
          ..permissionGate = permission;
        final ScreenshotAutopilot autopilot = automatic(source);
        final Future<void> first = autopilot.run();
        await Future<void>.delayed(Duration.zero);
        final Future<void> resumed = autopilot.run();
        permission.complete(true);
        await Future.wait(<Future<void>>[first, resumed]);
        expect(source.requests, 1);
        expect(harness.prefs.screenshotFirstRunDone, isTrue);
      },
    );

    test(
      'overlapping onboarding actions do not repeat a denied prompt',
      () async {
        harness.prefs.onboardingDone = true;
        final Completer<bool> permission = Completer<bool>();
        final FakeScreenshotSource source = FakeScreenshotSource(<FakeShot>[])
          ..permission = false
          ..permissionGate = permission;
        final ScreenshotAutopilot autopilot = automatic(source);
        final Future<void> first = autopilot.run();
        await Future<void>.delayed(Duration.zero);
        final Future<void> onboarding = autopilot.run(requestAccess: true);
        permission.complete(false);
        await Future.wait(<Future<void>>[first, onboarding]);
        expect(source.requests, 1);
        expect(harness.prefs.screenshotFirstRunDone, isFalse);
      },
    );

    test(
      'resume during import drains unseen rows behind the page cursor',
      () async {
        final Completer<void> started = Completer<void>();
        final Completer<void> release = Completer<void>();
        final FakeScreenshotSource source = FakeScreenshotSource(<FakeShot>[
          await shot('z-first.png', takenAt: DateTime(2026), color: 86),
        ]);
        source.onCopy = () async {
          source.onCopy = null;
          started.complete();
          await release.future;
        };
        final ScreenshotAutopilot autopilot = automatic(source);
        final Future<void> first = autopilot.run();
        await started.future;
        source.files.add(
          await shot('a-new.png', takenAt: DateTime(2020), color: 87),
        );
        final Future<void> resumed = autopilot.run();
        release.complete();
        await Future.wait(<Future<void>>[first, resumed]);
        expect(source.copied, 2);
        expect(
          source.cursors.where((String? cursor) => cursor == null),
          hasLength(2),
        );
      },
    );

    test(
      'failed native scans do not complete onboarding import state',
      () async {
        final FakeScreenshotSource source = FakeScreenshotSource(<FakeShot>[])
          ..failOnListCall = 1;
        await automatic(source).run();
        expect(harness.prefs.screenshotFirstRunDone, isFalse);
        expect(await serviceFor(source).lastSyncedAt(), isNull);
      },
    );
  });

  group('native source contract', () {
    const MethodChannel channel = MethodChannel('mindpocket/test-screenshots');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('uses the same bounded keyset map as Android and iOS', () async {
      MethodCall? observed;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            observed = call;
            return <Object?>[
              <String, Object?>{
                'id': '2',
                'name': 'Screenshot.png',
                'contentUri': 'ph://2',
                'takenAt': 1000,
                'width': 2,
                'height': 2,
                'size': 0,
                'bucket': 'Screenshots',
                'mimeType': 'image/png',
              },
            ];
          });
      final List<DeviceScreenshot> page = await ScreenshotSource(
        channel: channel,
      ).list(afterId: '1', limit: 2);
      expect(observed?.method, 'list');
      expect(observed?.arguments, <String, Object?>{
        'afterId': '1',
        'limit': 2,
      });
      expect(page.single.id, '2');
    });

    test(
      'propagates query and copy failures instead of reporting an empty scan',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              if (call.method == 'list') {
                throw PlatformException(code: 'query_failed');
              }
              return false;
            });
        final ScreenshotSource source = ScreenshotSource(channel: channel);
        await expectLater(source.list(), throwsA(isA<PlatformException>()));
        await expectLater(
          source.copyTo('ph://1', 'destination'),
          throwsA(isA<PlatformException>()),
        );
      },
    );
  });

  group('queue kick', () {
    test(
      'imports tell the processor there is work, without a UI action',
      () async {
        int kicks = 0;
        harness.memories.onWorkQueued = () => kicks++;
        final ScreenshotSyncService service = serviceFor(
          FakeScreenshotSource(<FakeShot>[
            await shot(
              'kick.png',
              takenAt: DateTime(2026, 11, 4, 9),
              color: 52,
            ),
          ]),
        );

        await service.sync(full: true);

        expect(
          kicks,
          1,
          reason: 'one OCR job queued, so the queue must be kicked',
        );
      },
    );
  });

  group('AI grouping', () {
    test('creates collections and assigns each memory once', () async {
      final DateTime at = DateTime(2026, 11, 4, 10);
      final FakeScreenshotSource source = FakeScreenshotSource(<FakeShot>[
        await shot('pay.png', takenAt: at, color: 49),
        await shot(
          'memo.png',
          takenAt: at.add(const Duration(minutes: 1)),
          color: 50,
        ),
      ]);
      final ScreenshotSyncService service = serviceFor(source);
      // Give the notes text the fake provider can classify on.
      await service.sync(full: true);
      final List<Memory> memories = await harness.memoryDao.timeline(limit: 10);
      await harness.memories.updateText(
        memoryId: memories.first.id,
        title: memories.first.title,
        note: 'Safaricom KES 1,200 sent',
      );

      final FakeGrouping grouping = FakeGrouping();
      final GroupOutcome outcome = await service.organise(
        memoryIds: memories.map((Memory m) => m.id).toList(),
        provider: grouping,
      );

      expect(outcome.created, 2, reason: 'Money and Other');
      final List<Collection> collections = await harness.taxonomy.collections();
      expect(
        collections.map((Collection c) => c.name),
        containsAll(<String>['Money', 'Other']),
      );
      expect(grouping.batches.single, hasLength(2));
      expect(
        await harness.taxonomy.collectionIdsFor(memories.last.id),
        hasLength(1),
        reason: 'exactly one collection per item, no duplicates',
      );
    });

    test(
      'reuses an existing collection instead of creating a duplicate',
      () async {
        final Memory memory = await harness.memories.createNote(
          title: 'a',
          note: 'KES 50',
        );
        final Collection existing = await harness.taxonomy.createCollection(
          'Money',
        );
        final ScreenshotSyncService service = serviceFor(
          FakeScreenshotSource(const <FakeShot>[]),
        );

        final GroupOutcome outcome = await service.organise(
          memoryIds: <String>[memory.id],
          provider: FakeGrouping(),
        );

        expect(outcome.created, 0);
        expect(await harness.taxonomy.collections(), hasLength(1));
        expect(await harness.taxonomy.collectionIdsFor(memory.id), <String>{
          existing.id,
        });
      },
    );

    test(
      'a backend failure changes nothing and keeps prior collections',
      () async {
        final Memory memory = await harness.memories.createNote(
          title: 'a',
          note: 'KES 50',
        );
        final Collection keep = await harness.taxonomy.createCollection('Mine');
        await harness.memories.setCollections(memory.id, <String>{keep.id});
        final ScreenshotSyncService service = serviceFor(
          FakeScreenshotSource(const <FakeShot>[]),
        );

        await expectLater(
          service.organise(
            memoryIds: <String>[memory.id],
            provider: FakeGrouping(
              fail: 'The AI backend timed out. Nothing was changed.',
            ),
          ),
          throwsA(isA<GroupingException>()),
        );
        expect(await harness.taxonomy.collectionIdsFor(memory.id), <String>{
          keep.id,
        });
      },
    );

    test('an item the model omits keeps its current collections', () async {
      final Memory memory = await harness.memories.createNote(
        title: 'a',
        note: 'KES 50',
      );
      final Collection keep = await harness.taxonomy.createCollection('Mine');
      await harness.memories.setCollections(memory.id, <String>{keep.id});
      final ScreenshotSyncService service = serviceFor(
        FakeScreenshotSource(const <FakeShot>[]),
      );

      final GroupOutcome outcome = await service.organise(
        memoryIds: <String>[memory.id],
        provider: FakeGrouping(omit: <String>{memory.id}),
      );

      expect(outcome.collections, 0);
      expect(await harness.taxonomy.collectionIdsFor(memory.id), <String>{
        keep.id,
      });
      expect(await harness.taxonomy.collections(), hasLength(1));
    });
  });

  group('NIM parsing', () {
    test('accepts fenced JSON and drops ids it was not given', () {
      const String answer =
          '```json\n'
          '[{"id":"a","collection":"Money","title":"M-PESA receipt"},'
          '{"id":"ghost","collection":"Nope","title":"x"}]\n```';
      final List<GroupingAssignment> parsed = NimGroupingProvider.parseAnswer(
        answer,
        <String>{'a'},
      );
      expect(parsed, hasLength(1));
      expect(parsed.single.collection, 'Money');
    });

    test('rejects a non-list answer', () {
      expect(
        () => NimGroupingProvider.parseAnswer(
          '{"collection":"Money"}',
          <String>{'a'},
        ),
        throwsA(isA<GroupingException>()),
      );
    });

    test(
      'reports a missing key as unconfigured rather than calling out',
      () async {
        final NimGroupingProvider provider = NimGroupingProvider(
          baseUrl: 'https://example.invalid/v1',
          apiKey: '',
          model: 'm',
        );
        expect(provider.isConfigured, isFalse);
        await expectLater(
          provider.group(
            items: const <GroupingItem>[],
            knownCollections: const <String>[],
          ),
          throwsA(isA<GroupingException>()),
        );
      },
    );
  });
}
