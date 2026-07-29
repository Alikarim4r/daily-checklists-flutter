import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('checklist lists include DEFAULT template', () {
    expect(kChecklistLists.containsKey('DEFAULT'), isTrue);
    expect(kChecklistLists['DEFAULT'], isNotEmpty);
  });

  test('buildings config has B1', () {
    expect(kBuildingsConfig.containsKey('B1'), isTrue);
  });
}
