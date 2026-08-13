import 'package:flutter/material.dart';

enum ReportLogoSlotKind { orgHeader, zoneFooter, siteFooter }

/// Tiny A4 mockup highlighting where a logo sits on the inspection sheet.
class ReportLogoPaperDiagram extends StatelessWidget {
  const ReportLogoPaperDiagram({
    super.key,
    required this.kind,
    required this.language,
  });

  final ReportLogoSlotKind kind;
  final String language;

  bool get _ar => language == 'ar';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final caption = switch (kind) {
      ReportLogoSlotKind.orgHeader =>
        _ar
            ? 'شعار الجهة أعلى الورقة (يمين في العربية / يمين-خارجي في الإنجليزية)'
            : 'Organization logo at the top of the sheet',
      ReportLogoSlotKind.zoneFooter =>
        _ar
            ? 'شعار المنطقة أسفل الورقة (يسار بالعربية · يمين بالإنجليزية)'
            : 'Zone logo at the bottom (left in Arabic · right in English)',
      ReportLogoSlotKind.siteFooter =>
        _ar
            ? 'شعار الموقع أسفل الورقة (يمين بالعربية · يسار بالإنجليزية)'
            : 'Site logo at the bottom (right in Arabic · left in English)',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _ar
              ? 'موضع الشعار على ورقة الفحص'
              : 'Logo position on the checklist sheet',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(caption, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        Center(
          child: AspectRatio(
            aspectRatio: 210 / 297,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220, maxHeight: 310),
              child: CustomPaint(
                painter: _PaperLogoPainter(
                  kind: kind,
                  highlight: scheme.primary,
                  paper: scheme.surface,
                  border: scheme.outline.withValues(alpha: 0.55),
                  ink: scheme.onSurface.withValues(alpha: 0.18),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PaperLogoPainter extends CustomPainter {
  _PaperLogoPainter({
    required this.kind,
    required this.highlight,
    required this.paper,
    required this.border,
    required this.ink,
  });

  final ReportLogoSlotKind kind;
  final Color highlight;
  final Color paper;
  final Color border;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(6),
    );
    canvas.drawRRect(r, Paint()..color = paper);
    canvas.drawRRect(
      r,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // Fake header/title lines
    final line = Paint()..color = ink;
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.12, size.height * 0.12, size.width * 0.5, 6),
      line,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * 0.12,
        size.height * 0.16,
        size.width * 0.62,
        5,
      ),
      line,
    );
    // Fake table lines
    for (var i = 0; i < 8; i++) {
      final y = size.height * (0.28 + i * 0.06);
      canvas.drawRect(
        Rect.fromLTWH(size.width * 0.1, y, size.width * 0.8, 3),
        line,
      );
    }

    Rect slot;
    switch (kind) {
      case ReportLogoSlotKind.orgHeader:
        // Top-right on paper (absolute LTR corners of the sheet)
        slot = Rect.fromLTWH(
          size.width * 0.62,
          size.height * 0.04,
          size.width * 0.28,
          size.height * 0.07,
        );
      case ReportLogoSlotKind.zoneFooter:
        // Bottom-right (EN) — diagram shows absolute right; Arabic note says flips
        slot = Rect.fromLTWH(
          size.width * 0.62,
          size.height * 0.9,
          size.width * 0.28,
          size.height * 0.055,
        );
      case ReportLogoSlotKind.siteFooter:
        slot = Rect.fromLTWH(
          size.width * 0.1,
          size.height * 0.9,
          size.width * 0.28,
          size.height * 0.055,
        );
    }

    final fill = Paint()..color = highlight.withValues(alpha: 0.22);
    final stroke = Paint()
      ..color = highlight
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(slot, const Radius.circular(3)),
      fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(slot, const Radius.circular(3)),
      stroke,
    );

    // Label "LOGO"
    final tp = TextPainter(
      text: TextSpan(
        text: 'LOGO',
        style: TextStyle(
          color: highlight,
          fontSize: size.width * 0.045,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(slot.center.dx - tp.width / 2, slot.center.dy - tp.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _PaperLogoPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.highlight != highlight;
}
