import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/checklist_brand.dart';
import 'checklist_app_background.dart';

/// Centers content on a printable A4-width paper sheet (≈794px @ 96dpi).
///
/// Content is always laid out at full [maxWidth] (desktop / PDF proportions),
/// then uniformly scaled to fit the viewport so phones match the paper form.
class A4PaperSheet extends StatelessWidget {
  const A4PaperSheet({
    super.key,
    required this.child,
    this.maxWidth = 794, // ≈ A4 @ 96 dpi
    this.margin = const EdgeInsets.fromLTRB(28, 32, 28, 36),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsets margin;

  /// A4 aspect ratio (width / height) for a single page viewport hint.
  static const double a4Aspect = 210 / 297;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return ChecklistAppBackground(
      opacity: dark ? 0.06 : 0.11,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = math.max(280.0, constraints.maxWidth - 16);
          final scale = math.min(1.0, available / maxWidth);
          final displayW = maxWidth * scale;

          return ColoredBox(
            color: dark
                ? ChecklistChrome.darkCanvas.withValues(alpha: 0.35)
                : Colors.transparent,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(8, 12, 8, 20 + bottomInset),
              child: Center(
                child: SizedBox(
                  width: displayW,
                  child: FittedBox(
                    fit: BoxFit.fitWidth,
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: maxWidth,
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
              ),
            ),
          );
        },
      ),
    );
  }
}
