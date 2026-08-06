import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// Classic ballpoint blue ink used for technician signatures.
const Color kSignatureInkColor = Color(0xFF0B3D91);

/// Recolor opaque dark strokes in a signature PNG to [kSignatureInkColor].
///
/// Existing signatures saved in black still render as blue ink on screen/PDF.
Uint8List recolorSignatureToBlueInk(Uint8List pngBytes) {
  try {
    final decoded = img.decodePng(pngBytes) ?? img.decodeImage(pngBytes);
    if (decoded == null) return pngBytes;
    final out = decoded.convert(numChannels: 4);
    const inkR = 0x0B;
    const inkG = 0x3D;
    const inkB = 0x91;
    for (var y = 0; y < out.height; y++) {
      for (var x = 0; x < out.width; x++) {
        final p = out.getPixel(x, y);
        final a = p.a.toInt();
        if (a < 8) continue;
        final r = p.r.toInt();
        final g = p.g.toInt();
        final b = p.b.toInt();
        final lum = (r + g + b) / 3.0;
        // Any non-white stroke (incl. anti-aliased gray) becomes blue ink.
        if (lum >= 245 && a < 40) continue;
        if (lum >= 245) continue;
        final strength = ((245 - lum) / 245).clamp(0.25, 1.0) * (a / 255.0);
        final sr = (inkR * strength + 255 * (1 - strength)).round().clamp(0, 255);
        final sg = (inkG * strength + 255 * (1 - strength)).round().clamp(0, 255);
        final sb = (inkB * strength + 255 * (1 - strength)).round().clamp(0, 255);
        out.setPixelRgba(x, y, sr, sg, sb, a < 180 ? 220 : 255);
      }
    }
    return Uint8List.fromList(img.encodePng(out));
  } catch (_) {
    return pngBytes;
  }
}
