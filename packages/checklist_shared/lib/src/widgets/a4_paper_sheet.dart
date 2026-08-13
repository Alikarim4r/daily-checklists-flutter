import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/checklist_brand.dart';

/// Centers content on a printable A4-width paper sheet (≈794px @ 96dpi).
///
/// The sheet stays white (print-accurate) in both themes; the surrounding
/// canvas follows the app dark/light chrome. Layout is always at [maxWidth],
/// then scaled on narrow viewports so phones match the paper form.
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = math.max(280.0, constraints.maxWidth - 16);
        final scale = math.min(1.0, available / maxWidth);
        final displayW = maxWidth * scale;

        final paper = Material(
          color: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          child: Padding(padding: margin, child: child),
        );

        // Desktop (scale≈1): no FittedBox — it can swallow mouse hits on thumbs.
        // Phone (scale<1): FittedBox keeps A4 proportions while fitting width.
        final sheetInner = scale >= 0.999
            ? SizedBox(width: maxWidth, child: paper)
            : SizedBox(
                width: displayW,
                child: FittedBox(
                  fit: BoxFit.fitWidth,
                  alignment: Alignment.topCenter,
                  child: SizedBox(width: maxWidth, child: paper),
                ),
              );

        final sheet = DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            boxShadow: [
              BoxShadow(
                color: dark
                    ? Colors.black.withValues(alpha: 0.65)
                    : Colors.black.withValues(alpha: 0.18),
                blurRadius: dark ? 32 : 14,
                offset: Offset(0, dark ? 14 : 6),
              ),
              if (dark)
                BoxShadow(
                  color: ChecklistChrome.accent.withValues(alpha: 0.12),
                  blurRadius: 40,
                  spreadRadius: -4,
                ),
            ],
          ),
          child: sheetInner,
        );

        return ColoredBox(
          color: dark ? ChecklistChrome.darkCanvas : const Color(0x00000000),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(8, 16, 8, 24 + bottomInset),
            child: Center(child: sheet),
          ),
        );
      },
    );
  }
}
