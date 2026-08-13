import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

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

  test('Arabic reports shape text with Arabic fonts as the primary family', () {
    final latinRegular = pw.Font.helvetica();
    final latinBold = pw.Font.helveticaBold();
    final arabicRegular = pw.Font.courier();
    final arabicBold = pw.Font.courierBold();

    final theme = buildInspectionReportTheme(
      arabic: true,
      latinRegular: latinRegular,
      latinBold: latinBold,
      arabicRegular: arabicRegular,
      arabicBold: arabicBold,
    );

    expect(theme.defaultTextStyle.font, same(arabicRegular));
    expect(theme.defaultTextStyle.fontNormal, same(arabicRegular));
    expect(theme.defaultTextStyle.fontBold, same(arabicBold));
    expect(theme.header0.fontBold, same(arabicBold));
    expect(theme.defaultTextStyle.fontFallback, contains(latinRegular));
  });

  test('English reports keep the Latin family primary', () {
    final latinRegular = pw.Font.helvetica();
    final latinBold = pw.Font.helveticaBold();
    final arabicRegular = pw.Font.courier();
    final arabicBold = pw.Font.courierBold();

    final theme = buildInspectionReportTheme(
      arabic: false,
      latinRegular: latinRegular,
      latinBold: latinBold,
      arabicRegular: arabicRegular,
      arabicBold: arabicBold,
    );

    expect(theme.defaultTextStyle.font, same(latinRegular));
    expect(theme.defaultTextStyle.fontBold, same(latinBold));
    expect(theme.defaultTextStyle.fontFallback, contains(arabicRegular));
  });
}
