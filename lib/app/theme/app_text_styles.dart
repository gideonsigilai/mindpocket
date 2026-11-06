import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Typography is built from the bundled Manrope family. Sizes are in logical
/// pixels at the 390x844 design size and are still multiplied by the user's
/// system text scale by Flutter, so accessibility scaling keeps working.
abstract final class AppTextStyles {
  static TextTheme textTheme(Brightness brightness) {
    final Color primary = AppColors.textPrimary(brightness);
    final Color secondary = AppColors.textSecondary(brightness);
    // The family is bundled (see pubspec `fonts:`); Google Fonts must never be
    // consulted, because it would either hit the network or fall back silently.
    final base = ThemeData(brightness: brightness).textTheme
        .apply(fontFamily: 'Manrope');

    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(
        fontSize: 40,
        height: 1.08,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.2,
        color: primary,
      ),
      displayMedium: base.displayMedium?.copyWith(
        fontSize: 32,
        height: 1.12,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        color: primary,
      ),
      displaySmall: base.displaySmall?.copyWith(
        fontSize: 28,
        height: 1.16,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: primary,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontSize: 24,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: primary,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontSize: 20,
        height: 1.25,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: primary,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 18,
        height: 1.3,
        fontWeight: FontWeight.w700,
        color: primary,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 16,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontSize: 14,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        fontSize: 16,
        height: 1.5,
        fontWeight: FontWeight.w400,
        color: primary,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        fontSize: 14,
        height: 1.5,
        fontWeight: FontWeight.w400,
        color: primary,
      ),
      bodySmall: base.bodySmall?.copyWith(
        fontSize: 13,
        height: 1.45,
        fontWeight: FontWeight.w400,
        color: secondary,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontSize: 15,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
        color: primary,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontSize: 12,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: secondary,
      ),
      labelSmall: base.labelSmall?.copyWith(
        fontSize: 11,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: secondary,
      ),
    );
  }

  /// Small uppercase eyebrow used above headings.
  static TextStyle eyebrow(Brightness brightness) => TextStyle(
    fontFamily: 'Manrope',
    fontSize: 11,
    height: 1.2,
    letterSpacing: 1.4,
    fontWeight: FontWeight.w800,
    color: AppColors.accentText(brightness),
  );
}
