import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

/// A fully drawable signature canvas with no controls layered over it.
///
/// Labels and clear actions belong in the caller's toolbar, outside this
/// widget. Keeping [Signature] unconstrained internally also avoids the
/// `Center`/`LimitedBox` path used by the package when explicit dimensions are
/// passed, which can make the upper edge miss pointer events in tight layouts.
class ChecklistSignaturePad extends StatelessWidget {
  const ChecklistSignaturePad({
    super.key,
    required this.controller,
    this.height = 200,
    this.backgroundColor = Colors.white,
    this.borderColor = const Color(0xFFCBD5E1),
    this.borderRadius = 12,
    this.semanticLabel,
  });

  final SignatureController controller;
  final double height;
  final Color backgroundColor;
  final Color borderColor;
  final double borderRadius;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final canvas = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        child: SizedBox(
          key: const ValueKey('checklist-signature-canvas'),
          height: height,
          width: double.infinity,
          child: Signature(
            controller: controller,
            backgroundColor: Colors.transparent,
          ),
        ),
      ),
    );

    final label = semanticLabel;
    if (label == null || label.isEmpty) return canvas;
    return Semantics(label: label, textField: true, child: canvas);
  }
}

/// Signature editor whose toolbar is structurally outside the drawing canvas.
class ChecklistSignatureEditor extends StatelessWidget {
  const ChecklistSignatureEditor({
    super.key,
    required this.controller,
    required this.title,
    required this.clearLabel,
    required this.onClear,
    this.height = 220,
    this.borderColor = const Color(0xFFCBD5E1),
  });

  final SignatureController controller;
  final String title;
  final String clearLabel;
  final VoidCallback onClear;
  final double height;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          key: const ValueKey('checklist-signature-toolbar'),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Icon(Icons.draw_outlined, color: Theme.of(context).primaryColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton(
                key: const ValueKey('checklist-signature-clear'),
                onPressed: onClear,
                child: Text(clearLabel),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ChecklistSignaturePad(
          controller: controller,
          height: height,
          borderColor: borderColor,
          semanticLabel: title,
        ),
      ],
    );
  }
}
