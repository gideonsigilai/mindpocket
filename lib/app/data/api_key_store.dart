import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiKeyMetadata {
  const ApiKeyMetadata({
    required this.id,
    required this.name,
    required this.prefix,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String prefix;
  final DateTime createdAt;
}

class CreatedApiKey {
  const CreatedApiKey({required this.metadata, required this.secret});

  final ApiKeyMetadata metadata;
  final String secret;
}

class ApiKeyStore {
  ApiKeyStore({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? FlutterSecureStorage();

  static const _storageKey = 'served_api_keys';
  final FlutterSecureStorage _secureStorage;
  Future<void> _writeQueue = Future<void>.value();

  Future<List<ApiKeyMetadata>> listKeys() async {
    final entries = await _readEntries();
    return entries
        .map(
          (entry) => ApiKeyMetadata(
            id: entry['id']! as String,
            name: entry['name']! as String,
            prefix: entry['prefix']! as String,
            createdAt: DateTime.parse(entry['createdAt']! as String),
          ),
        )
        .toList(growable: false);
  }

  Future<CreatedApiKey> createKey(String name) => _serializeWrites(() async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty || normalizedName.length > 80) {
      throw const FormatException(
        'Key names must be between 1 and 80 characters.',
      );
    }

    final random = Random.secure();
    final secret =
        'loom_sk_${base64Url.encode(List<int>.generate(32, (_) => random.nextInt(256))).replaceAll('=', '')}';
    final id = List<int>.generate(
      8,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    final createdAt = DateTime.now().toUtc();
    final entry = <String, Object>{
      'id': id,
      'name': normalizedName,
      'prefix': secret.substring(0, 14),
      'createdAt': createdAt.toIso8601String(),
      'hash': sha256.convert(utf8.encode(secret)).toString(),
    };
    final entries = await _readEntries()
      ..add(entry);
    await _writeEntries(entries);

    return CreatedApiKey(
      metadata: ApiKeyMetadata(
        id: id,
        name: normalizedName,
        prefix: secret.substring(0, 14),
        createdAt: createdAt,
      ),
      secret: secret,
    );
  });

  Future<void> revokeKey(String id) => _serializeWrites(() async {
    final entries = await _readEntries();
    final filtered = entries.where((entry) => entry['id'] != id).toList();
    if (filtered.length == entries.length) {
      throw StateError('The selected API key no longer exists.');
    }
    await _writeEntries(filtered);
  });

  Future<bool> isValid(String secret) async {
    if (secret.isEmpty || secret.length > 256) return false;
    final candidate = sha256.convert(utf8.encode(secret)).toString();
    for (final entry in await _readEntries()) {
      if (_constantTimeEquals(entry['hash']! as String, candidate)) return true;
    }
    return false;
  }

  Future<List<Map<String, Object?>>> _readEntries() async {
    final encoded = await _secureStorage.read(key: _storageKey);
    if (encoded == null || encoded.isEmpty) return [];

    final decoded = jsonDecode(encoded);
    if (decoded is! List) {
      throw const FormatException('Stored API key data is invalid.');
    }
    return decoded.map((value) {
      if (value is! Map<String, dynamic> ||
          value['id'] is! String ||
          value['name'] is! String ||
          value['prefix'] is! String ||
          value['createdAt'] is! String ||
          value['hash'] is! String) {
        throw const FormatException('Stored API key data is invalid.');
      }
      return Map<String, Object?>.from(value);
    }).toList();
  }

  Future<void> _writeEntries(List<Map<String, Object?>> entries) async {
    if (entries.isEmpty) {
      await _secureStorage.delete(key: _storageKey);
      return;
    }
    await _secureStorage.write(key: _storageKey, value: jsonEncode(entries));
  }

  Future<T> _serializeWrites<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    final release = Completer<void>();
    final previous = _writeQueue;
    _writeQueue = release.future;

    unawaited(
      previous.then((_) async {
        try {
          result.complete(await operation());
        } on Object catch (error, stackTrace) {
          result.completeError(error, stackTrace);
        } finally {
          release.complete();
        }
      }),
    );
    return result.future;
  }

  bool _constantTimeEquals(String left, String right) {
    var difference = left.length ^ right.length;
    final length = max(left.length, right.length);
    for (var index = 0; index < length; index++) {
      final leftCode = index < left.length ? left.codeUnitAt(index) : 0;
      final rightCode = index < right.length ? right.codeUnitAt(index) : 0;
      difference |= leftCode ^ rightCode;
    }
    return difference == 0;
  }
}
