import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/ops_metrics.dart';

class OpsReportExporter {
  const OpsReportExporter();

  Future<Uint8List> buildPdf({
    required OpsSnapshot snapshot,
    required String language,
    String scopeLabel = '',
  }) async {
    final ar = language == 'ar';
    final base = await PdfGoogleFonts.notoSansRegular();
    final bold = await PdfGoogleFonts.notoSansBold();
    final arabic = await PdfGoogleFonts.notoNaskhArabicRegular();
    final theme = pw.ThemeData.withFont(
      base: base,
      bold: bold,
      fontFallback: [arabic],
    );
    final direction = ar ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    String pct(double value) => '${(value * 100).clamp(0, 100).round()}%';
    String iso(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';

    pw.Widget metric(String label, String value, PdfColor color) =>
        pw.Container(
          width: 128,
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: color, width: 0.8),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 5),
              pw.Text(
                value,
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        );

    final doc = pw.Document(theme: theme);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (_) => [
          pw.Text(
            ar ? 'تقرير المتابعة والإشراف' : 'Ops & Supervision Report',
            textDirection: direction,
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            '${iso(snapshot.dateFrom)} — ${iso(snapshot.dateTo)}'
            '${scopeLabel.trim().isEmpty ? '' : ' · $scopeLabel'}',
            textDirection: direction,
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 16),
          pw.Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              metric(
                ar ? 'الالتزام اليومي' : 'Daily compliance',
                pct(snapshot.dailyCompliance),
                PdfColors.green700,
              ),
              metric(
                ar ? 'بانتظار الاعتماد' : 'Pending approval',
                '${snapshot.pendingReviewCount}',
                PdfColors.blue700,
              ),
              metric(
                ar ? 'قوائم متأخرة' : 'Overdue inspections',
                '${snapshot.overdueInspectionCount}',
                PdfColors.red700,
              ),
              metric(
                ar ? 'مشاكل مفتوحة' : 'Open problems',
                '${snapshot.openProblemCount}',
                PdfColors.orange700,
              ),
              metric(
                ar ? 'نسبة الإنجاز' : 'Completion rate',
                pct(snapshot.completionRate),
                PdfColors.teal700,
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            ar ? 'ترتيب المواقع' : 'Site ranking',
            textDirection: direction,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: ar
                ? [
                    'الموقع',
                    'النتيجة',
                    'المثالي',
                    'الاعتماد',
                    'مفتوحة',
                    'متأخرة',
                  ]
                : ['Site', 'Score', 'Ideal', 'Approved', 'Open', 'Overdue'],
            data: [
              for (final row in ([
                ...snapshot.sites,
              ]..sort((a, b) => b.score.compareTo(a.score))))
                [
                  '${row.buildingCode} — ${row.siteName}',
                  pct(row.score),
                  pct(row.idealRate),
                  pct(row.approvalRate),
                  '${row.openProblemCount}',
                  '${row.overdueCount}',
                ],
            ],
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
              fontSize: 8,
            ),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColors.blueGrey800,
            ),
            cellStyle: const pw.TextStyle(fontSize: 7.5),
            cellAlignment: ar
                ? pw.Alignment.centerRight
                : pw.Alignment.centerLeft,
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            ar ? 'المتابعات المطلوبة' : 'Required follow-ups',
            textDirection: direction,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          if (snapshot.followUps.isEmpty)
            pw.Text(
              ar ? 'لا توجد متابعات ضمن النطاق.' : 'No follow-ups in scope.',
              textDirection: direction,
            )
          else
            for (final item in snapshot.followUps.take(100))
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 5),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.grey300),
                  ),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      item.title,
                      textDirection: direction,
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      item.subtitle,
                      textDirection: direction,
                      style: const pw.TextStyle(
                        fontSize: 8,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
    return doc.save();
  }

  Future<void> sharePdf({
    required OpsSnapshot snapshot,
    required String language,
    String scopeLabel = '',
  }) async {
    final bytes = await buildPdf(
      snapshot: snapshot,
      language: language,
      scopeLabel: scopeLabel,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'ops-supervision-${snapshot.dateFrom.year.toString().padLeft(4, '0')}'
          '${snapshot.dateFrom.month.toString().padLeft(2, '0')}'
          '${snapshot.dateFrom.day.toString().padLeft(2, '0')}-'
          '${snapshot.dateTo.year.toString().padLeft(4, '0')}'
          '${snapshot.dateTo.month.toString().padLeft(2, '0')}'
          '${snapshot.dateTo.day.toString().padLeft(2, '0')}.pdf',
    );
  }
}
