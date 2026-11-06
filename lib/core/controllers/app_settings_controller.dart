import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../services/storage/preferences_service.dart';

/// Theme and accessibility preferences for the whole app.
///
/// Theme mode is mirrored into GetStorage so it survives restarts; the motion
/// preference falls back to the OS "remove animations" setting when the user has
/// not chosen explicitly.
class AppSettingsController extends GetxService {
  AppSettingsController(this._preferences);

  final PreferencesService _preferences;

  final Rx<ThemeMode> themeMode = ThemeMode.system.obs;
  final RxBool reduceMotion = false.obs;
  final RxnBool reduceMotionOverride = RxnBool();

  AppSettingsController init() {
    themeMode.value = switch (_preferences.themeModeName) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    reduceMotionOverride.value = _preferences.reducedMotionOverride;
    reduceMotion.value = _preferences.reducedMotionOverride ?? false;
    return this;
  }

  /// Called by the app shell when MediaQuery changes, so an unset override
  /// follows the system setting.
  void syncSystemMotion({required bool disableAnimations}) {
    if (reduceMotionOverride.value != null) return;
    if (reduceMotion.value == disableAnimations) return;
    reduceMotion.value = disableAnimations;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    await _preferences.setThemeModeName(mode.name);
  }

  Future<void> setReduceMotion(bool value) async {
    reduceMotion.value = value;
    reduceMotionOverride.value = value;
    await _preferences.setReducedMotionOverride(value);
  }

  /// Returns to following the OS animation preference.
  Future<void> clearReduceMotionOverride() async {
    reduceMotionOverride.value = null;
    await _preferences.setReducedMotionOverride(null);
  }

  /// Motion duration helper: zero when reduced, [normal] otherwise.
  Duration motion(Duration normal) =>
      reduceMotion.value ? Duration.zero : normal;
}
