import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

/// Lightweight, non-sensitive preferences. Tokens never go here; they live in
/// secure storage behind the cloud settings screen.
class PreferencesService extends GetxService {
  static const String _boxName = 'mindpocket_prefs';

  late final GetStorage _box;

  static const String kOnboardingDone = 'onboarding_done';
  static const String kThemeMode = 'theme_mode';
  static const String kOcrAuto = 'ocr_auto';
  static const String kTranscribeAuto = 'transcribe_auto';
  static const String kCloudEnabled = 'cloud_enabled';
  static const String kCloudBaseUrl = 'cloud_base_url';
  static const String kSortOldest = 'sort_oldest';
  static const String kSemanticEnabled = 'semantic_enabled';
  static const String kReducedMotion = 'reduced_motion_override';
  static const String kInterestsDismissedHint = 'interests_hint_dismissed';
  static const String kNimBaseUrl = 'nim_base_url';
  static const String kNimModel = 'nim_model';
  static const String kScreenshotAutoImport = 'screenshot_auto_import';
  static const String kScreenshotFirstRunDone = 'screenshot_first_run_done';

  Future<PreferencesService> init() async {
    await GetStorage.init(_boxName);
    _box = GetStorage(_boxName);
    return this;
  }

  bool get onboardingDone => readBool(kOnboardingDone, false);
  Future<void> completeOnboarding() => write(kOnboardingDone, true);

  String get themeModeName => readString(kThemeMode, 'system');
  Future<void> setThemeModeName(String value) => write(kThemeMode, value);

  bool get ocrAuto => readBool(kOcrAuto, true);
  Future<void> setOcrAuto(bool value) => write(kOcrAuto, value);

  bool get transcribeAuto => readBool(kTranscribeAuto, true);
  Future<void> setTranscribeAuto(bool value) => write(kTranscribeAuto, value);

  bool get cloudEnabled => readBool(kCloudEnabled, false);
  Future<void> setCloudEnabled(bool value) => write(kCloudEnabled, value);

  String get cloudBaseUrl => readString(kCloudBaseUrl, '');
  Future<void> setCloudBaseUrl(String value) =>
      write(kCloudBaseUrl, value.trim());

  /// NVIDIA NIM endpoint, model, and key. The key lives in the same local box as
  /// other settings and is never sent anywhere except the configured endpoint.
  String get nimBaseUrl =>
      readString(kNimBaseUrl, 'https://integrate.api.nvidia.com/v1');
  Future<void> setNimBaseUrl(String value) => write(kNimBaseUrl, value.trim());

  String get nimModel =>
      readString(kNimModel, 'nvidia/nemotron-3-nano-omni-30b-a3b-reasoning');
  Future<void> setNimModel(String value) => write(kNimModel, value.trim());

  // The key itself lives in secure storage (see NimKeyStore): preferences are
  // plain files and a credential does not belong there.

  bool get nimConfigured => nimModel.trim().isNotEmpty;

  bool get screenshotAutoImport => readBool(kScreenshotAutoImport, true);
  Future<void> setScreenshotAutoImport(bool value) =>
      write(kScreenshotAutoImport, value);

  bool get screenshotFirstRunDone => readBool(kScreenshotFirstRunDone, false);
  Future<void> markScreenshotFirstRunDone() =>
      write(kScreenshotFirstRunDone, true);

  bool get sortOldest => readBool(kSortOldest, false);
  Future<void> setSortOldest(bool value) => write(kSortOldest, value);

  bool get semanticEnabled => readBool(kSemanticEnabled, true);
  Future<void> setSemanticEnabled(bool value) => write(kSemanticEnabled, value);

  /// Null means "follow the system".
  bool? get reducedMotionOverride {
    final Object? value = _box.read<Object?>(kReducedMotion);
    return value is bool ? value : null;
  }

  Future<void> setReducedMotionOverride(bool? value) async {
    if (value == null) {
      await _box.remove(kReducedMotion);
    } else {
      await write(kReducedMotion, value);
    }
  }

  bool get interestsHintDismissed => readBool(kInterestsDismissedHint, false);
  Future<void> dismissInterestsHint() => write(kInterestsDismissedHint, true);

  bool readBool(String key, bool fallback) {
    final Object? value = _box.read<Object?>(key);
    return value is bool ? value : fallback;
  }

  String readString(String key, String fallback) {
    final Object? value = _box.read<Object?>(key);
    return value is String ? value : fallback;
  }

  Future<void> write(String key, Object? value) => _box.write(key, value);
}
