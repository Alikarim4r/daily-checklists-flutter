import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/checklist_brand.dart';

/// A calm, theme-aware facilities network behind Entry, Viewer and Admin.
///
/// The pattern is drawn as vectors so it stays crisp on phones, desktop and
/// large displays without loading or stretching a bitmap watermark.
class ChecklistAppBackground extends StatelessWidget {
  const ChecklistAppBackground({
    super.key,
    required this.child,
    this.opacity = 0.14,
  });

  final Widget child;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final strength = opacity.clamp(0.04, 0.24);

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: ColoredBox(
            color: dark ? ChecklistChrome.darkCanvas : const Color(0xFFF4F7F8),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _FacilitiesNetworkPainter(
                  accent: theme.colorScheme.primary.withValues(
                    alpha: dark ? strength * 0.72 : strength * 0.62,
                  ),
                  quiet: theme.colorScheme.onSurface.withValues(
                    alpha: dark ? strength * 0.20 : strength * 0.14,
                  ),
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _FacilitiesNetworkPainter extends CustomPainter {
  const _FacilitiesNetworkPainter({required this.accent, required this.quiet});

  final Color accent;
  final Color quiet;

  @override
  void paint(Canvas canvas, Size size) {
    final shortSide = math.min(size.width, size.height);
    final radius = (shortSide * 0.105).clamp(46.0, 88.0);
    final horizontalGap = radius * 3.05;
    final verticalGap = radius * 2.42;
    final linePaint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15;
    final quietPaint = Paint()
      ..color = quiet
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    final nodePaint = Paint()
      ..color = accent
      ..style = PaintingStyle.fill;

    var row = -1;
    for (
      double y = -verticalGap;
      y < size.height + verticalGap;
      y += verticalGap
    ) {
      row += 1;
      final offset = row.isOdd ? horizontalGap * 0.5 : 0.0;
      for (
        double x = -horizontalGap + offset;
        x < size.width + horizontalGap;
        x += horizontalGap
      ) {
        final center = Offset(x, y);
        final path = _hexagon(center, radius);
        canvas.drawPath(path, linePaint);

        // A second partial ring makes the motif read as a connected facility
        // system rather than a repeated decorative tile.
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius * 0.56),
          -math.pi * 0.88,
          math.pi * 1.18,
          false,
          quietPaint,
        );
        canvas.drawCircle(center, 2.4, nodePaint);

        final right = Offset(x + horizontalGap, y);
        canvas.drawLine(
          Offset(x + radius, y),
          Offset(right.dx - radius, right.dy),
          quietPaint,
        );
        if (row.isEven) {
          final lower = Offset(x + horizontalGap * 0.5, y + verticalGap);
          canvas.drawLine(
            Offset(x + radius * 0.52, y + radius * 0.86),
            Offset(lower.dx - radius * 0.52, lower.dy - radius * 0.86),
            quietPaint,
          );
        }
      }
    }

    final sweepPaint = Paint()
      ..color = accent.withValues(alpha: accent.a * 0.62)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(size.width * 0.88, size.height * 0.16),
        radius: shortSide * 0.24,
      ),
      math.pi * 0.68,
      math.pi * 0.92,
      false,
      sweepPaint,
    );
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(size.width * 0.10, size.height * 0.86),
        radius: shortSide * 0.18,
      ),
      -math.pi * 0.30,
      math.pi * 0.88,
      false,
      sweepPaint,
    );
  }

  Path _hexagon(Offset center, double radius) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = math.pi / 3 * i;
      final point = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  @override
  bool shouldRepaint(covariant _FacilitiesNetworkPainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.quiet != quiet;
}
