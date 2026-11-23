import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';

class SettingsStore {
  SettingsStore({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? FlutterSecureStorage();

  static const _internetKey = 'internet_enabled';
  static const _baseUrlKey = 'remote_base_url';
  static const _remoteModelKey = 'remote_model';
  static const _remoteTokenKey = 'remote_api_token';
  static const _huggingFaceTokenKey = 'hugging_face_token';

  final FlutterSecureStorage _secureStorage;

  Future<AppSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    final remoteApiToken = await _secureStorage.read(key: _remoteTokenKey);
    final huggingFaceToken = await _secureStorage.read(
      key: _huggingFaceTokenKey,
    );

    return AppSettings(
      internetEnabled: preferences.getBool(_internetKey) ?? false,
      remoteBaseUrl:
          preferences.getString(_baseUrlKey) ?? 'https://api.openai.com/v1',
      remoteModel: preferences.getString(_remoteModelKey) ?? '',
      remoteApiToken: remoteApiToken ?? '',
      huggingFaceToken: huggingFaceToken ?? '',
    );
  }

  Future<void> saveInternetAccess(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_internetKey, enabled);
  }

  Future<void> saveApiSettings({
    required String remoteBaseUrl,
    required String remoteModel,
    required String remoteApiToken,
    required String huggingFaceToken,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_baseUrlKey, remoteBaseUrl);
    await preferences.setString(_remoteModelKey, remoteModel);
    await _writeSecret(_remoteTokenKey, remoteApiToken);
    await _writeSecret(_huggingFaceTokenKey, huggingFaceToken);
  }

  Future<void> saveRemoteModel(String model) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_remoteModelKey, model);
  }

  Future<void> _writeSecret(String key, String value) async {
    if (value.isEmpty) {
      await _secureStorage.delete(key: key);
    } else {
      await _secureStorage.write(key: key, value: value);
    }
  }
}
