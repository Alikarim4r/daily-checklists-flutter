import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Pan/zoom an imported logo inside a fixed 4×2 cm slot, then export cropped bytes.
Future<Uint8List?> showReportLogoCropDialog({
  required BuildContext context,
  required Uint8List imageBytes,
  required double slotWidth,
  required double slotHeight,
  required String title,
}) {
  return showDialog<Uint8List>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ReportLogoCropDialog(
      imageBytes: imageBytes,
      slotWidth: slotWidth,
      slotHeight: slotHeight,
      title: title,
    ),
  );
}

class _ReportLogoCropDialog extends StatefulWidget {
  const _ReportLogoCropDialog({
    required this.imageBytes,
    required this.slotWidth,
    required this.slotHeight,
    required this.title,
  });

  final Uint8List imageBytes;
  final double slotWidth;
  final double slotHeight;
  final String title;

  @override
  State<_ReportLogoCropDialog> createState() => _ReportLogoCropDialogState();
}

class _ReportLogoCropDialogState extends State<_ReportLogoCropDialog> {
  final _boundaryKey = GlobalKey();
  final _transform = TransformationController();
  bool _exporting = false;

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final boundary =
          _boundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null || !mounted) return;
      Navigator.of(context).pop(byteData.buffer.asUint8List());
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not crop logo')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: widget.slotWidth + 48,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Pan and zoom to fit the 4×2 cm slot, then save.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Container(
              width: widget.slotWidth,
              height: widget.slotHeight,
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              clipBehavior: Clip.hardEdge,
              child: RepaintBoundary(
                key: _boundaryKey,
                child: InteractiveViewer(
                  transformationController: _transform,
                  minScale: 0.4,
                  maxScale: 6,
                  constrained: false,
                  child: Image.memory(
                    widget.imageBytes,
                    width: widget.slotWidth * 2,
                    height: widget.slotHeight * 2,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _exporting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _exporting ? null : _export,
          child: _exporting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save logo'),
        ),
      ],
    );
  }
}
