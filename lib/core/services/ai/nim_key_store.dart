// ignore_for_file: prefer_initializing_formals

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../utils/logger.dart';

/// Holds the NVIDIA NIM API key. Kept out of preferences because those are a
/// plain JSON file; the key is the one secret this app has.
class NimKeyStore {
  NimKeyStore({FlutterSecureStorage storage = const FlutterSecureStorage()})
    : _storage = storage;

  static const String _key = 'nim_api_key';

  final FlutterSecureStorage _storage;

  /// Returns null when the platform cannot read secure storage, which is a
  /// real state (locked keystore) rather than an error worth crashing over.
  Future<String?> read() async {
    try {
      final String? value = await _storage.read(key: _key);
      return value == null || value.trim().isEmpty ? null : value.trim();
    } catch (exception) {
      logWarn('Secure storage unavailable for the NIM key', exception);
      return null;
    }
  }

  Future<bool> hasKey() async => await read() != null;

  Future<void> write(String value) async {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) return;
    try {
      await _storage.write(key: _key, value: trimmed);
    } catch (exception) {
      logWarn('Could not store the NIM key securely', exception);
      rethrow;
    }
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (exception) {
      logWarn('Could not clear the NIM key', exception);
    }
  }
}
