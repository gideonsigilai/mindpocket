import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'app/bindings/initial_binding.dart';
import 'app/routes/app_pages.dart';
import 'app/routes/app_routes.dart';
import 'app/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'core/controllers/app_settings_controller.dart';
import 'core/database/app_database.dart';
import 'core/services/processing/audio_playback_service.dart';
import 'core/services/processing/ocr_service.dart';
import 'core/services/processing/processing_service.dart';
import 'core/services/storage/path_service.dart';
import 'core/services/storage/preferences_service.dart';
import 'core/utils/logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Phones are portrait-first. Desktop windows are freely resizable, so pinning
  // orientation there would be meaningless and would fight the window manager.
  if (Platform.isAndroid || Platform.isIOS) {
    await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  // Windows and Linux have no just_audio backend of their own. Registering the
  // media_kit backend is a no-op on platforms just_audio already supports.
  if (Platform.isWindows || Platform.isLinux) {
    JustAudioMediaKit.ensureInitialized(
      windows: Platform.isWindows,
      linux: Platform.isLinux,
    );
  }

  final PreferencesService preferences = await PreferencesService().init();

  // The bundled SQLite build is required for FTS5, which Android's system
  // SQLite does not provide.
  AppDatabase.initialise();
  final PathService paths = PathService();
  final String directory = (await paths.documents).path;
  final AppDatabase database = await AppDatabase.openIn(directory);

  await bootstrapServices(database: database, preferences: preferences);

  runApp(const MindPocketApp());
}

class MindPocketApp extends StatefulWidget {
  const MindPocketApp({super.key});

  @override
  State<MindPocketApp> createState() => _MindPocketAppState();
}

class _MindPocketAppState extends State<MindPocketApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    logDebug('MindPocket started');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // Audio must not keep playing behind a locked screen, and processing is
        // allowed to finish its current job before the process may be stopped.
        Get.find<AudioPlaybackService>().onAppPaused();
      case AppLifecycleState.resumed:
        // Android does not allow unrestricted background execution: unfinished
        // jobs resume as soon as the app returns to the foreground.
        if (Get.isRegistered<ProcessingService>()) {
          Get.find<ProcessingService>().resumeQueue();
        }
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (Get.isRegistered<OcrService>()) {
      Get.find<OcrService>().shutdown();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppSettingsController settings = Get.find<AppSettingsController>();
    return ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: false,
      splitScreenMode: true,
      builder: (BuildContext context, Widget? child) {
        return Obx(
          () => GetMaterialApp(
            title: AppConstants.appName,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: settings.themeMode.value,
            initialRoute: AppRoutes.splash,
            getPages: AppPages.pages,
            defaultTransition: Transition.fadeIn,
            opaqueRoute: false,
            builder: (BuildContext context, Widget? child) {
              // Keep system text scale (accessibility) but sync the motion
              // preference so animated surfaces can opt out.
              final MediaQueryData data = MediaQuery.of(context);
              settings.syncSystemMotion(
                disableAnimations: data.disableAnimations,
              );
              return MediaQuery(
                data: data.copyWith(
                  textScaler: data.textScaler.clamp(
                    minScaleFactor: 0.9,
                    maxScaleFactor: 2.0,
                  ),
                ),
                child: child ?? const SizedBox.shrink(),
              );
            },
          ),
        );
      },
    );
  }
}
