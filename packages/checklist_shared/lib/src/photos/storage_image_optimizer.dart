import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Storage-oriented image normalization for user-uploaded evidence.
/// Keeps evidence readable while preventing multi-megabyte originals from
/// being persisted when the app is used at public scale.
class StorageImageOptimizer {
  static const int maxDimension = 1600;
  static const int jpegQuality = 76;
  static const int maxOutputBytes = 2 * 1024 * 1024;

  static Uint8List optimize(Uint8List bytes) {
    try {
      var decoded = img.decodeImage(bytes);
      if (decoded == null) return bytes;
      if (decoded.width > maxDimension || decoded.height > maxDimension) {
        decoded = img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? maxDimension : null,
          height: decoded.height > decoded.width ? maxDimension : null,
          interpolation: img.Interpolation.average,
        );
      }
      var quality = jpegQuality;
      var out = Uint8List.fromList(img.encodeJpg(decoded, quality: quality));
      while (out.length > maxOutputBytes && quality > 50) {
        quality -= 8;
        out = Uint8List.fromList(img.encodeJpg(decoded, quality: quality));
      }
      return out;
    } catch (_) {
      return bytes;
    }
  }
}
