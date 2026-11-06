import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../utils/logger.dart';

/// A payload received from another app.
class IncomingShare {
  const IncomingShare({
    required this.kind,
    this.text,
    this.filePath,
    this.mimeType,
  });

  final IncomingShareKind kind;
  final String? text;
  final String? filePath;
  final String? mimeType;
}

enum IncomingShareKind { text, image, unsupported }

/// Share-intent intake (Android/iOS) and the system picker (all platforms).
///
/// Handles both cold start (`getInitialMedia`) and warm delivery (stream). The
/// plugin copies shared files into its own cache; we copy them again into
/// app-owned storage immediately, because the cache entry is temporary.
///
/// Windows, Linux, and macOS have no share-intent plugin: intake is a no-op
/// there and the picker plus automatic screenshot import remain the real paths.
class ShareIntakeService extends GetxService {
  ShareIntakeService();

  final ImagePicker _picker = ImagePicker();
  // Not a broadcast stream: a cold-start share can be produced before the UI
  // subscribes, and buffering means that payload is still delivered.
  final StreamController<IncomingShare> _shares =
      StreamController<IncomingShare>();
  StreamSubscription<List<SharedMediaFile>>? _subscription;
  bool _initialised = false;

  Stream<IncomingShare> get shares => _shares.stream;

  /// Call once at startup. Subsequent calls are no-ops.
  Future<void> start() async {
    if (_initialised) return;
    _initialised = true;
    if (!_supportsShareIntents) {
      logDebug('Share-intent intake is not available on this platform');
      return;
    }
    _subscription = ReceiveSharingIntent.instance.getMediaStream().listen(
      _handleBatch,
      onError: (Object error) => logWarn('Share stream error', error),
    );
    // Cold start: the intent that launched the app is only available here.
    try {
      final List<SharedMediaFile> initial = await ReceiveSharingIntent.instance
          .getInitialMedia();
      if (initial.isNotEmpty) {
        await _handleBatch(initial);
        // Consume it so a hot reload or a second read cannot re-import.
        await ReceiveSharingIntent.instance.reset();
      }
    } catch (error) {
      logWarn('Initial share read failed', error);
    }
  }

  static bool get _supportsShareIntents =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> _handleBatch(List<SharedMediaFile> files) async {
    for (final SharedMediaFile file in files) {
      final IncomingShare? share = _map(file);
      if (share != null && !_shares.isClosed) _shares.add(share);
    }
  }

  IncomingShare? _map(SharedMediaFile file) {
    switch (file.type) {
      case SharedMediaType.text:
      case SharedMediaType.url:
        final String text = file.path.trim();
        if (text.isEmpty) return null;
        return IncomingShare(kind: IncomingShareKind.text, text: text);
      case SharedMediaType.image:
        return IncomingShare(
          kind: IncomingShareKind.image,
          filePath: file.path,
          mimeType: file.mimeType,
        );
      case SharedMediaType.video:
      case SharedMediaType.file:
        final String extension = p.extension(file.path).toLowerCase();
        if (<String>{
          '.jpg',
          '.jpeg',
          '.png',
          '.webp',
          '.heic',
          '.heif',
        }.contains(extension)) {
          return IncomingShare(
            kind: IncomingShareKind.image,
            filePath: file.path,
            mimeType: file.mimeType,
          );
        }
        return IncomingShare(
          kind: IncomingShareKind.unsupported,
          filePath: file.path,
          mimeType: file.mimeType,
        );
    }
  }

  /// Opens the Android photo picker. Returns null when the user cancels.
  Future<File?> pickImage() async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        // Originals are copied and thumbnailed locally; do not re-encode.
        imageQuality: null,
        requestFullMetadata: false,
      );
      if (picked == null) return null;
      return File(picked.path);
    } catch (error) {
      logWarn('Picker failed', error);
      rethrow;
    }
  }

  Future<List<File>> pickImages() async {
    try {
      final List<XFile> picked = await _picker.pickMultiImage(
        requestFullMetadata: false,
      );
      return picked
          .map((XFile file) => File(file.path))
          .toList(growable: false);
    } catch (error) {
      logWarn('Multi picker failed', error);
      rethrow;
    }
  }

  @override
  void onClose() {
    _subscription?.cancel();
    _shares.close();
    super.onClose();
  }
}
