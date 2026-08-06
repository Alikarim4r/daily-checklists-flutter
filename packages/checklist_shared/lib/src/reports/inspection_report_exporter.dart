import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/enums.dart';
import '../models/inspection.dart';
import '../repositories/inspection_repository.dart';
import '../utils/signature_ink.dart';

/// PDF export matching the on-screen A4 [ChecklistFormLayout] / MOEHE paper form.
class InspectionReportExporter {
  const InspectionReportExporter();

  static const _gold = PdfColor.fromInt(0xFFE8C547);
  static const _border = PdfColors.black;
  static const _okBlue = PdfColor.fromInt(0xFF3B82F6);
  static const _problemRed = PdfColor.fromInt(0xFFEF4444);
  static const _emptyGray = PdfColor.fromInt(0xFFCBD5E1);

  /// Build A4 form PDF and open the system share/save sheet.
  ///
  /// Avoids [Printing.layoutPdf] — sandboxed macOS without print entitlement
  /// and some Android OEMs show "This application does not support printing".
  Future<void> export(Inspection inspection, {String language = 'en'}) async {
    final bytes = await buildPdfBytes(inspection, language: language);
    final filename =
        'inspection_${inspection.buildingCode}_${inspection.dateIso}.pdf';
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }

  /// Optional: system print dialog (requires macOS print entitlement).
  Future<void> print(Inspection inspection, {String language = 'en'}) async {
    final bytes = await buildPdfBytes(inspection, language: language);
    final name =
        'inspection_${inspection.buildingCode}_${inspection.dateIso}';
    try {
      final info = await Printing.info();
      if (!info.canPrint) {
        await Printing.sharePdf(bytes: bytes, filename: '$name.pdf');
        return;
      }
      final ok = await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: name,
        format: PdfPageFormat.a4,
      );
      if (!ok) {
        await Printing.sharePdf(bytes: bytes, filename: '$name.pdf');
      }
    } catch (_) {
      await Printing.sharePdf(bytes: bytes, filename: '$name.pdf');
    }
  }

  /// Share/save without opening the print dialog (optional callers).
  Future<void> share(Inspection inspection, {String language = 'en'}) async {
    final bytes = await buildPdfBytes(inspection, language: language);
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'inspection_${inspection.buildingCode}_${inspection.dateIso}.pdf',
    );
  }

  Future<Uint8List> buildPdfBytes(
    Inspection inspection, {
    String language = 'en',
  }) async {
    final ar = language == 'ar';
    final items = [...inspection.items]
      ..sort((a, b) => a.itemIndex.compareTo(b.itemIndex));

    final baseFont = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();
    final arabicFont = await PdfGoogleFonts.notoNaskhArabicRegular();
    final theme = pw.ThemeData.withFont(
      base: baseFont,
      bold: boldFont,
      fontFallback: [arabicFont],
    ).copyWith(
      defaultTextStyle: pw.TextStyle(
        font: baseFont,
        fontSize: 9,
        color: PdfColors.black,
      ),
      header0: pw.TextStyle(
        font: boldFont,
        fontSize: 13,
        color: PdfColors.black,
      ),
    );

    final moeheLogo = await _loadImage(
      'packages/checklist_shared/assets/branding/moehe_logo.png',
    );
    final waseefLogo = await _loadImage(
      'packages/checklist_shared/assets/branding/logo_waseef.png',
    );
    final footerLogo = await _loadImage(
      'packages/checklist_shared/assets/branding/logo_footer2.png',
    );

    pw.MemoryImage? signatureImage;
    final sigPath = inspection.signaturePath;
    if (sigPath != null && sigPath.isNotEmpty) {
      try {
        final raw = await InspectionRepository(Supabase.instance.client)
            .downloadBytes(sigPath);
        if (raw != null && raw.isNotEmpty) {
          final blue = recolorSignatureToBlueInk(Uint8List.fromList(raw));
          signatureImage = pw.MemoryImage(blue);
        }
      } catch (_) {}
    }

    final disclaimer = ar
        ? 'توفر هذه القائمة المتطلبات الأساسية للفحوصات اليومية لخدمات البنية. عند تسجيل «لا» لأي بند أعلاه، يجب اتخاذ إجراء فوري لمعالجة المشكلة لضمان استمرار التشغيل الآمن.'
        : 'This checklist provides the basic requirements for hard services operations daily checks. Should a "No" be recorded for any of the above checklist items, immediate action to be taken to address the issues, to have safe, continued operation.';

    final doc = pw.Document(theme: theme);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        // Extra bottom margin so footer logos sit above the page edge.
        margin: const pw.EdgeInsets.fromLTRB(24, 22, 24, 18),
        theme: theme,
        footer: (context) => _pageFooter(
          elegancia: waseefLogo,
          waseef: footerLogo,
          disclaimer: disclaimer,
          ar: ar,
          isLastPage: context.pageNumber == context.pagesCount,
        ),
        build: (context) => [
          _header(inspection, ar, moeheLogo),
          pw.SizedBox(height: 6),
          _titleBanner(ar),
          pw.SizedBox(height: 8),
          _metaGrid(inspection, ar, signatureImage),
          pw.SizedBox(height: 10),
          _itemsTable(items, language, ar),
        ],
      ),
    );
    return doc.save();
  }

  Future<pw.MemoryImage?> _loadImage(String assetPath) async {
    try {
      final data = await rootBundle.load(assetPath);
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  pw.Widget _header(
    Inspection inspection,
    bool ar,
    pw.MemoryImage? logo,
  ) {
    final siteName = ar
        ? (inspection.siteNameAr.isNotEmpty
            ? inspection.siteNameAr
            : inspection.buildingCode)
        : (inspection.siteNameEn.isNotEmpty
            ? inspection.siteNameEn
            : inspection.buildingCode);
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _border, width: 1)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment:
                  ar ? pw.CrossAxisAlignment.end : pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  ar
                      ? 'خدمة الإدارة المتكاملة للمرافق لصالح وزارة التربية والتعليم والتعليم العالي'
                      : 'Integrated Facilities Management Service for MOEHE',
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                  ),
                  textAlign: ar ? pw.TextAlign.right : pw.TextAlign.left,
                  textDirection:
                      ar ? pw.TextDirection.rtl : pw.TextDirection.ltr,
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  ar
                      ? 'قائمة الفحص اليومي للمرافق - $siteName'
                      : 'Facilities Daily Inspection Checklist - $siteName',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                  ),
                  textAlign: ar ? pw.TextAlign.right : pw.TextAlign.left,
                  textDirection:
                      ar ? pw.TextDirection.rtl : pw.TextDirection.ltr,
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 10),
          if (logo != null)
            pw.Image(logo, height: 36)
          else
            pw.Text(
              'MOEHE',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
            ),
        ],
      ),
    );
  }

  pw.Widget _titleBanner(bool ar) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 7),
      decoration: pw.BoxDecoration(
        color: _gold,
        border: pw.Border.all(color: _border, width: 0.9),
      ),
      child: pw.Text(
        ar ? 'تقرير الفحص اليومي للمرافق' : 'Daily Facilities Inspection Report',
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          fontSize: 13,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.black,
        ),
        textDirection: ar ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      ),
    );
  }

  String _formatMetaDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yy = (d.year % 100).toString().padLeft(2, '0');
    return '$dd/$mm/$yy';
  }

  pw.Widget _metaGrid(
    Inspection inspection,
    bool ar,
    pw.MemoryImage? signatureImage,
  ) {
    final pin = inspection.pin.isNotEmpty ? inspection.pin : '—';

    // Fixed heights keep left Pin/Bldg rows locked to Signature + Date/Time.
    const double topH = 20;
    const double halfH = 24;
    const double sigH = halfH * 2; // 48 — matches Pin + Bldg stacked
    const double labelW = 78;
    const double inspLabelW = 92;
    const double dateLabelW = 40;
    const double dateBlockW = 112;
    const double bldgNoW = 30;
    const double floorLabelW = 52;

    pw.TextStyle labelStyle() => pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.black,
        );
    pw.TextStyle valueStyle() => pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.black,
        );

    pw.Widget gold(
      String text, {
      double? width,
      required double height,
      pw.Border? border,
    }) {
      return pw.Container(
        width: width,
        height: height,
        alignment: pw.Alignment.centerLeft,
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: pw.BoxDecoration(color: _gold, border: border),
        child: pw.Text(text, style: labelStyle()),
      );
    }

    pw.Widget value(
      String text, {
      double? width,
      required double height,
      pw.TextAlign align = pw.TextAlign.left,
      pw.Border? border,
    }) {
      return pw.Container(
        width: width,
        height: height,
        alignment: align == pw.TextAlign.center
            ? pw.Alignment.center
            : pw.Alignment.centerLeft,
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: pw.BoxDecoration(border: border),
        child: pw.Text(text, textAlign: align, style: valueStyle()),
      );
    }

    pw.BorderSide side([double w = 0.7]) =>
        pw.BorderSide(color: _border, width: w);

    // Internal dividers: right + bottom; outer edge comes from parent.
    pw.Border cellBorder({
      bool right = true,
      bool bottom = true,
    }) =>
        pw.Border(
          right: right ? side() : pw.BorderSide.none,
          bottom: bottom ? side() : pw.BorderSide.none,
        );

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _border, width: 0.7),
      ),
      child: pw.Column(
        children: [
          // ── Top: Location | Inspector Name ──────────────────────────
          pw.Row(
            children: [
              gold(
                ar ? 'الموقع:' : 'Location:',
                width: labelW,
                height: topH,
                border: cellBorder(),
              ),
              pw.Expanded(
                flex: 5,
                child: value(
                  inspection.locationLabel,
                  height: topH,
                  border: cellBorder(),
                ),
              ),
              gold(
                ar ? 'اسم المفتش:' : 'Inspector Name:',
                width: inspLabelW,
                height: topH,
                border: cellBorder(),
              ),
              pw.Expanded(
                flex: 5,
                child: value(
                  inspection.inspectorName,
                  height: topH,
                  border: cellBorder(right: false),
                ),
              ),
            ],
          ),
          // ── Bottom: Pin/Bldg  |  Signature + Date/Time ──────────────
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // LEFT half
              pw.Expanded(
                flex: 5,
                child: pw.Column(
                  children: [
                    pw.Row(
                      children: [
                        gold(
                          ar ? 'رقم القسيمة' : 'Pin No.',
                          width: labelW,
                          height: halfH,
                          border: cellBorder(),
                        ),
                        pw.Expanded(
                          child: value(
                            pin,
                            height: halfH,
                            border: cellBorder(right: false),
                          ),
                        ),
                      ],
                    ),
                    pw.Row(
                      children: [
                        gold(
                          ar ? 'رقم المبنى' : 'Bldg. No.',
                          width: labelW,
                          height: halfH,
                          border: cellBorder(bottom: false),
                        ),
                        value(
                          inspection.bldgNo,
                          width: bldgNoW,
                          height: halfH,
                          align: pw.TextAlign.center,
                          border: cellBorder(bottom: false),
                        ),
                        gold(
                          ar ? 'الطابق' : 'Floor no.',
                          width: floorLabelW,
                          height: halfH,
                          border: cellBorder(bottom: false),
                        ),
                        pw.Expanded(
                          child: value(
                            inspection.floorLabel,
                            height: halfH,
                            align: pw.TextAlign.center,
                            border: cellBorder(right: false, bottom: false),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Vertical split between halves
              pw.Container(width: 0.7, height: sigH, color: _border),
              // RIGHT half
              pw.Expanded(
                flex: 5,
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    gold(
                      ar ? 'توقيع المفتش:' : 'Inspector Signature:',
                      width: inspLabelW,
                      height: sigH,
                      border: cellBorder(bottom: false),
                    ),
                    pw.Expanded(
                      child: pw.Container(
                        height: sigH,
                        alignment: pw.Alignment.center,
                        padding: const pw.EdgeInsets.all(3),
                        decoration: pw.BoxDecoration(
                          border: cellBorder(bottom: false),
                        ),
                        child: signatureImage != null
                            ? pw.Image(
                                signatureImage,
                                height: sigH - 8,
                                fit: pw.BoxFit.contain,
                              )
                            : pw.SizedBox(height: sigH - 8),
                      ),
                    ),
                    pw.SizedBox(
                      width: dateBlockW,
                      height: sigH,
                      child: pw.Column(
                        children: [
                          pw.Row(
                            children: [
                              gold(
                                ar ? 'التاريخ' : 'Date',
                                width: dateLabelW,
                                height: halfH,
                                border: cellBorder(),
                              ),
                              pw.Expanded(
                                child: value(
                                  _formatMetaDate(inspection.inspectionDate),
                                  height: halfH,
                                  border: cellBorder(right: false),
                                ),
                              ),
                            ],
                          ),
                          pw.Row(
                            children: [
                              gold(
                                ar ? 'الوقت:' : 'Time:',
                                width: dateLabelW,
                                height: halfH,
                                border: cellBorder(bottom: false),
                              ),
                              pw.Expanded(
                                child: value(
                                  inspection.inspectionTime,
                                  height: halfH,
                                  border: cellBorder(
                                    right: false,
                                    bottom: false,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  PdfColor _markColor(InspectionItem item, ChecklistResponse column) {
    final selected = item.response?.shortCode == column.shortCode;
    if (!selected) return _emptyGray;
    return switch (item.checkColorFor(column)) {
      ColorCode.ok => _okBlue,
      ColorCode.problem => _problemRed,
      _ => PdfColors.black,
    };
  }

  pw.Widget _markCell(InspectionItem item, ChecklistResponse column) {
    final selected = item.response?.shortCode == column.shortCode;
    if (!selected) {
      return pw.Container(
        alignment: pw.Alignment.center,
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: pw.SizedBox(width: 14, height: 14),
      );
    }
    final color = _markColor(item, column);
    // Draw the tick geometrically — Unicode ✓ is missing in Noto and renders as ⊞.
    // PdfGraphics uses PDF coords (origin bottom-left, Y up) — invert Y vs Flutter.
    return pw.Container(
      alignment: pw.Alignment.center,
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 2),
      child: pw.SizedBox(
        width: 14,
        height: 14,
        child: pw.CustomPaint(
          size: const PdfPoint(14, 14),
          painter: (PdfGraphics canvas, PdfPoint size) {
            final h = size.y;
            canvas
              ..setStrokeColor(color)
              ..setLineWidth(1.7)
              ..setLineCap(PdfLineCap.round)
              ..setLineJoin(PdfLineJoin.round);
            // Classic ✓ : short stroke down-right, long stroke up-right (visual).
            canvas.drawLine(2.2, h - 7.2, 5.6, h - 11.0);
            canvas.drawLine(5.6, h - 11.0, 12.0, h - 2.8);
            canvas.strokePath();
          },
        ),
      ),
    );
  }

  pw.Widget _th(
    String text, {
    pw.TextAlign align = pw.TextAlign.center,
    double fontSize = 8,
  }) {
    return pw.Container(
      color: _gold,
      padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 3),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.black,
        ),
      ),
    );
  }

  pw.Widget _itemsTable(
    List<InspectionItem> items,
    String language,
    bool ar,
  ) {
    return pw.Table(
      border: pw.TableBorder.all(color: _border, width: 0.8),
      columnWidths: {
        0: const pw.FixedColumnWidth(30),
        1: const pw.FlexColumnWidth(4.8),
        2: const pw.FixedColumnWidth(30),
        3: const pw.FixedColumnWidth(30),
        4: const pw.FixedColumnWidth(30),
        5: const pw.FlexColumnWidth(3.2),
      },
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        pw.TableRow(
          children: [
            _th(ar ? 'م' : 'Item'),
            _th(ar ? 'الوصف' : 'Description', align: pw.TextAlign.left),
            _th(ar ? 'نعم' : 'Yes'),
            _th(ar ? 'لا' : 'No'),
            _th(ar ? 'غ.م' : 'N/A'),
            _th(
              ar
                  ? "إن كانت الإجابة لا، ما الإجراء؟"
                  : "If 'no', what are the actions taken?",
              align: pw.TextAlign.left,
              fontSize: 7,
            ),
          ],
        ),
        for (final item in items)
          pw.TableRow(
            verticalAlignment: pw.TableCellVerticalAlignment.middle,
            children: [
              pw.Container(
                alignment: pw.Alignment.center,
                padding:
                    const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                child: pw.Text(
                  '${item.itemIndex}',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                  ),
                ),
              ),
              pw.Container(
                alignment: pw.Alignment.centerLeft,
                padding: const pw.EdgeInsets.symmetric(
                  vertical: 6,
                  horizontal: 4,
                ),
                child: pw.Text(
                  item.descriptionFor(language),
                  style: const pw.TextStyle(
                    fontSize: 8,
                    lineSpacing: 1.15,
                    color: PdfColors.black,
                  ),
                  textDirection:
                      ar ? pw.TextDirection.rtl : pw.TextDirection.ltr,
                ),
              ),
              _markCell(item, ChecklistResponse.yes),
              _markCell(item, ChecklistResponse.no),
              _markCell(item, ChecklistResponse.na),
              pw.Container(
                alignment: pw.Alignment.centerLeft,
                padding: const pw.EdgeInsets.symmetric(
                  vertical: 6,
                  horizontal: 4,
                ),
                child: pw.Text(
                  item.actionsTaken,
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.black,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  /// Sticky page footer: partner logos always at bottom; disclaimer on last page.
  pw.Widget _pageFooter({
    required pw.MemoryImage? elegancia,
    required pw.MemoryImage? waseef,
    required String disclaimer,
    required bool ar,
    required bool isLastPage,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        if (isLastPage) ...[
          pw.SizedBox(height: 6),
          pw.Text(
            disclaimer,
            textAlign: ar ? pw.TextAlign.right : pw.TextAlign.left,
            style: pw.TextStyle(
              fontSize: 8,
              lineSpacing: 1.25,
              color: PdfColors.black,
            ),
            textDirection: ar ? pw.TextDirection.rtl : pw.TextDirection.ltr,
          ),
          pw.SizedBox(height: 8),
        ] else
          pw.SizedBox(height: 10),
        _footerLogos(elegancia, waseef),
        pw.SizedBox(height: 4),
        pw.Align(
          alignment: pw.Alignment.centerLeft,
          child: pw.Text(
            'Classification - Public',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
      ],
    );
  }

  pw.Widget _footerLogos(
    pw.MemoryImage? elegancia,
    pw.MemoryImage? waseef,
  ) {
    // Matches on-screen form: elegancia (left) · © · Waseef (right).
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (elegancia != null)
          pw.Image(elegancia, height: 22)
        else
          pw.SizedBox(width: 90, height: 22),
        pw.Text(
          '© MOEHE Facilities',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
        if (waseef != null)
          pw.Image(waseef, height: 30)
        else
          pw.SizedBox(width: 70, height: 30),
      ],
    );
  }
}
