import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';

import '../../../core/models/enums.dart';
import '../../../core/models/memory.dart';
import '../../../core/services/ai/cloud_ai_service.dart';
import '../../../core/services/storage/preferences_service.dart';
import '../../../core/utils/logger.dart';

/// Cloud configuration: backend URL, optional bearer token, and the disclosure
/// copy. No provider keys are shipped in the APK.
class CloudSettingsController extends GetxController {
  CloudSettingsController(this._preferences);

  final PreferencesService _preferences;
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  final RxString baseUrl = ''.obs;
  final RxBool hasToken = false.obs;
  final RxBool testing = false.obs;
  final RxString testResult = ''.obs;
  final RxBool testSucceeded = false.obs;
  final RxBool cloudEnabled = false.obs;

  @override
  void onInit() {
    super.onInit();
    baseUrl.value = _preferences.cloudBaseUrl;
    cloudEnabled.value = _preferences.cloudEnabled;
    _loadTokenFlag();
  }

  Future<void> _loadTokenFlag() async {
    try {
      final String? token = await _secure.read(key: 'cloud_proxy_token');
      hasToken.value = token != null && token.isNotEmpty;
    } catch (exception) {
      logWarn('Secure storage unavailable', exception);
      hasToken.value = false;
    }
  }

  Future<void> saveUrl(String value) async {
    baseUrl.value = value.trim();
    await _preferences.setCloudBaseUrl(value);
    testResult.value = '';
    testSucceeded.value = false;
  }

  Future<void> saveToken(String value) async {
    try {
      final ProxyAiProvider provider = ProxyAiProvider(
        baseUrl: baseUrl.value,
        secureStorage: _secure,
      );
      await provider.saveToken(value);
      await _loadTokenFlag();
      testResult.value = value.trim().isEmpty
          ? 'Token removed. Requests will be sent without authorization.'
          : 'Token stored in the device keystore.';
      testSucceeded.value = true;
    } catch (exception) {
      logWarn('Saving token failed', exception);
      testResult.value =
          'The token could not be stored securely on this device.';
      testSucceeded.value = false;
    }
  }

  Future<void> setCloudEnabled(bool value) async {
    cloudEnabled.value = value;
    await _preferences.setCloudEnabled(value);
  }

  /// Sends a deliberately tiny, synthetic request so the user can confirm their
  /// proxy works without any personal content leaving the device.
  Future<void> testConnection() async {
    testing.value = true;
    testResult.value = '';
    testSucceeded.value = false;
    try {
      final ProxyAiProvider provider = ProxyAiProvider(
        baseUrl: baseUrl.value,
        secureStorage: _secure,
      );
      if (!provider.isConfigured) {
        testResult.value = 'Add your backend URL first.';
        return;
      }
      final CloudAnalysisResult result = await provider.analyse(
        CloudAnalysisRequest(
          memory: _syntheticMemory,
          includeImages: false,
          imageBase64: const <String>[],
          existingCollections: const <String>[],
        ),
      );
      testResult.value =
          'Backend responded with a valid structured result '
          '(${result.tags.length} tags, ${result.tasks.length} tasks).';
      testSucceeded.value = true;
    } on AiConfigurationException catch (error) {
      testResult.value = error.message;
    } on AiRequestException catch (error) {
      testResult.value = error.message;
    } catch (exception) {
      logWarn('Cloud test failed', exception);
      testResult.value = 'The request failed: $exception';
    } finally {
      testing.value = false;
    }
  }

  /// A clearly synthetic probe: no user content is included.
  Memory get _syntheticMemory {
    final DateTime now = DateTime.now();
    return Memory(
      id: 'connection-test',
      title: 'MindPocket connection test',
      note: '',
      kind: MemoryKind.note,
      source: MemorySource.typed,
      createdAt: now,
      updatedAt: now,
    );
  }

  bool get configured => baseUrl.value.trim().isNotEmpty;
  String get disclosureUrl => baseUrl.value.trim();
}
