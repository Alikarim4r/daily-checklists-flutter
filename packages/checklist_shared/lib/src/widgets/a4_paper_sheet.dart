import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Centers content on a printable A4-width paper sheet (210×297 mm proportions).
///
/// Height grows with content (multi-page feel) while width stays A4.
class A4PaperSheet extends StatelessWidget {
  const A4PaperSheet({
    super.key,
    required this.child,
    this.maxWidth = 794, // ≈ A4 @ 96 dpi
    this.margin = const EdgeInsets.fromLTRB(28, 32, 28, 36),
    this.background = const Color(0xFFE5E7EB),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsets margin;
  final Color background;

  /// A4 aspect ratio (width / height) for a single page viewport hint.
  static const double a4Aspect = 210 / 297;

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final width = math.min(maxWidth, screenW - 24);

    return ColoredBox(
      color: background,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width),
            child: Material(
              color: Colors.white,
              elevation: 6,
              shadowColor: Colors.black26,
              child: Padding(
                padding: margin,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
