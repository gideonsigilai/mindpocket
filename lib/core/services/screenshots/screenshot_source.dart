import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

part 'desktop_screenshot_library.dart';

/// One screenshot reported by the device's media store.
class DeviceScreenshot {
  const DeviceScreenshot({
    required this.id,
    required this.name,
    required this.contentUri,
    required this.takenAt,
    required this.width,
    required this.height,
    required this.byteSize,
    required this.bucket,
    required this.mimeType,
    this.revision,
  });

  factory DeviceScreenshot.fromMap(Map<Object?, Object?> map) =>
      DeviceScreenshot(
        id: '${map['id']}',
        name: '${map['name'] ?? ''}',
        contentUri: '${map['contentUri'] ?? ''}',
        takenAt: DateTime.fromMillisecondsSinceEpoch(
          (map['takenAt'] as num?)?.toInt() ?? 0,
        ),
        width: (map['width'] as num?)?.toInt() ?? 0,
        height: (map['height'] as num?)?.toInt() ?? 0,
        byteSize: (map['size'] as num?)?.toInt() ?? 0,
        bucket: '${map['bucket'] ?? ''}',
        mimeType: '${map['mimeType'] ?? 'image/png'}',
      );

  final String id;
  final String name;
  final String contentUri;
  final DateTime takenAt;
  final int width;
  final int height;
  final int byteSize;
  final String bucket;
  final String mimeType;

  /// Desktop content fingerprint; mobile receipts retain their original shape.
  final String? revision;

  /// Capture time protects mobile IDs; desktop revisions also detect edits and
  /// replacement files, including equal-size files with preserved timestamps.
  String get key => revision == null
      ? '$id@${takenAt.millisecondsSinceEpoch}'
      : '$id@${takenAt.millisecondsSinceEpoch}@$revision';
}

/// Enumerates only screenshots, using MediaStore/PhotoKit on mobile and a
/// conservative, non-recursive filesystem library on desktop.
class ScreenshotSource {
  ScreenshotSource({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('mindpocket/screenshots'),
      _desktop =
          channel == null &&
              (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
          ? _DesktopScreenshotLibrary(
              operatingSystem: Platform.operatingSystem,
              environment: Platform.environment,
            )
          : null;

  /// Exercises real filesystem workers with an isolated home directory, without
  /// reading the test machine's OS preferences or personal screenshot folders.
  @visibleForTesting
  ScreenshotSource.desktop({
    required String operatingSystem,
    required Map<String, String> environment,
    String? macCaptureDirectory,
  }) : _channel = const MethodChannel('mindpocket/screenshots'),
       _desktop = _DesktopScreenshotLibrary(
         operatingSystem: operatingSystem,
         environment: Map<String, String>.unmodifiable(environment),
         macCaptureDirectory: macCaptureDirectory,
         readSystemPreferences: false,
       );

  final MethodChannel _channel;
  final _DesktopScreenshotLibrary? _desktop;
  Future<bool>? _permissionRequest;

  Future<bool> hasPermission() async {
    final _DesktopScreenshotLibrary? desktop = _desktop;
    return desktop != null
        ? desktop.hasPermission()
        : await _channel.invokeMethod<bool>('permission') ?? false;
  }

  /// Permission UI stays on the root isolate and overlapping callers share it.
  Future<bool> requestPermission() =>
      _permissionRequest ??= _requestPermission();

  Future<bool> _requestPermission() async {
    try {
      final _DesktopScreenshotLibrary? desktop = _desktop;
      if (desktop != null) return await desktop.hasPermission();
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } finally {
      _permissionRequest = null;
    }
  }

  Future<int> count() async {
    final _DesktopScreenshotLibrary? desktop = _desktop;
    return desktop != null
        ? desktop.count()
        : await _channel.invokeMethod<int>('count') ?? 0;
  }

  /// A bounded page in stable ascending native-ID order, strictly after
  /// [afterId]. Capture timestamps are not cursors: screenshots saved later can
  /// have old or equal capture dates, and limited Photos access can expand.
  ///
  /// Errors propagate so an interrupted query cannot masquerade as an empty,
  /// successful scan. Implementations must apply the same ordering and limit.
  Future<List<DeviceScreenshot>> list({
    String? afterId,
    int limit = 500,
  }) async {
    final _DesktopScreenshotLibrary? desktop = _desktop;
    if (desktop != null) {
      return desktop.list(afterId: afterId, limit: limit);
    }
    final List<Object?>? rows = await _channel.invokeMethod<List<Object?>>(
      'list',
      <String, Object?>{'afterId': ?afterId, 'limit': limit},
    );
    return (rows ?? const <Object?>[])
        .cast<Map<Object?, Object?>>()
        .map(DeviceScreenshot.fromMap)
        .toList(growable: false);
  }

  /// Copies the original through the native media API or a desktop file worker.
  Future<void> copyTo(String contentUri, String destination) async {
    final _DesktopScreenshotLibrary? desktop = _desktop;
    if (desktop != null) return desktop.copyTo(contentUri, destination);
    final bool copied =
        await _channel.invokeMethod<bool>('copy', <String, Object?>{
          'contentUri': contentUri,
          'destination': destination,
        }) ??
        false;
    if (!copied) {
      throw PlatformException(
        code: 'copy_failed',
        message: 'The screenshot could not be read.',
      );
    }
  }
}
