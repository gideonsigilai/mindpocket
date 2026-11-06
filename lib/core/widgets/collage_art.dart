import 'dart:math' as math;

import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Abstract collage illustration in the reference direction: monochrome cut-paper
/// shapes, a sun disc, dashed path, and grain. Generated in code so it scales
/// crisply and needs no bitmap assets.
class CollageArt extends StatelessWidget {
  const CollageArt({
    super.key,
    this.variant = CollageVariant.capture,
    this.height = 320,
    this.showGrain = true,
  });

  final CollageVariant variant;
  final double height;
  final bool showGrain;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    return Semantics(
      label: 'Decorative illustration',
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _CollagePainter(
            variant: variant,
            brightness: brightness,
            showGrain: showGrain,
          ),
        ),
      ),
    );
  }
}

enum CollageVariant { capture, voice, search, collections }

class _CollagePainter extends CustomPainter {
  _CollagePainter({
    required this.variant,
    required this.brightness,
    required this.showGrain,
  });

  final CollageVariant variant;
  final Brightness brightness;
  final bool showGrain;

  @override
  void paint(Canvas canvas, Size size) {
    final bool dark = brightness == Brightness.dark;
    final Color ink = dark ? AppColors.nightInk : const Color(0xFF1B1A22);
    final Color paper = dark ? AppColors.nightRaised : const Color(0xFFF4EFE6);
    final Color sun = dark ? AppColors.sunNight : AppColors.sun;
    final Color muted = dark
        ? const Color(0xFF4A4459)
        : const Color(0xFFD8D2C7);

    if (showGrain) _paintGrain(canvas, size, dark);

    // Sun disc with a hairline outline, echoing the reference.
    final Offset sunCenter = Offset(size.width * 0.82, size.height * 0.2);
    final double sunRadius = math.min(size.width, size.height) * 0.14;
    canvas.drawCircle(sunCenter, sunRadius, Paint()..color = sun);
    canvas.drawCircle(
      sunCenter,
      sunRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = ink.withValues(alpha: 0.55),
    );

    switch (variant) {
      case CollageVariant.capture:
        _paintCapture(canvas, size, ink, paper, muted, dark);
      case CollageVariant.voice:
        _paintVoice(canvas, size, ink, paper, muted, dark);
      case CollageVariant.search:
        _paintSearch(canvas, size, ink, paper, muted);
      case CollageVariant.collections:
        _paintCollections(canvas, size, ink, paper, muted);
    }
  }

