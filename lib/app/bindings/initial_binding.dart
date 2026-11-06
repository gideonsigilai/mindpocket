import 'package:get/get.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/controllers/app_settings_controller.dart';
import '../../core/database/app_database.dart';
import '../../core/database/job_dao.dart';
import '../../core/database/memory_dao.dart';
import '../../core/database/search_dao.dart';
import '../../core/services/ai/cloud_ai_service.dart';
import '../../core/services/ai/model_manager.dart';
import '../../core/services/ai/related_service.dart';
import '../../core/services/permissions/permissions_service.dart';
import '../../core/services/processing/audio_playback_service.dart';
import '../../core/services/processing/audio_recording_service.dart';
import '../../core/services/processing/ocr_service.dart';
import '../../core/services/processing/processing_contracts.dart';
import '../../core/services/processing/processing_service.dart';
import '../../core/services/processing/share_intake_service.dart';
import '../../core/services/ai/nim_key_store.dart';
import '../../core/services/screenshots/screenshot_autopilot.dart';
import '../../core/services/screenshots/screenshot_source.dart';
import '../../core/services/screenshots/screenshot_sync_service.dart';
import '../../core/services/storage/share_import_service.dart';
import '../../features/settings/controller/settings_controller.dart';
import '../../core/services/storage/file_store.dart';
import '../../core/services/storage/memory_service.dart';
import '../../core/services/storage/path_service.dart';
import '../../core/services/storage/preferences_service.dart';
import '../../core/utils/logger.dart';

/// Performs the async boot sequence and registers services.
///
/// Kept out of [InitialBinding] because GetX bindings are synchronous; doing the
/// awaits here keeps `main()` readable and failures explicit.
Future<void> bootstrapServices({
  required AppDatabase database,
  required PreferencesService preferences,
}) async {
  Get.put<AppDatabase>(database, permanent: true);
  Get.put<PreferencesService>(preferences, permanent: true);

  final PathService paths = PathService();
  Get.put<PathService>(paths, permanent: true);

  final FileStore files = FileStore(paths);
  Get.put<FileStore>(files, permanent: true);

  Get.put<AppSettingsController>(
    AppSettingsController(preferences).init(),
    permanent: true,
  );

  final ModelManager models = ModelManager(paths, files, preferences);
  await models.init();
  Get.put<ModelManager>(models, permanent: true);

  final OcrService ocr = OcrService(paths);
  Get.put<OcrService>(ocr, permanent: true);

  final PermissionsService permissions = PermissionsService();
  Get.put<PermissionsService>(permissions, permanent: true);

  final AudioPlaybackService playback = AudioPlaybackService(paths);
  await playback.init();
  Get.put<AudioPlaybackService>(playback, permanent: true);

  final AudioRecordingService recording = AudioRecordingService(
    paths,
    permissions,
  );
  Get.put<AudioRecordingService>(recording, permanent: true);

  final ShareIntakeService shares = ShareIntakeService();
  Get.put<ShareIntakeService>(shares, permanent: true);

  Get.put<MemoryDao>(MemoryDao(database), permanent: true);
  Get.put<JobDao>(JobDao(database), permanent: true);
  Get.put<SearchDao>(SearchDao(database), permanent: true);
  Get.put<TaxonomyDao>(TaxonomyDao(database), permanent: true);
  Get.put<EmbeddingDao>(EmbeddingDao(database), permanent: true);
  Get.put<SuggestionDao>(SuggestionDao(database), permanent: true);

  final MemoryService memories = MemoryService(
    database: database,
    memories: Get.find<MemoryDao>(),
    jobs: Get.find<JobDao>(),
    search: Get.find<SearchDao>(),
    taxonomy: Get.find<TaxonomyDao>(),
    files: files,
    paths: paths,
    settings: ProcessingSettingsAdapter(preferences),
  );
  // Any queued OCR/transcription job starts immediately: importers (screenshots,
  // shares) never have to reach into the processing layer themselves.
  Get.put<MemoryService>(memories, permanent: true);

  final ProcessingService processing = ProcessingService(
    database: database,
    memories: Get.find<MemoryDao>(),
    jobs: Get.find<JobDao>(),
    search: Get.find<SearchDao>(),
    ocr: ocr,
    models: ModelManagerProvider(models),
    paths: PathResolverAdapter(paths),
    settings: ProcessingSettingsAdapter(preferences),
    transcripts: SherpaTranscriptEngine(),
  );
  Get.put<ProcessingService>(processing, permanent: true);
  // Any queued OCR/transcription job starts immediately: importers (screenshots,
  // shares) never have to reach into the processing layer themselves.
  memories.onWorkQueued = processing.schedule;

  // A finished job changes extractions and job status; bumping the revision
  // makes open detail pages and the timeline re-read instead of showing a stale
  // "queued" badge.
  processing.onJobFinished = memories.notifyCollectionChange;

  Get.put<RelatedService>(RelatedService(database, memories), permanent: true);

  // Cloud access is only reachable when a proxy URL is configured; the provider
  // object itself makes no network calls until asked.
  if (preferences.cloudBaseUrl.trim().isNotEmpty) {
    Get.put<AiAnalysisProvider>(
      ProxyAiProvider(
        baseUrl: preferences.cloudBaseUrl,
        secureStorage: const FlutterSecureStorage(),
      ),
      permanent: true,
    );
  }

  // The importer subscribes first, then intake reads the cold-start intent, so
  // a share that launched the app is saved rather than dropped.
  Get.put<ShareImportService>(
    ShareImportService(
      intake: shares,
      memories: memories,
      memoryDao: Get.find<MemoryDao>(),
    ),
    permanent: true,
  );
  await Get.find<ShareImportService>().start();

  Get.put<ScreenshotSyncService>(
    ScreenshotSyncService(
      source: ScreenshotSource(),
      memories: memories,
      taxonomy: Get.find<TaxonomyDao>(),
      paths: paths,
    ),
    permanent: true,
  );

  // Registered at bootstrap because the first-run import needs it before the
  // Settings page has ever been opened.
  Get.put<SettingsController>(
    SettingsController(
      preferences,
      Get.find<ModelManager>(),
      memories,
      database,
    ),
    permanent: true,
  );

  Get.put<ScreenshotAutopilot>(
    ScreenshotAutopilot(
      sync: Get.find<ScreenshotSyncService>(),
      preferences: preferences,
      keys: NimKeyStore(),
    ),
    permanent: true,
  ).start();

  await processing.resumeQueue();

  logDebug('Services ready');
}
