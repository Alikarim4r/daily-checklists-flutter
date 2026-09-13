import 'dart:io';

import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'bundled report fonts render Arabic without a network request',
    () async {
      final fonts = await ReportFontLoader.load();
      final document = pw.Document(
        theme: buildInspectionReportTheme(
          arabic: true,
          latinRegular: fonts.latinRegular,
          latinBold: fonts.latinBold,
          arabicRegular: fonts.arabicRegular,
          arabicBold: fonts.arabicBold,
        ),
      );
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (_) => pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Text(
              'تقرير الفحص اليومي للمرافق — توقيع المفتش والإجراءات التصحيحية',
            ),
          ),
        ),
      );

      final bytes = await document.save();
      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(1000));
    },
  );

  test('long Arabic inspection rows paginate without clipping', () async {
    final inspection = Inspection(
      id: 'pdf-regression',
      siteId: 'site-test',
      buildingCode: 'B7-M',
      inspectionDate: DateTime(2026, 9, 12),
      locationLabel: 'موقع اختبار التقرير',
      inspectorName: 'مفتش الاختبار',
      items: List.generate(
        22,
        (index) => InspectionItem(
          itemIndex: index + 1,
          description: 'Mechanical plant inspection ${index + 1}',
          descriptionAr:
              'هل تعمل مضخات المياه وأنظمة التحكم بصورة طبيعية دون تسرب أو ضوضاء غير معتادة؟ تحقق من قراءات الضغط وحالة التوصيلات الكهربائية وسجّل أي انحراف لضمان التشغيل الآمن والمستمر.',
          response: ChecklistResponse.yes,
          actionsTaken:
              'تم فحص المعدات وتوثيق قراءات الضغط ودرجة الحرارة والتأكد من سلامة توصيلات التغذية وأنظمة الإنذار، مع تسجيل إجراءات المتابعة اللازمة.',
        ),
      ),
    );
    final bytes = await InspectionReportExporter().buildPdfBytes(
      inspection,
      language: 'ar',
      branding: const ReportBrandingBytes(orgNameAr: 'جهة اختبار'),
      paperTheme: FormPaperTheme.resolve(themeDb: 'classic_gold'),
    );
    expect(bytes.length, greaterThan(5000));
    // Optional artifact for visual QA; the normal suite writes no report.
    final output = Platform.environment['CHECKLIST_PDF_TEST_OUTPUT'];
    if (output != null) await File(output).writeAsBytes(bytes);
  });
}
