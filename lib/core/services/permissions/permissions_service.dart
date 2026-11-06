import 'dart:io';

import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Wraps permission requests so every caller handles denial the same way:
/// explain, offer Settings, and stay functional without the feature.
class PermissionsService extends GetxService {
  /// True when recording can start. Requests microphone access on first use.
  ///
  /// `permission_handler` reports microphone as permanently denied on desktop
  /// because there is no runtime prompt there. Windows, macOS, and Linux gate
  /// capture in the OS privacy settings and via the recorder backend, so the
  /// recorder's own capability check is the real signal.
  Future<PermissionOutcome> ensureMicrophone() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final AudioRecorder probe = AudioRecorder();
      try {
        return await probe.hasPermission() ||
                await probe.hasPermission(request: true)
            ? PermissionOutcome.granted
            : PermissionOutcome.denied;
      } on Exception {
        // Linux reports a missing audio session as a failure, not a denial.
        return PermissionOutcome.denied;
      } finally {
        await probe.dispose();
      }
    }
    final PermissionStatus status = await Permission.microphone.status;
    if (status.isGranted || status.isLimited) return PermissionOutcome.granted;
    if (status.isPermanentlyDenied) return PermissionOutcome.blocked;
    final PermissionStatus result = await Permission.microphone.request();
    if (result.isGranted || result.isLimited) return PermissionOutcome.granted;
    return result.isPermanentlyDenied
        ? PermissionOutcome.blocked
        : PermissionOutcome.denied;
  }

  /// Notifications are only needed for the optional completion notice, so a
  /// denial is never fatal and never blocks capture.
  Future<PermissionOutcome> ensureNotification() async {
    // Desktop has no notification permission to request from this plugin.
    if (Platform.isWindows || Platform.isLinux) {
      return PermissionOutcome.denied;
    }
    final PermissionStatus status = await Permission.notification.status;
    if (status.isGranted) return PermissionOutcome.granted;
    if (status.isPermanentlyDenied) return PermissionOutcome.blocked;
    final PermissionStatus result = await Permission.notification.request();
    if (result.isGranted) return PermissionOutcome.granted;
    return result.isPermanentlyDenied
        ? PermissionOutcome.blocked
        : PermissionOutcome.denied;
  }

  Future<bool> openSettings() => openAppSettings();
}

enum PermissionOutcome {
  granted,
  denied,
  blocked;

  bool get isGranted => this == granted;
}

/// Copy used by every denial surface so the message stays consistent.
String permissionMessage(PermissionOutcome outcome, String feature) {
  return switch (outcome) {
    PermissionOutcome.granted => '$feature is ready.',
    PermissionOutcome.denied =>
      '$feature needs permission. You can try again, or type a note instead.',
    PermissionOutcome.blocked =>
      '$feature is blocked. Open Settings → Permissions to allow it, or type a note instead.',
  };
}
