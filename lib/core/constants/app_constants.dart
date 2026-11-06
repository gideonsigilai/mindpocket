/// Cross-cutting constants. Keep magic strings in one place.
abstract final class AppConstants {
  static const String appName = 'MindPocket';
  static const String tagline =
      'Screenshots and voice notes, kept in one pocket.';

  static const int timelinePageSize = 20;
  static const int maxConcurrentJobs = 1;

  /// Model catalogue lives in [core/services/ai/model_catalog.dart]; the
  /// folder name here only controls on-disk storage.
  static const String modelsFolder = 'models';
  static const String imagesFolder = 'images';
  static const String audioFolder = 'audio';
  static const String thumbnailsFolder = 'thumbnails';

  /// Accepted import types (images only for now; audio is recorded in-app).
  static const Set<String> imageExtensions = <String>{
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.heic',
    '.heif',
  };

  static const int maxImageBytes = 30 * 1024 * 1024;
  static const int maxNoteLength = 20000;

  static const Duration searchDebounce = Duration(milliseconds: 280);
  static const Duration snackDuration = Duration(seconds: 3);
}
