import 'dart:typed_data';

import 'package:image/image.dart' as img;

class ImageUploadValidation {
  const ImageUploadValidation._({
    required this.ok,
    required this.code,
    required this.width,
    required this.height,
  });

  final bool ok;
  final String code;
  final int width;
  final int height;

  String messageFor(String language) {
    final ar = language == 'ar';
    return switch (code) {
      'empty' => ar ? 'ملف الصورة فارغ.' : 'The image file is empty.',
      'too_large' =>
        ar
            ? 'حجم الصورة أكبر من الحد المسموح.'
            : 'The image file is larger than allowed.',
      'invalid' =>
        ar
            ? 'الملف ليس صورة صالحة أو مدعومة.'
            : 'The file is not a valid supported image.',
      'too_small' =>
        ar
            ? 'دقة الصورة منخفضة جدًا. التقط أو اختر صورة أوضح.'
            : 'Image resolution is too low. Choose a clearer image.',
      'too_many_pixels' =>
        ar
            ? 'أبعاد الصورة كبيرة جدًا للمعالجة الآمنة.'
            : 'Image dimensions are too large to process safely.',
      _ => '',
    };
  }

  static ImageUploadValidation validate(
    Uint8List bytes, {
    int minWidth = 320,
    int minHeight = 240,
    int maxBytes = 15 * 1024 * 1024,
    int maxPixels = 40 * 1000 * 1000,
  }) {
    if (bytes.isEmpty) {
      return const ImageUploadValidation._(
        ok: false,
        code: 'empty',
        width: 0,
        height: 0,
      );
    }
    if (bytes.length > maxBytes) {
      return const ImageUploadValidation._(
        ok: false,
        code: 'too_large',
        width: 0,
        height: 0,
      );
    }
    img.Image? decoded;
    try {
      // Some decoders throw while probing very short or corrupted byte
      // sequences instead of returning null. Treat every such failure as an
      // invalid upload and keep it out of the capture/upload pipeline.
      decoded = img.decodeImage(bytes);
    } catch (_) {
      decoded = null;
    }
    if (decoded == null) {
      return const ImageUploadValidation._(
        ok: false,
        code: 'invalid',
        width: 0,
        height: 0,
      );
    }
    if (decoded.width * decoded.height > maxPixels) {
      return ImageUploadValidation._(
        ok: false,
        code: 'too_many_pixels',
        width: decoded.width,
        height: decoded.height,
      );
    }
    if (decoded.width < minWidth || decoded.height < minHeight) {
      return ImageUploadValidation._(
        ok: false,
        code: 'too_small',
        width: decoded.width,
        height: decoded.height,
      );
    }
    return ImageUploadValidation._(
      ok: true,
      code: 'ok',
      width: decoded.width,
      height: decoded.height,
    );
  }
}
