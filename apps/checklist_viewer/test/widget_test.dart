import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('inspection status enum', () {
    expect(InspectionStatus.fromDb('submitted'), InspectionStatus.submitted);
    expect(ChecklistResponse.fromDb('Y'), ChecklistResponse.yes);
  });
}
