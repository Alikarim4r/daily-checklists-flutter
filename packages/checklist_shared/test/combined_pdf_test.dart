import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

Inspection testInspection(String id) => Inspection(
  id: id,
  siteId: id,
  siteNameEn: 'Washroom $id',
  buildingCode: 'B1',
  locationLabel: 'MOEHE Headquarters / Building 1',
  pin: 'A/66170852/01-0013',
  floorLabel: 'LGF',
  inspectionDate: DateTime(2026, 10, 10),
  items: [
    InspectionItem(
      itemIndex: 1,
      description: 'Floors clean?',
      defaultAnswer: 'Y',
    ),
    InspectionItem(
      itemIndex: 2,
      description: 'Washbasins clean?',
      defaultAnswer: 'Y',
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('single combined A4 PDF contains all unfilled checklists', () async {
    final exporter = InspectionReportExporter();
    final fonts = InspectionReportFonts(
      latinRegular: pw.Font.helvetica(),
      latinBold: pw.Font.helveticaBold(),
      arabicRegular: pw.Font.helvetica(),
      arabicBold: pw.Font.helveticaBold(),
    );
    const branding = ReportBrandingBytes(orgNameEn: 'MOEHE Headquarters');
    const paper = FormPaperTheme.classicGold;
    final a = testInspection('A');
    final b = testInspection('B');
    final single = await exporter.buildPdfBytes(
      a,
      language: 'en',
      branding: branding,
      paperTheme: paper,
      fonts: fonts,
    );
    var callbacks = 0;
    final combined = await exporter.buildBatchPdfBytes(
      [a, b],
      language: 'en',
      branding: branding,
      paperTheme: paper,
      fonts: fonts,
      onProgress: (n, total) {
        callbacks++;
        expect(total, 2);
        expect(n, inInclusiveRange(1, 2));
      },
    );
    expect(combined.take(4).toList(), [37, 80, 68, 70]);
    expect(combined.length, greaterThan(single.length));
    expect(callbacks, 2);
  });
}
