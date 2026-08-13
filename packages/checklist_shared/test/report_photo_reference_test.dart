import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('submitted reports cannot silently omit a signature', () {
    final inspection = Inspection(
      id: 'inspection',
      siteId: 'site',
      buildingCode: 'B1',
      inspectionDate: DateTime(2026, 8, 13),
      status: InspectionStatus.submitted,
    );

    expect(
      () => validateInspectionReportEvidence(inspection),
      throwsA(isA<InspectionReportEvidenceException>()),
    );
  });

  test('draft report preview may be generated before signing', () {
    final inspection = Inspection(
      id: 'inspection',
      siteId: 'site',
      buildingCode: 'B1',
      inspectionDate: DateTime(2026, 8, 13),
    );

    expect(() => validateInspectionReportEvidence(inspection), returnsNormally);
  });

  test('photo references stay bound to item and photo order', () {
    final item12 = InspectionItem(itemIndex: 12, description: 'Second item')
      ..setPhotoPairs([
        InspectionPhotoPair(
          id: 'p2',
          issuePath: 'org/site/inspection/12_issue.jpg',
          fixPath: 'org/site/inspection/12_fix.jpg',
        ),
      ]);
    final item5 = InspectionItem(itemIndex: 5, description: 'First item')
      ..setPhotoPairs([
        InspectionPhotoPair(
          id: 'p1',
          issuePath: 'org/site/inspection/5_issue.jpg',
        ),
      ]);

    final references = buildInspectionPhotoReferences([item12, item5]);

    expect(references['org/site/inspection/5_issue.jpg'], '5.1');
    expect(references['org/site/inspection/12_issue.jpg'], '12.1');
    expect(references['org/site/inspection/12_fix.jpg'], '12.2');
  });
}
