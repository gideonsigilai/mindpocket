import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mindpocket/app/theme/app_theme.dart';
import 'package:mindpocket/features/home/controller/home_controller.dart';
import 'package:mindpocket/features/home/presentation/home_page.dart';

import 'support/harness.dart';

/// Renders the real timeline so the reactive wiring is exercised by the widgets,
/// not just by the controller. The device showed a stale "being processed"
/// banner and unstarred cards while the database already held the new state.
Future<void> _loadFonts() async {
  final FontLoader loader = FontLoader('Manrope');
  for (final String path in <String>[
    'assets/fonts/Manrope-Regular.ttf',
    'assets/fonts/Manrope-Medium.ttf',
    'assets/fonts/Manrope-SemiBold.ttf',
    'assets/fonts/Manrope-Bold.ttf',
    'assets/fonts/Manrope-ExtraBold.ttf',
  ]) {
    final Uint8List bytes = await File(path).readAsBytes();
    loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
  final FontLoader icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
}

void main() {
  testWidgets('timeline reflects a finished job and a star toggle', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final Harness harness = (await tester.runAsync(Harness.create))!;
    await tester.runAsync(
      () => harness.memories.createNote(title: 'Star me', note: 'body'),
    );

    final HomeController controller = HomeController(
      harness.memories,
      harness.processing,
      harness.prefs,
      harness.database,
    );
    Get.put<HomeController>(controller);

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (BuildContext context, Widget? child) => GetMaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: const Scaffold(body: HomePage()),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    // The card is rendered and unstarred.
    expect(find.text('Star me'), findsWidgets);
    expect(find.bySemanticsLabel('Star this memory'), findsWidgets);

    controller.pendingJobs.value = 2;
    await tester.pump();
    expect(find.textContaining('being processed'), findsOneWidget);

    controller.pendingJobs.value = 0;
    await tester.pump();
    expect(find.textContaining('being processed'), findsNothing);

    // Starring must redraw the card, not only write to SQLite.
    await tester.runAsync(
      () => controller.toggleFavorite(controller.memories.single),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(find.bySemanticsLabel('Remove from starred'), findsWidgets);

    await tester.runAsync(harness.dispose);
  });
}
