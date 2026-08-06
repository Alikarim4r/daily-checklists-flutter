import 'package:flutter/material.dart';

/// Subtle BMS watermark behind app scaffolds (Entry / Viewer / Admin).
class ChecklistAppBackground extends StatelessWidget {
  const ChecklistAppBackground({
    super.key,
    required this.child,
    this.opacity = 0.14,
  });

  final Widget child;
  final double opacity;

  static const assetPath = 'assets/branding/bg_watermark.jpg';

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: ColoredBox(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF121416)
                : const Color(0xFFF3F4F6),
          ),
        ),
        Positioned.fill(
          child: Opacity(
            opacity: opacity,
            child: Image.asset(
              assetPath,
              package: 'checklist_shared',
              fit: BoxFit.cover,
              alignment: Alignment.center,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
