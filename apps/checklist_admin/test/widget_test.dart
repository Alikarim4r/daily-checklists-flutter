import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('admin role gates', () {
    expect(UserRole.superAdmin.canUseAdmin, isTrue);
    expect(UserRole.viewer.canUseAdmin, isFalse);
    expect(UserRole.superAdmin.canDeleteInspections, isTrue);
  });
}
