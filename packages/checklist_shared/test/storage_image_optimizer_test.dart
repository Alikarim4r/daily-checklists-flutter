import 'dart:typed_data';

import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('downsizes large evidence photos and emits compact JPEG', () {
    final source = img.Image(width: 3200, height: 2400);
    final input = Uint8List.fromList(img.encodePng(source));
    final output = StorageImageOptimizer.optimize(input);
    final decoded = img.decodeJpg(output);
    expect(decoded, isNotNull);
    expect(decoded!.width, lessThanOrEqualTo(1600));
    expect(decoded.height, lessThanOrEqualTo(1600));
    expect(output.length, lessThanOrEqualTo(2 * 1024 * 1024));
  });
}
