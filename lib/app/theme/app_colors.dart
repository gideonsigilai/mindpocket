import 'package:flutter/material.dart';

/// Brand palette. Neutrals are sampled from the supplied art direction —
/// near-white paper, true-black ink, one saturated sun accent — with teal kept
/// as the functional accent so state is never carried by yellow alone.
abstract final class AppColors {
  // Neutrals and the sun accent.
  static const Color cream = Color(0xFFF6F6F4);
  static const Color paper = Color(0xFFFFFFFF);
  static const Color ink = Color(0xFF101014);
  static const Color indigo = Color(0xFF17171C);
  static const Color teal = Color(0xFF0CB59B);
  static const Color tealDeep = Color(0xFF05695A);
  static const Color sun = Color(0xFFFECC30);
  static const Color sand = Color(0xFFEFEEEA);
  static const Color line = Color(0xFFE4E2DD);
  static const Color muted = Color(0xFF6E6C74);
  static const Color danger = Color(0xFFB3261E);

  /// Danger tone for dark surfaces: the light-theme red only reaches 2.6:1 on
  /// the night palette, so dark text/icons use a lighter red instead.
  static const Color dangerNight = Color(0xFFFF8A80);
  static Color dangerFor(Brightness brightness) =>
      brightness == Brightness.dark ? dangerNight : danger;
  static const Color success = Color(0xFF1E7A5A);

  // Dark
  static const Color night = Color(0xFF100E18);
  static const Color nightSurface = Color(0xFF191625);
  static const Color nightRaised = Color(0xFF231F32);
  static const Color nightLine = Color(0xFF322D44);
  static const Color nightInk = Color(0xFFF6F1E8);
  static const Color nightMuted = Color(0xFFA9A3B8);
  static const Color tealNight = Color(0xFF3BD8BC);
  static const Color sunNight = Color(0xFFFFD95A);

  /// Full-bleed page background.
  static Color background(Brightness brightness) =>
      brightness == Brightness.dark ? night : cream;

  /// Cards and sheets.
  static Color surface(Brightness brightness) =>
      brightness == Brightness.dark ? nightSurface : paper;

  /// Raised chips, inputs, secondary cards.
  static Color raised(Brightness brightness) =>
      brightness == Brightness.dark ? nightRaised : sand;

  static Color border(Brightness brightness) =>
      brightness == Brightness.dark ? nightLine : line;

  static Color textPrimary(Brightness brightness) =>
      brightness == Brightness.dark ? nightInk : ink;

  static Color textSecondary(Brightness brightness) =>
      brightness == Brightness.dark ? nightMuted : muted;

  static Color accent(Brightness brightness) =>
      brightness == Brightness.dark ? tealNight : teal;

  /// Teal deep enough for small text on cream.
  static Color accentText(Brightness brightness) =>
      brightness == Brightness.dark ? tealNight : tealDeep;

  static Color highlight(Brightness brightness) =>
      brightness == Brightness.dark ? sunNight : sun;

  /// Ink that stays legible on top of teal / sun fills.
  static const Color onAccent = Color(0xFF10231F);
  static const Color onSun = Color(0xFF221C00);

  /// Filled dark surfaces (primary actions, active navigation).
  static Color inkFor(Brightness brightness) =>
      brightness == Brightness.dark ? nightInk : indigo;

  static Color onInkFor(Brightness brightness) =>
      brightness == Brightness.dark ? night : cream;
}
