import 'package:flutter/services.dart';

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

  /// Capture time protects against reused media IDs after a gallery wipe.
  String get key => '$id@${takenAt.millisecondsSinceEpoch}';
}

/// Enumerates screenshot metadata, never the rest of the user's gallery.
///
/// Native enumeration and copying run on workers. Small bounded metadata pages
/// are decoded here; moving these maps to another isolate would add a second
/// copy without moving any image work off the UI isolate.
class ScreenshotSource {
  ScreenshotSource({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('mindpocket/screenshots');

  final MethodChannel _channel;
  Future<bool>? _permissionRequest;

  Future<bool> hasPermission() async =>
      await _channel.invokeMethod<bool>('permission') ?? false;

  /// Permission UI stays on the root isolate and overlapping callers share it.
  Future<bool> requestPermission() =>
      _permissionRequest ??= _requestPermission();

  Future<bool> _requestPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } finally {
      _permissionRequest = null;
    }
  }

  Future<int> count() async => await _channel.invokeMethod<int>('count') ?? 0;

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
    final List<Object?>? rows = await _channel.invokeMethod<List<Object?>>(
      'list',
      <String, Object?>{
        'afterId': ?afterId,
        'limit': limit,
      },
    );
    return (rows ?? const <Object?>[])
        .cast<Map<Object?, Object?>>()
        .map(DeviceScreenshot.fromMap)
        .toList(growable: false);
  }

  /// Copies through ContentResolver / PhotoKit, never an assumed public path.
  Future<void> copyTo(String contentUri, String destination) async {
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
