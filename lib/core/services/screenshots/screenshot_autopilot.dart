// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../utils/logger.dart';
import '../ai/nim_key_store.dart';
import '../ai/nim_grouping_provider.dart';
import '../storage/preferences_service.dart';
import 'screenshot_sync_service.dart';

/// Imports unseen screenshots on launch/resume, after the onboarding consent
/// flow. Concurrent lifecycle events coalesce into a follow-up pass rather than
/// losing screenshots captured while an import or permission dialog is active.
class ScreenshotAutopilot with WidgetsBindingObserver {
  ScreenshotAutopilot({
    required ScreenshotSyncService sync,
    required PreferencesService preferences,
    required NimKeyStore keys,
  }) : _sync = sync,
       _preferences = preferences,
       _keys = keys;

  static const String _permissionAsked = 'screenshot_permission_asked';

  final ScreenshotSyncService _sync;
  final PreferencesService _preferences;
  final NimKeyStore _keys;
  bool _started = false;
  bool _pending = false;
  bool _pendingAccess = false;
  bool _consentPresented = false;
  Future<void>? _active;

  final RxString message = ''.obs;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_started) unawaited(run());
    });
  }

  void stop() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _started) unawaited(run());
  }

  /// [requestAccess] is an explicit onboarding/settings action. Automatic calls
  /// ask once after onboarding, never repeatedly after a denial or app resume.
  Future<void> run({bool requestAccess = false}) {
    if (!_preferences.screenshotAutoImport) return Future<void>.value();
    _pending = true;
    _pendingAccess = _pendingAccess || requestAccess;
    return _active ??= _drain();
  }

  Future<void> _drain() async {
    _consentPresented = false;
    try {
      while (_pending) {
        final bool requestAccess = _pendingAccess;
        _pending = false;
        _pendingAccess = false;
        if (!_preferences.screenshotAutoImport) continue;
        try {
          await _runOnce(requestAccess: requestAccess);
        } catch (error, stack) {
          logError('Screenshot import failed', error, stack);
          message.value =
              'Screenshot import stopped early. It will retry next time.';
        }
      }
    } finally {
      _active = null;
    }
  }

  Future<void> _runOnce({required bool requestAccess}) async {
    bool allowed = await _sync.hasPermission();
    final bool shouldAsk =
        !_consentPresented &&
        (requestAccess ||
            (_preferences.onboardingDone &&
                !_preferences.readBool(_permissionAsked, false)));
    if (!allowed && shouldAsk) {
      // Persist before presenting: the system prompt can itself trigger resume.
      await _preferences.write(_permissionAsked, true);
      if (!_preferences.screenshotAutoImport) return;
      _consentPresented = true;
      allowed = await _sync.requestPermission();
      if (!allowed) {
        message.value =
            'Screenshot access was declined, so nothing was imported. '
            'You can grant it in Settings.';
        return;
      }
    }
    if (!allowed || !_preferences.screenshotAutoImport) return;

    final bool firstRun = !_preferences.screenshotFirstRunDone;
    final GroupingProvider? provider = await _groupingProvider();
    final ScreenshotSyncResult result = await _sync.sync(
      full: firstRun,
      grouping: provider,
    );
    if (result.imported > 0 ||
        result.skipped > 0 ||
        result.groupingError.isNotEmpty) {
      message.value = result.summary(fullScan: firstRun);
    }
    if (firstRun && result.completed) {
      await _preferences.markScreenshotFirstRunDone();
    }
  }

  Future<GroupingProvider?> _groupingProvider() async {
    final String? key = await _keys.read();
    if (key == null || !_preferences.nimConfigured) return null;
    return NimGroupingProvider(
      baseUrl: _preferences.nimBaseUrl,
      apiKey: key,
      model: _preferences.nimModel,
    );
  }
}
