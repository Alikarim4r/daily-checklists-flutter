import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';

/// Context lines burned onto inspection photos (Entry / Viewer).
class InspectionPhotoContext {
  const InspectionPhotoContext({
    required this.siteName,
    required this.buildingCode,
    required this.inspectionDateIso,
    required this.inspectionTime,
    required this.itemIndex,
    required this.itemDescription,
    required this.inspectorName,
    required this.kindLabel,
    required this.sourceLabel,
    this.organizationName = 'MOEHE Facilities Inspection',
  });

  final String organizationName;
  final String siteName;
  final String buildingCode;
  final String inspectionDateIso;
  final String inspectionTime;
  final int itemIndex;
  final String itemDescription;
  final String inspectorName;
  final String kindLabel;
  final String sourceLabel;

  List<String> watermarkLines() {
    final captured = DateFormat('yyyy-MM-dd HH:mm').format(
      DateTime.now().toUtc().add(const Duration(hours: 3)),
    );
    final desc = itemDescription.trim();
    final shortDesc =
        desc.length > 48 ? '${desc.substring(0, 45)}...' : desc;
    return [
      organizationName,
      [
        if (siteName.trim().isNotEmpty) siteName.trim(),
        if (buildingCode.trim().isNotEmpty) buildingCode.trim(),
      ].join(' | '),
      'Inspection: $inspectionDateIso'
          '${inspectionTime.trim().isEmpty ? '' : ' $inspectionTime'}',
      'Item $itemIndex'
          '${shortDesc.isEmpty ? '' : ': $shortDesc'}',
      'Kind: $kindLabel',
      'Inspector: ${inspectorName.trim().isEmpty ? '—' : inspectorName.trim()}',
      'Captured: $captured Asia/Qatar',
      'Source: $sourceLabel',
    ].where((l) => l.trim().isNotEmpty).toList();
  }
}

/// Burns a bottom-bar stamp onto JPEG inspection photos (meters-style).
class InspectionPhotoWatermark {
  static const _maxWidth = 1920;
  static const _jpegQuality = 85;

  Future<Uint8List> apply({
    required Uint8List imageBytes,
    required InspectionPhotoContext context,
  }) async {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) return imageBytes;

    var image = decoded;
    if (image.width > _maxWidth) {
      image = img.copyResize(image, width: _maxWidth);
    }

    final lines = context.watermarkLines();
    const lineHeight = 36;
    const padding = 24;
    final font = img.arial24;
    final textBlockHeight = lines.length * lineHeight + padding * 2;
    final barTop = (image.height - textBlockHeight).clamp(0, image.height);

    img.fillRect(
      image,
      x1: 0,
      y1: barTop,
      x2: image.width,
      y2: image.height,
      color: img.ColorRgba8(0, 0, 0, 170),
    );

    var y = barTop + padding;
    for (final line in lines) {
      img.drawString(
        image,
        line,
        font: font,
        x: padding,
        y: y,
        color: img.ColorRgba8(255, 255, 255, 255),
      );
      y += lineHeight;
    }

    return Uint8List.fromList(img.encodeJpg(image, quality: _jpegQuality));
  }
}