  void _paintCapture(
    Canvas canvas,
    Size size,
    Color ink,
    Color paper,
    Color muted,
    bool dark,
  ) {
    // A tall, folded screenshot sheet with a curled corner.
    final Rect sheet = Rect.fromLTWH(
      size.width * 0.18,
      size.height * 0.12,
      size.width * 0.46,
      size.height * 0.74,
    );
    final Path sheetPath = Path()
      ..addRRect(
        RRect.fromRectAndCorners(
          sheet,
          topLeft: const Radius.circular(6),
          topRight: const Radius.circular(34),
          bottomLeft: const Radius.circular(6),
          bottomRight: const Radius.circular(6),
        ),
      );
    canvas.drawPath(sheetPath, Paint()..color = ink);

    // Fold.
    final Path fold = Path()
      ..moveTo(sheet.right - 34, sheet.top)
      ..lineTo(sheet.right, sheet.top + 34)
      ..lineTo(sheet.right - 34, sheet.top + 34)
      ..close();
    canvas.drawPath(fold, Paint()..color = paper.withValues(alpha: 0.9));

    // Content bars on the sheet.
    final Paint bar = Paint()..color = paper.withValues(alpha: 0.28);
    for (int i = 0; i < 4; i++) {
      final double y = sheet.top + 70 + i * 30;
      final double w = i.isEven ? sheet.width * 0.62 : sheet.width * 0.4;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(sheet.left + 22, y, w, 7),
          const Radius.circular(4),
        ),
        bar,
      );
    }

    // Overlapping translucent square.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.5,
          size.height * 0.42,
          size.width * 0.3,
          size.width * 0.3,
        ),
        const Radius.circular(10),
      ),
      Paint()..color = muted.withValues(alpha: dark ? 0.5 : 0.55),
    );

    // Pipe outline.
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..color = ink;
    canvas.drawLine(
      Offset(size.width * 0.1, size.height * 0.9),
      Offset(size.width * 0.36, size.height * 0.9),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * 0.1, size.height * 0.55),
      Offset(size.width * 0.1, size.height * 0.9),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * 0.1, size.height * 0.55),
      Offset(size.width * 0.25, size.height * 0.55),
      stroke,
    );

    // Small floating ball.
    canvas.drawCircle(
      Offset(size.width * 0.72, size.height * 0.82),
      size.width * 0.028,
      Paint()..color = ink,
    );
  }

  void _paintVoice(
    Canvas canvas,
    Size size,
    Color ink,
    Color paper,
    Color muted,
    bool dark,
  ) {
    // Stacked rounded slabs suggesting a waveform.
    final Paint inkPaint = Paint()..color = ink;
    final Paint mutedPaint = Paint()..color = muted.withValues(alpha: 0.65);

    final double baseY = size.height * 0.55;
    const List<double> heights = <double>[
      0.18,
      0.34,
      0.52,
      0.3,
      0.44,
      0.22,
      0.36,
    ];
    final double barWidth = size.width * 0.055;
    final double gap = size.width * 0.028;
    final double totalWidth =
        heights.length * barWidth + (heights.length - 1) * gap;
    double x = (size.width - totalWidth) / 2;
    for (int i = 0; i < heights.length; i++) {
      final double h = size.height * heights[i];
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, baseY - h / 2, barWidth, h),
          Radius.circular(barWidth / 2),
        ),
        i == 2 || i == 4 ? inkPaint : mutedPaint,
      );
      x += barWidth + gap;
    }

    // Dashed path through the bars.
    final Paint dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = ink.withValues(alpha: 0.7);
    _drawDashedPath(
      canvas,
      Path()
        ..moveTo(size.width * 0.12, baseY + size.height * 0.22)
        ..cubicTo(
          size.width * 0.36,
          baseY + size.height * 0.34,
          size.width * 0.6,
          baseY - size.height * 0.34,
          size.width * 0.88,
          baseY - size.height * 0.24,
        ),
      dash,
    );

    // Circular lens.
    canvas.drawCircle(
      Offset(size.width * 0.2, size.height * 0.26),
      size.width * 0.1,
      Paint()..color = paper.withValues(alpha: 0.9),
    );
    canvas.drawCircle(
      Offset(size.width * 0.2, size.height * 0.26),
      size.width * 0.1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = ink.withValues(alpha: 0.5),
    );
  }

  void _paintSearch(
    Canvas canvas,
    Size size,
    Color ink,
    Color paper,
    Color muted,
  ) {
    // Magnifier ring with a thick handle.
    final Offset center = Offset(size.width * 0.42, size.height * 0.46);
    final double radius = size.width * 0.19;
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = paper.withValues(alpha: 0.95),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..color = ink,
    );
    canvas.drawLine(
      center + Offset(radius * 0.66, radius * 0.66),
      center + Offset(radius * 1.5, radius * 1.5),
      Paint()
        ..strokeWidth = 11
        ..strokeCap = StrokeCap.round
        ..color = ink,
    );

    // Ladder.
    final Paint rung = Paint()
      ..color = muted
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    final Offset a = Offset(size.width * 0.12, size.height * 0.52);
    final Offset b = Offset(size.width * 0.24, size.height * 0.82);
    canvas.drawLine(a, b, rung);
    canvas.drawLine(a + const Offset(30, -4), b + const Offset(30, -4), rung);
    for (int i = 1; i < 4; i++) {
      final double t = i / 4;
      canvas.drawLine(
        Offset.lerp(a, b, t)!,
        Offset.lerp(a + const Offset(30, -4), b + const Offset(30, -4), t)!,
        rung,
      );
    }
  }

  void _paintCollections(
    Canvas canvas,
    Size size,
    Color ink,
    Color paper,
    Color muted,
  ) {
    // Three staggered cards.
    final List<Rect> cards = <Rect>[
      Rect.fromLTWH(
        size.width * 0.12,
        size.height * 0.5,
        size.width * 0.42,
        size.height * 0.3,
      ),
      Rect.fromLTWH(
        size.width * 0.3,
        size.height * 0.34,
        size.width * 0.42,
        size.height * 0.3,
      ),
      Rect.fromLTWH(
        size.width * 0.48,
        size.height * 0.5,
        size.width * 0.4,
        size.height * 0.3,
      ),
    ];
    final List<Color> colors = <Color>[
      muted,
      paper,
      ink.withValues(alpha: 0.92),
    ];
    for (int i = 0; i < cards.length; i++) {
      canvas.save();
      canvas.translate(cards[i].center.dx, cards[i].center.dy);
      canvas.rotate((i - 1) * 0.06);
      canvas.translate(-cards[i].center.dx, -cards[i].center.dy);
      canvas.drawRRect(
        RRect.fromRectAndRadius(cards[i], const Radius.circular(16)),
        Paint()..color = colors[i],
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(cards[i], const Radius.circular(16)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = ink.withValues(alpha: 0.35),
      );
      canvas.restore();
    }
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    for (final PathMetric metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final double end = math.min(distance + 8, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + 7;
      }
    }
  }

  void _paintGrain(Canvas canvas, Size size, bool dark) {
    // Deterministic speckle so the surface never shimmers on rebuild.
    final math.Random random = math.Random(7);
    final Paint paint = Paint()
      ..color = (dark ? Colors.white : Colors.black).withValues(
        alpha: dark ? 0.05 : 0.045,
      );
    final int dots = (size.width * size.height / 900).round().clamp(80, 380);
    for (int i = 0; i < dots; i++) {
      final double x = random.nextDouble() * size.width;
      final double y = random.nextDouble() * size.height;
      canvas.drawCircle(Offset(x, y), random.nextDouble() * 1.3 + 0.3, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CollagePainter oldDelegate) =>
      oldDelegate.variant != variant ||
      oldDelegate.brightness != brightness ||
      oldDelegate.showGrain != showGrain;
}
