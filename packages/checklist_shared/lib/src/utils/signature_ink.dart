import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// Classic ballpoint blue ink used for technician signatures.
const Color kSignatureInkColor = Color(0xFF002D72);

/// Recolor opaque dark strokes in a signature PNG to [ink].
///
/// Existing signatures saved in black still render as blue ink on screen/PDF.
Uint8List recolorSignatureToBlueInk(
  Uint8List pngBytes, {
  Color ink = kSignatureInkColor,
}) {
  try {
    final decoded = img.decodePng(pngBytes) ?? img.decodeImage(pngBytes);
    if (decoded == null) return pngBytes;
    final out = decoded.convert(numChannels: 4);
    final inkR = (ink.r * 255.0).round().clamp(0, 255);
    final inkG = (ink.g * 255.0).round().clamp(0, 255);
    final inkB = (ink.b * 255.0).round().clamp(0, 255);
    for (var y = 0; y < out.height; y++) {
      for (var x = 0; x < out.width; x++) {
        final p = out.getPixel(x, y);
        final a = p.a.toInt();
        if (a < 8) continue;
        final r = p.r.toInt();
        final g = p.g.toInt();
        final b = p.b.toInt();
        final lum = (r + g + b) / 3.0;
        // Skip near-white background.
        if (lum >= 248 && a < 30) continue;
        if (lum >= 250) continue;
        // Keep stroke strong — less wash-out to white for a real ink look.
        final cover = ((250 - lum) / 250).clamp(0.65, 1.0) * (a / 255.0);
        final strength = cover.clamp(0.7, 1.0);
        final sr = (inkR * strength + 255 * (1 - strength)).round().clamp(
          0,
          255,
        );
        final sg = (inkG * strength + 255 * (1 - strength)).round().clamp(
          0,
          255,
        );
        final sb = (inkB * strength + 255 * (1 - strength)).round().clamp(
          0,
          255,
        );
        final outA = a < 120 ? 230 : 255;
        out.setPixelRgba(x, y, sr, sg, sb, outA);
      }
    }
    return Uint8List.fromList(img.encodePng(out));
  } catch (_) {
    return pngBytes;
  }
}
