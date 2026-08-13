import 'dart:typed_data';

import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('rejects empty and undecodable image bytes', () {
    expect(ImageUploadValidation.validate(Uint8List(0)).code, 'empty');
    expect(
      ImageUploadValidation.validate(Uint8List.fromList([1, 2, 3])).code,
      'invalid',
    );
  });

  test('rejects low resolution and accepts field resolution', () {
    final tiny = Uint8List.fromList(
      img.encodePng(img.Image(width: 80, height: 80)),
    );
    final field = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 640, height: 480)),
    );
    expect(ImageUploadValidation.validate(tiny).code, 'too_small');
    expect(ImageUploadValidation.validate(field).ok, isTrue);
  });
}
