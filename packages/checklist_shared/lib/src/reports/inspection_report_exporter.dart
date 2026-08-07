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
import '../utils/storage_path_list.dart';

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

    final repo = InspectionRepository(Supabase.instance.client);
    final photoLinks = <String, String>{};
    for (final item in items) {
      for (final photo in item.remarkPhotos) {
        if (photoLinks.containsKey(photo.path)) continue;
        final url = await repo.signedUrl(photo.path, expiresIn: 7 * 24 * 3600);
        if (url != null && url.isNotEmpty) {
          photoLinks[photo.path] = url;
        }
      }
    }

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
          ar: ar,
          elegancia: waseefLogo,
          waseef: footerLogo,
        ),
        build: (context) => [
          _header(inspection, ar, moeheLogo),
          pw.SizedBox(height: 6),
          _titleBanner(ar),
          pw.SizedBox(height: 8),
          _metaGrid(inspection, ar, signatureImage),
          pw.SizedBox(height: 10),
          _itemsTable(items, language, ar, photoLinks),
          pw.SizedBox(height: 10),
          pw.Text(
            disclaimer,
            textAlign: ar ? pw.TextAlign.right : pw.TextAlign.left,
            style: pw.TextStyle(
              fontSize: 8.5,
              lineSpacing: 1.3,
              color: PdfColors.black,
            ),
            textDirection: ar ? pw.TextDirection.rtl : pw.TextDirection.ltr,
          ),
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

    final logoWidget = logo != null
        ? pw.Image(logo, height: 36)
        : pw.Text(
            'MOEHE',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
          );

    // Titles hug the edge opposite the logo — not centered in the gap.
    final titles = pw.ConstrainedBox(
      constraints: const pw.BoxConstraints(maxWidth: 340),
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
            textDirection: ar ? pw.TextDirection.rtl : pw.TextDirection.ltr,
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
            textDirection: ar ? pw.TextDirection.rtl : pw.TextDirection.ltr,
          ),
        ],
      ),
    );

    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _border, width: 1)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: ar
            ? [
                logoWidget,
                pw.Expanded(
                  child: pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: titles,
                  ),
                ),
              ]
            : [
                pw.Expanded(
                  child: pw.Align(
                    alignment: pw.Alignment.centerLeft,
                    child: titles,
                  ),
                ),
                logoWidget,
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
    final dir = ar ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final startAlign = ar ? pw.Alignment.centerRight : pw.Alignment.centerLeft;
    final startText = ar ? pw.TextAlign.right : pw.TextAlign.left;

    const double rowH = 18;
    const double halfH = 22;
    const double sigH = halfH * 2;
    const double labelW = 78;
    const double inspLabelW = 92;
    const double dateLabelW = 38;
    const double dateBlockW = 108;
    const double bldgNoW = 28;
    const double floorLabelW = 50;

    pw.TextStyle labelStyle() => pw.TextStyle(
          fontSize: 7.5,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.black,
        );
    pw.TextStyle valueStyle() => pw.TextStyle(
          fontSize: 8.5,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.black,
        );

    pw.Border cellBorderAll() =>
        pw.Border.all(color: _border, width: 0.75);

    pw.Widget box({
      required double height,
      double? width,
      PdfColor? bg,
      required pw.Widget child,
      pw.Alignment? align,
    }) {
      return pw.Container(
        width: width,
        height: height,
        alignment: align ?? startAlign,
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1),
        decoration: pw.BoxDecoration(
          color: bg,
          border: cellBorderAll(),
        ),
        child: child,
      );
    }

    pw.Widget goldLabel(
      String text, {
      required double width,
      required double height,
    }) {
      return box(
        width: width,
        height: height,
        bg: _gold,
        child: pw.Text(
          text,
          style: labelStyle(),
          textAlign: startText,
          textDirection: dir,
        ),
      );
    }

    pw.Widget val(
      String text, {
      double? width,
      required double height,
      pw.TextAlign? align,
      bool forceLtr = false,
    }) {
      final a = align ?? startText;
      return box(
        width: width,
        height: height,
        align: a == pw.TextAlign.center
            ? pw.Alignment.center
            : (a == pw.TextAlign.right
                ? pw.Alignment.centerRight
                : pw.Alignment.centerLeft),
        child: pw.Text(
          text,
          textAlign: a,
          style: valueStyle(),
          textDirection: forceLtr ? pw.TextDirection.ltr : dir,
        ),
      );
    }

    List<pw.Widget> pair(pw.Widget label, pw.Widget value) =>
        ar ? [value, label] : [label, value];

    final locationHalf = pw.Expanded(
      child: pw.Row(
        children: pair(
          goldLabel(
            ar ? 'الموقع:' : 'Location:',
            width: labelW,
            height: rowH,
          ),
          pw.Expanded(
            child: val(inspection.locationLabel, height: rowH, forceLtr: !ar),
          ),
        ),
      ),
    );
    final nameHalf = pw.Expanded(
      child: pw.Row(
        children: pair(
          goldLabel(
            ar ? 'اسم المفتش:' : 'Inspector Name:',
            width: inspLabelW,
            height: rowH,
          ),
          pw.Expanded(
            child: val(inspection.inspectorName, height: rowH, forceLtr: true),
          ),
        ),
      ),
    );

    final pinRow = pw.SizedBox(
      height: halfH,
      child: pw.Row(
        children: pair(
          goldLabel(
            ar ? 'رقم القسيمة' : 'Pin No.',
            width: labelW,
            height: halfH,
          ),
          pw.Expanded(child: val(pin, height: halfH, forceLtr: true)),
        ),
      ),
    );
    final bldgRow = pw.SizedBox(
      height: halfH,
      child: pw.Row(
        children: ar
            ? [
                pw.Expanded(
                  child: val(
                    inspection.floorLabel,
                    height: halfH,
                    align: pw.TextAlign.center,
                    forceLtr: true,
                  ),
                ),
                goldLabel(
                  ar ? 'الطابق' : 'Floor no.',
                  width: floorLabelW,
                  height: halfH,
                ),
                val(
                  inspection.bldgNo,
                  width: bldgNoW,
                  height: halfH,
                  align: pw.TextAlign.center,
                  forceLtr: true,
                ),
                goldLabel(
                  ar ? 'رقم المبنى' : 'Bldg. No.',
                  width: labelW,
                  height: halfH,
                ),
              ]
            : [
                goldLabel(
                  ar ? 'رقم المبنى' : 'Bldg. No.',
                  width: labelW,
                  height: halfH,
                ),
                val(
                  inspection.bldgNo,
                  width: bldgNoW,
                  height: halfH,
                  align: pw.TextAlign.center,
                ),
                goldLabel(
                  ar ? 'الطابق' : 'Floor no.',
                  width: floorLabelW,
                  height: halfH,
                ),
                pw.Expanded(
                  child: val(
                    inspection.floorLabel,
                    height: halfH,
                    align: pw.TextAlign.center,
                  ),
                ),
              ],
      ),
    );

    final leftHalf = pw.Expanded(
      child: pw.Column(children: [pinRow, bldgRow]),
    );

    final dateBlock = pw.SizedBox(
      width: dateBlockW,
      height: sigH,
      child: pw.Column(
        children: [
          pw.SizedBox(
            height: halfH,
            child: pw.Row(
              children: pair(
                goldLabel(
                  ar ? 'التاريخ' : 'Date',
                  width: dateLabelW,
                  height: halfH,
                ),
                pw.Expanded(
                  child: val(
                    _formatMetaDate(inspection.inspectionDate),
                    height: halfH,
                    forceLtr: true,
                  ),
                ),
              ),
            ),
          ),
          pw.SizedBox(
            height: halfH,
            child: pw.Row(
              children: pair(
                goldLabel(
                  ar ? 'الوقت:' : 'Time:',
                  width: dateLabelW,
                  height: halfH,
                ),
                pw.Expanded(
                  child: val(
                    inspection.inspectionTime,
                    height: halfH,
                    forceLtr: true,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    final signatureLabel = goldLabel(
      ar ? 'توقيع المفتش:' : 'Inspector Signature:',
      width: inspLabelW,
      height: sigH,
    );
    final signatureValue = pw.Expanded(
      child: pw.Container(
        height: sigH,
        decoration: pw.BoxDecoration(border: cellBorderAll()),
        child: pw.Stack(
          children: [
            if (signatureImage != null)
              pw.Positioned(
                left: -7,
                top: -6,
                right: -10,
                bottom: -5,
                child: pw.Image(
                  signatureImage,
                  fit: pw.BoxFit.contain,
                ),
              ),
          ],
        ),
      ),
    );

    final rightHalf = pw.Expanded(
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: ar
            ? [dateBlock, signatureValue, signatureLabel]
            : [signatureLabel, signatureValue, dateBlock],
      ),
    );

    return pw.Column(
      children: [
        pw.SizedBox(
          height: rowH,
          child: pw.Row(
            children: ar
                ? [nameHalf, locationHalf]
                : [locationHalf, nameHalf],
          ),
        ),
        pw.SizedBox(
          height: sigH,
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: ar
                ? [rightHalf, leftHalf]
                : [leftHalf, rightHalf],
          ),
        ),
      ],
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
    bool ar = false,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 3),
      decoration: pw.BoxDecoration(
        color: _gold,
        border: pw.Border.all(color: _border, width: 0.8),
      ),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.black,
        ),
        textDirection: ar ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      ),
    );
  }

  pw.Widget _photoHyperlinkChip({
    required ({String path, RemarkPhotoKind kind}) photo,
    required String? url,
    required bool ar,
  }) {
    final isFix = photo.kind == RemarkPhotoKind.fix;
    final label = isFix
        ? (ar ? 'صورة إصلاح' : 'Repair photo')
        : (ar ? 'صورة مشكلة' : 'Issue photo');
    final accent = isFix ? PdfColors.green700 : PdfColors.red700;
    final chip = pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Container(
          width: 11,
          height: 11,
          decoration: pw.BoxDecoration(
            color: accent,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
            border: pw.Border.all(color: accent, width: 0.6),
          ),
          alignment: pw.Alignment.center,
          child: pw.Text(
            '▣',
            style: pw.TextStyle(
              fontSize: 7,
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.SizedBox(width: 3),
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 7,
            color: url != null ? PdfColors.blue800 : PdfColors.grey700,
            decoration:
                url != null ? pw.TextDecoration.underline : pw.TextDecoration.none,
          ),
        ),
      ],
    );
    if (url == null || url.isEmpty) return chip;
    return pw.UrlLink(destination: url, child: chip);
  }

  pw.Widget _itemsTable(
    List<InspectionItem> items,
    String language,
    bool ar,
    Map<String, String> photoLinks,
  ) {
    final descAlign = ar ? pw.TextAlign.right : pw.TextAlign.left;
    final headers = [
      _th(ar ? 'م' : 'Item', ar: ar),
      _th(ar ? 'الوصف' : 'Description', align: descAlign, ar: ar),
      _th(ar ? 'نعم' : 'Yes', ar: ar),
      _th(ar ? 'لا' : 'No', ar: ar),
      _th(ar ? 'غ.م' : 'N/A', ar: ar),
      _th(
        ar
            ? "إن كانت الإجابة لا، ما الإجراء؟"
            : "If 'no', what are the actions taken?",
        align: descAlign,
        fontSize: 7,
        ar: ar,
      ),
    ];

    List<pw.Widget> rowCells(InspectionItem item) => [
          pw.Container(
            alignment: pw.Alignment.center,
            padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 2),
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
            alignment: ar ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
            padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: pw.Text(
              item.descriptionFor(language),
              style: const pw.TextStyle(
                fontSize: 8,
                lineSpacing: 1.15,
                color: PdfColors.black,
              ),
              textAlign: descAlign,
              textDirection: ar ? pw.TextDirection.rtl : pw.TextDirection.ltr,
            ),
          ),
          _markCell(item, ChecklistResponse.yes),
          _markCell(item, ChecklistResponse.no),
          _markCell(item, ChecklistResponse.na),
          pw.Container(
            alignment: ar ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
            padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: pw.Column(
              crossAxisAlignment: ar
                  ? pw.CrossAxisAlignment.end
                  : pw.CrossAxisAlignment.start,
              children: [
                if (item.actionsTaken.trim().isNotEmpty)
                  pw.Text(
                    item.actionsTaken,
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.black,
                    ),
                    textAlign: descAlign,
                    textDirection:
                        ar ? pw.TextDirection.rtl : pw.TextDirection.ltr,
                  ),
                for (final photo in item.remarkPhotos) ...[
                  pw.SizedBox(height: 2),
                  _photoHyperlinkChip(
                    photo: photo,
                    url: photoLinks[photo.path],
                    ar: ar,
                  ),
                ],
              ],
            ),
          ),
        ];

    // Arabic: mirror columns (actions … item).
    final headerRow = ar ? headers.reversed.toList() : headers;
    final widths = ar
        ? {
            0: const pw.FlexColumnWidth(3.2),
            1: const pw.FixedColumnWidth(30),
            2: const pw.FixedColumnWidth(30),
            3: const pw.FixedColumnWidth(30),
            4: const pw.FlexColumnWidth(4.8),
            5: const pw.FixedColumnWidth(30),
          }
        : {
            0: const pw.FixedColumnWidth(30),
            1: const pw.FlexColumnWidth(4.8),
            2: const pw.FixedColumnWidth(30),
            3: const pw.FixedColumnWidth(30),
            4: const pw.FixedColumnWidth(30),
            5: const pw.FlexColumnWidth(3.2),
          };

    return pw.Table(
      border: pw.TableBorder.all(color: _border, width: 0.8),
      columnWidths: widths,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        pw.TableRow(children: headerRow),
        for (final item in items)
          pw.TableRow(
            verticalAlignment: pw.TableCellVerticalAlignment.middle,
            children: ar ? rowCells(item).reversed.toList() : rowCells(item),
          ),
      ],
    );
  }

  /// Sticky page footer: partner logos always at bottom of every page.
  pw.Widget _pageFooter({
    required bool ar,
    required pw.MemoryImage? elegancia,
    required pw.MemoryImage? waseef,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.SizedBox(height: 8),
        _footerLogos(elegancia, waseef),
        pw.SizedBox(height: 4),
        pw.Align(
          alignment: ar ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
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
