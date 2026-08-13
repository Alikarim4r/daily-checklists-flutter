import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';

/// Context lines burned onto inspection photos (Entry / Viewer).
class InspectionPhotoContext {
  const InspectionPhotoContext({
    required this.organizationName,
    required this.zoneName,
    required this.siteName,
    required this.buildingCode,
    required this.inspectionDateIso,
    required this.inspectionTime,
    required this.itemIndex,
    required this.itemDescription,
    required this.inspectorName,
    required this.kindLabel,
    required this.sourceLabel,
  });

  final String organizationName;
  final String zoneName;
  final String siteName;
  final String buildingCode;
  final String inspectionDateIso;
  final String inspectionTime;
  final int itemIndex;
  final String itemDescription;
  final String inspectorName;
  final String kindLabel;
  final String sourceLabel;

  List<String> watermarkLines({required bool arabic}) {
    final captured = DateFormat(
      'yyyy-MM-dd HH:mm',
    ).format(DateTime.now().toUtc().add(const Duration(hours: 3)));
    final desc = itemDescription.trim();
    final shortDesc = desc.length > 72 ? '${desc.substring(0, 69)}…' : desc;
    final org = organizationName.trim();
    final zone = zoneName.trim();
    final site = siteName.trim();
    final code = buildingCode.trim();

    return [
      if (org.isNotEmpty) org,
      if (zone.isNotEmpty) zone,
      [if (site.isNotEmpty) site, if (code.isNotEmpty) code].join(' · '),
      arabic
          ? 'الفحص: $inspectionDateIso'
                '${inspectionTime.trim().isEmpty ? '' : ' $inspectionTime'}'
          : 'Inspection: $inspectionDateIso'
                '${inspectionTime.trim().isEmpty ? '' : ' $inspectionTime'}',
      arabic
          ? 'البند $itemIndex${shortDesc.isEmpty ? '' : ': $shortDesc'}'
          : 'Item $itemIndex${shortDesc.isEmpty ? '' : ': $shortDesc'}',
      arabic
          ? 'النوع: $kindLabel  ·  المصدر: $sourceLabel'
          : 'Kind: $kindLabel  ·  Source: $sourceLabel',
      arabic
          ? 'المفتش: ${inspectorName.trim().isEmpty ? '—' : inspectorName.trim()}'
          : 'Inspector: ${inspectorName.trim().isEmpty ? '—' : inspectorName.trim()}',
      arabic
          ? 'وقت الالتقاط: $captured آسيا/قطر'
          : 'Captured: $captured Asia/Qatar',
    ].where((line) => line.trim().isNotEmpty).toList();
  }
}

/// Burns a readable transparent stamp onto an image.
///
/// Flutter's text engine is used instead of a bitmap font so Arabic shaping,
/// joining and right-to-left ordering remain correct on mobile, desktop and web.
class InspectionPhotoWatermark {
  static const _maxWidth = 1920;
  static const _jpegQuality = 88;
  static const _padding = 18.0;

  Future<Uint8List> apply({
    required Uint8List imageBytes,
    required InspectionPhotoContext context,
    bool arabic = false,
  }) async {
    ui.Codec? codec;
    ui.Image? source;
    ui.Image? rendered;
    ui.Picture? picture;
    try {
      codec = await ui.instantiateImageCodec(imageBytes);
      var frame = await codec.getNextFrame();
      source = frame.image;
      if (source.width > _maxWidth) {
        source.dispose();
        source = null;
        codec.dispose();
        codec = null;
        codec = await ui.instantiateImageCodec(
          imageBytes,
          targetWidth: _maxWidth,
        );
        frame = await codec.getNextFrame();
        source = frame.image;
      }

      final width = source.width;
      final height = source.height;
      final textDirection = arabic
          ? ui.TextDirection.rtl
          : ui.TextDirection.ltr;
      final lines = context.watermarkLines(arabic: arabic);
      final availableTextWidth = math.max(40.0, width - _padding * 2);
      final maxTextWidth = (width * 0.92)
          .clamp(math.min(220.0, availableTextWidth), availableTextWidth)
          .toDouble();
      final painters = <TextPainter>[];
      var textHeight = 0.0;
      var widest = 0.0;
      for (var index = 0; index < lines.length; index++) {
        final hierarchy = index < 3;
        final painter = TextPainter(
          text: TextSpan(
            text: lines[index],
            style: TextStyle(
              color: hierarchy ? const Color(0xFFFFEC96) : Colors.white,
              fontSize: hierarchy ? 25 : 22,
              fontWeight: hierarchy ? FontWeight.w700 : FontWeight.w600,
              height: 1.12,
              shadows: const [
                Shadow(color: Colors.black, blurRadius: 4),
                Shadow(color: Colors.black, offset: Offset(1, 1)),
              ],
            ),
          ),
          textDirection: textDirection,
          textAlign: arabic ? TextAlign.right : TextAlign.left,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: maxTextWidth);
        painters.add(painter);
        textHeight += painter.height + 5;
        widest = widest < painter.width ? painter.width : widest;
      }

      final cushionWidth = (widest + _padding * 2)
          .clamp(math.min(240.0, width.toDouble()), width.toDouble())
          .toDouble();
      final cushionHeight = (textHeight + _padding * 2)
          .clamp(math.min(80.0, height.toDouble()), height.toDouble())
          .toDouble();
      final left = arabic ? width.toDouble() - cushionWidth : 0.0;
      final top = height.toDouble() - cushionHeight;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImage(source, Offset.zero, Paint());
      canvas.drawRect(
        Rect.fromLTWH(left, top, cushionWidth, cushionHeight),
        Paint()..color = const Color.fromRGBO(0, 0, 0, 0.48),
      );
      canvas.drawRect(
        Rect.fromLTWH(left, top, cushionWidth, 4),
        Paint()..color = const Color(0xFFE8C547),
      );

      var y = top + _padding;
      for (final painter in painters) {
        final x = arabic
            ? left + cushionWidth - _padding - painter.width
            : left + _padding;
        painter.paint(canvas, Offset(x, y));
        y += painter.height + 5;
      }

      picture = recorder.endRecording();
      rendered = await picture.toImage(width, height);
      final png = await rendered.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) return imageBytes;
      final decoded = img.decodePng(png.buffer.asUint8List());
      if (decoded == null) return png.buffer.asUint8List();
      return Uint8List.fromList(img.encodeJpg(decoded, quality: _jpegQuality));
    } catch (_) {
      // A stamp failure must not destroy a valid field photo.
      return imageBytes;
    } finally {
      picture?.dispose();
      rendered?.dispose();
      source?.dispose();
      codec?.dispose();
    }
  }
}
