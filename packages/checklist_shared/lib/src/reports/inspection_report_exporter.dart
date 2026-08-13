import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/enums.dart';
import '../models/inspection.dart';
import '../repositories/inspection_repository.dart';
import '../theme/form_paper_theme.dart';
import '../utils/signature_ink.dart';
import '../utils/storage_path_list.dart';
import 'report_branding.dart';
import 'report_branding_resolver.dart';

enum ReportPhotoMode { links, embedded }

class InspectionReportFonts {
  const InspectionReportFonts({
    required this.latinRegular,
    required this.latinBold,
    required this.arabicRegular,
    required this.arabicBold,
  });

  final pw.Font latinRegular;
  final pw.Font latinBold;
  final pw.Font arabicRegular;
  final pw.Font arabicBold;
}

enum InspectionReportEvidenceIssue {
  missingSignature,
  unavailableSignature,
  unavailablePhoto,
  unreadablePhoto,
}

class InspectionReportEvidenceException implements Exception {
  const InspectionReportEvidenceException(this.issue, {this.reference});

  final InspectionReportEvidenceIssue issue;
  final String? reference;

  String messageFor(String language) {
    final ar = language == 'ar';
    return switch (issue) {
      InspectionReportEvidenceIssue.missingSignature =>
        ar
            ? 'لا يمكن إنشاء تقرير نهائي لأن السجل لا يحتوي على توقيع محفوظ.'
            : 'A final report cannot be created because the record has no saved signature.',
      InspectionReportEvidenceIssue.unavailableSignature =>
        ar
            ? 'تعذر تحميل التوقيع المحفوظ. تحقق من الاتصال وسلامة ملف الدليل ثم أعد المحاولة.'
            : 'The saved signature could not be loaded. Check connectivity and evidence integrity, then retry.',
      InspectionReportEvidenceIssue.unavailablePhoto =>
        ar
            ? 'تعذر تحميل صورة الدليل${reference == null ? '' : ' رقم $reference'}. لن يتم إنشاء تقرير ناقص.'
            : 'Evidence photo${reference == null ? '' : ' $reference'} could not be loaded. An incomplete report was not created.',
      InspectionReportEvidenceIssue.unreadablePhoto =>
        ar
            ? 'صورة الدليل${reference == null ? '' : ' رقم $reference'} تالفة أو غير قابلة للقراءة.'
            : 'Evidence photo${reference == null ? '' : ' $reference'} is corrupt or unreadable.',
    };
  }

  @override
  String toString() => messageFor('en');
}

void validateInspectionReportEvidence(Inspection inspection) {
  if (inspection.isSubmitted &&
      (inspection.signaturePath == null ||
          inspection.signaturePath!.trim().isEmpty)) {
    throw const InspectionReportEvidenceException(
      InspectionReportEvidenceIssue.missingSignature,
    );
  }
}

/// Stable references derived only from checklist item/photo order. They do not
/// depend on PDF pagination, paper size, signed URLs, or storage file names.
Map<String, String> buildInspectionPhotoReferences(
  Iterable<InspectionItem> items,
) {
  final result = <String, String>{};
  final ordered = [...items]
    ..sort((a, b) => a.itemIndex.compareTo(b.itemIndex));
  for (final item in ordered) {
    var number = 0;
    for (final photo in item.remarkPhotos) {
      number++;
      result[photo.path] = '${item.itemIndex}.$number';
    }
  }
  return result;
}

/// Uses the Arabic family as the primary face for Arabic reports.
///
/// The PDF package performs Arabic shaping with the primary font. Keeping an
/// Arabic font only in [pw.TextStyle.fontFallback] produces incorrect glyph
/// selection and visibly broken words, even when every code point exists in
/// the fallback font.
pw.ThemeData buildInspectionReportTheme({
  required bool arabic,
  required pw.Font latinRegular,
  required pw.Font latinBold,
  required pw.Font arabicRegular,
  required pw.Font arabicBold,
}) {
  final primaryRegular = arabic ? arabicRegular : latinRegular;
  final primaryBold = arabic ? arabicBold : latinBold;
  final fallback = arabic
      ? <pw.Font>[latinRegular, latinBold]
      : <pw.Font>[arabicRegular, arabicBold];

  return pw.ThemeData.withFont(
    base: primaryRegular,
    bold: primaryBold,
    fontFallback: fallback,
  ).copyWith(
    defaultTextStyle: pw.TextStyle(
      font: primaryRegular,
      fontNormal: primaryRegular,
      fontBold: primaryBold,
      fontFallback: fallback,
      fontSize: 9,
      color: PdfColors.black,
    ),
    header0: pw.TextStyle(
      font: primaryBold,
      fontNormal: primaryRegular,
      fontBold: primaryBold,
      fontFallback: fallback,
      fontSize: 13,
      color: PdfColors.black,
    ),
  );
}

/// PDF export matching the on-screen A4 [ChecklistFormLayout] / MOEHE paper form.
class InspectionReportExporter {
  InspectionReportExporter();

  static const _okBlue = PdfColor.fromInt(0xFF3B82F6);
  static const _problemRed = PdfColor.fromInt(0xFFEF4444);
  static const _fixGreen = PdfColor.fromInt(0xFF28A745);
  static const _emptyGray = PdfColor.fromInt(0xFFCBD5E1);

  PdfColor _gold = const PdfColor.fromInt(0xFFE8C547);
  PdfColor _border = PdfColors.black;
  PdfColor _accentText = PdfColors.black;

  static PdfColor _pdfColor(Color c) =>
      PdfColor.fromInt(FormPaperTheme.asArgb32(c));

  /// Build A4 form PDF and open the system share/save sheet.
  ///
  /// Avoids [Printing.layoutPdf] — sandboxed macOS without print entitlement
  /// and some Android OEMs show "This application does not support printing".
  Future<void> export(
    Inspection inspection, {
    String language = 'en',
    FormPaperTheme? paperTheme,
    ReportPhotoMode photoMode = ReportPhotoMode.links,
  }) async {
    final bytes = await buildPdfBytes(
      inspection,
      language: language,
      paperTheme: paperTheme,
      photoMode: photoMode,
    );
    final stableName = inspection.referenceNo.isEmpty
        ? '${inspection.buildingCode}_${inspection.dateIso}'
        : inspection.referenceNo;
    final filename = 'inspection_$stableName.pdf';
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }

  /// Optional: system print dialog (requires macOS print entitlement).
  Future<void> print(
    Inspection inspection, {
    String language = 'en',
    ReportPhotoMode photoMode = ReportPhotoMode.links,
  }) async {
    final bytes = await buildPdfBytes(
      inspection,
      language: language,
      photoMode: photoMode,
    );
    final name = 'inspection_${inspection.buildingCode}_${inspection.dateIso}';
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
  Future<void> share(
    Inspection inspection, {
    String language = 'en',
    ReportPhotoMode photoMode = ReportPhotoMode.links,
  }) async {
    final bytes = await buildPdfBytes(
      inspection,
      language: language,
      photoMode: photoMode,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'inspection_${inspection.buildingCode}_${inspection.dateIso}.pdf',
    );
  }

  Future<Uint8List> buildPdfBytes(
    Inspection inspection, {
    String language = 'en',
    ReportBrandingBytes? branding,
    FormPaperTheme? paperTheme,
    ReportPhotoMode photoMode = ReportPhotoMode.links,
    InspectionReportFonts? fonts,
  }) async {
    validateInspectionReportEvidence(inspection);
    final ar = language == 'ar';
    var resolvedPaperTheme = paperTheme ?? inspection.paperTheme;
    // Older/offline instances may not carry migration 022's resolved theme.
    if (paperTheme == null && inspection.resolvedFormTheme == null) {
      try {
        final rows = await Supabase.instance.client.rpc(
          'resolve_checklist_form_themes',
          params: {
            'p_site_ids': [inspection.siteId],
          },
        );
        if ((rows as List).isNotEmpty) {
          final resolved = Map<String, dynamic>.from(rows.first as Map);
          resolvedPaperTheme = FormPaperTheme.resolve(
            themeDb: resolved['theme_key'] as String?,
            accentHex: resolved['accent_hex'] as String?,
          );
        }
      } catch (_) {
        // Compatibility fallback for deployments still applying migration 022.
      }
    }
    if (paperTheme == null &&
        inspection.resolvedFormTheme == null &&
        inspection.formTheme == FormThemeKey.inherit.dbValue &&
        inspection.parentSiteId != null) {
      final parent = await Supabase.instance.client
          .from('sites')
          .select('form_theme, form_theme_accent')
          .eq('id', inspection.parentSiteId!)
          .maybeSingle();
      if (parent != null) {
        resolvedPaperTheme = FormPaperTheme.resolve(
          themeDb: inspection.formTheme,
          accentHex: inspection.formThemeAccent,
          parentThemeDb: parent['form_theme'] as String?,
          parentAccentHex: parent['form_theme_accent'] as String?,
        );
      }
    }
    final paper = resolvedPaperTheme;
    _gold = _pdfColor(paper.accent);
    _border = _pdfColor(paper.border);
    _accentText = _pdfColor(paper.accentText);
    final items = [...inspection.items]
      ..sort((a, b) => a.itemIndex.compareTo(b.itemIndex));

    InspectionRepository? repository;
    InspectionRepository repo() =>
        repository ??= InspectionRepository(Supabase.instance.client);
    final photoLinks = <String, String>{};
    final photoReferences = buildInspectionPhotoReferences(items);
    final embeddedPhotos = <String, Uint8List>{};
    for (final item in items) {
      for (final photo in item.remarkPhotos) {
        if (photoLinks.containsKey(photo.path)) continue;
        final reference = photoReferences[photo.path];
        final url = await repo().signedUrl(
          photo.path,
          expiresIn: 7 * 24 * 3600,
        );
        if (url == null || url.isEmpty) {
          throw InspectionReportEvidenceException(
            InspectionReportEvidenceIssue.unavailablePhoto,
            reference: reference,
          );
        }
        photoLinks[photo.path] = url;
        if (photoMode == ReportPhotoMode.embedded) {
          final bytes = await repo().downloadBytes(photo.path);
          if (bytes == null || bytes.isEmpty) {
            throw InspectionReportEvidenceException(
              InspectionReportEvidenceIssue.unavailablePhoto,
              reference: reference,
            );
          }
          final optimized = _optimizeReportPhoto(bytes);
          if (optimized == null) {
            throw InspectionReportEvidenceException(
              InspectionReportEvidenceIssue.unreadablePhoto,
              reference: reference,
            );
          }
          embeddedPhotos[photo.path] = optimized;
        }
      }
    }

    final resolvedFonts =
        fonts ??
        InspectionReportFonts(
          latinRegular: await PdfGoogleFonts.notoSansRegular(),
          latinBold: await PdfGoogleFonts.notoSansBold(),
          arabicRegular: await PdfGoogleFonts.notoNaskhArabicRegular(),
          arabicBold: await PdfGoogleFonts.notoNaskhArabicBold(),
        );
    final theme = buildInspectionReportTheme(
      arabic: ar,
      latinRegular: resolvedFonts.latinRegular,
      latinBold: resolvedFonts.latinBold,
      arabicRegular: resolvedFonts.arabicRegular,
      arabicBold: resolvedFonts.arabicBold,
    );

    final brand =
        branding ??
        await ReportBrandingResolver(
          Supabase.instance.client,
        ).resolveForSite(siteId: inspection.siteId, language: language);

    pw.MemoryImage? moeheLogo;
    pw.MemoryImage? waseefLogo;
    pw.MemoryImage? footerLogo;
    if (brand.orgHeaderLogo != null) {
      moeheLogo = pw.MemoryImage(Uint8List.fromList(brand.orgHeaderLogo!));
    }
    if (brand.siteFooterLogo != null) {
      waseefLogo = pw.MemoryImage(Uint8List.fromList(brand.siteFooterLogo!));
    }
    if (brand.zoneFooterLogo != null) {
      footerLogo = pw.MemoryImage(Uint8List.fromList(brand.zoneFooterLogo!));
    }
    final orgName = brand.orgNameFor(language);

    pw.MemoryImage? signatureImage;
    final sigPath = inspection.signaturePath;
    if (sigPath != null && sigPath.isNotEmpty) {
      try {
        final raw = await repo().downloadBytes(sigPath, forceRefresh: true);
        if (raw == null || raw.isEmpty) {
          throw const InspectionReportEvidenceException(
            InspectionReportEvidenceIssue.unavailableSignature,
          );
        }
        final blue = recolorSignatureToBlueInk(Uint8List.fromList(raw));
        signatureImage = pw.MemoryImage(blue);
      } on InspectionReportEvidenceException {
        rethrow;
      } catch (_) {
        throw const InspectionReportEvidenceException(
          InspectionReportEvidenceIssue.unavailableSignature,
        );
      }
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
          siteLogo: waseefLogo,
          zoneLogo: footerLogo,
          orgName: orgName,
        ),
        build: (context) => [
          _header(inspection, ar, moeheLogo, orgName),
          pw.SizedBox(height: 6),
          _titleBanner(inspection, ar),
          pw.SizedBox(height: 8),
          _metaGrid(inspection, ar, signatureImage),
          pw.SizedBox(height: 10),
          _itemsTable(items, language, ar, photoLinks, photoReferences),
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
          if (photoMode == ReportPhotoMode.embedded &&
              embeddedPhotos.isNotEmpty) ...[
            pw.NewPage(),
            ..._photoEvidencePages(
              items: items,
              language: language,
              ar: ar,
              photoReferences: photoReferences,
              embeddedPhotos: embeddedPhotos,
            ),
          ],
        ],
      ),
    );
    return doc.save();
  }

  Uint8List? _optimizeReportPhoto(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      const maxSide = 1400;
      final longest = decoded.width > decoded.height
          ? decoded.width
          : decoded.height;
      final resized = longest > maxSide
          ? img.copyResize(
              decoded,
              width: decoded.width >= decoded.height ? maxSide : null,
              height: decoded.height > decoded.width ? maxSide : null,
              interpolation: img.Interpolation.average,
            )
          : decoded;
      return Uint8List.fromList(img.encodeJpg(resized, quality: 80));
    } catch (_) {
      return null;
    }
  }

  List<pw.Widget> _photoEvidencePages({
    required List<InspectionItem> items,
    required String language,
    required bool ar,
    required Map<String, String> photoReferences,
    required Map<String, Uint8List> embeddedPhotos,
  }) {
    final widgets = <pw.Widget>[
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 8),
        color: _gold,
        child: pw.Text(
          ar ? 'أدلة الصور ومراجعها' : 'Photo Evidence & References',
          textAlign: ar ? pw.TextAlign.right : pw.TextAlign.left,
          textDirection: ar ? pw.TextDirection.rtl : pw.TextDirection.ltr,
          style: pw.TextStyle(
            color: _accentText,
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ),
      pw.SizedBox(height: 10),
    ];
    for (final item in items) {
      for (final photo in item.remarkPhotos) {
        final bytes = embeddedPhotos[photo.path];
        if (bytes == null) continue;
        final reference = photoReferences[photo.path] ?? '${item.itemIndex}';
        widgets.add(
          pw.Container(
            height: 176,
            margin: const pw.EdgeInsets.only(bottom: 10),
            padding: const pw.EdgeInsets.all(7),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _border, width: 0.8),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: ar
                  ? [
                      _photoEvidenceDetails(
                        item: item,
                        language: language,
                        ar: ar,
                        reference: reference,
                        isFix: photo.kind == RemarkPhotoKind.fix,
                      ),
                      pw.SizedBox(width: 8),
                      _embeddedPhoto(bytes),
                    ]
                  : [
                      _embeddedPhoto(bytes),
                      pw.SizedBox(width: 8),
                      _photoEvidenceDetails(
                        item: item,
                        language: language,
                        ar: ar,
                        reference: reference,
                        isFix: photo.kind == RemarkPhotoKind.fix,
                      ),
                    ],
            ),
          ),
        );
      }
    }
    return widgets;
  }

  pw.Widget _embeddedPhoto(Uint8List bytes) => pw.SizedBox(
    width: 250,
    child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain),
  );

  pw.Widget _photoEvidenceDetails({
    required InspectionItem item,
    required String language,
    required bool ar,
    required String reference,
    required bool isFix,
  }) => pw.Expanded(
    child: pw.Column(
      crossAxisAlignment: ar
          ? pw.CrossAxisAlignment.end
          : pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          ar ? 'مرجع الصورة: $reference' : 'Photo Ref: $reference',
          textDirection: ar ? pw.TextDirection.rtl : pw.TextDirection.ltr,
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          ar
              ? 'البند ${item.itemIndex} — ${isFix ? 'دليل الإصلاح' : 'دليل المشكلة'}'
              : 'Item ${item.itemIndex} — ${isFix ? 'Fix evidence' : 'Issue evidence'}',
          textDirection: ar ? pw.TextDirection.rtl : pw.TextDirection.ltr,
          style: const pw.TextStyle(fontSize: 8.5),
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          item.descriptionFor(language),
          textDirection: ar ? pw.TextDirection.rtl : pw.TextDirection.ltr,
          textAlign: ar ? pw.TextAlign.right : pw.TextAlign.left,
          maxLines: 6,
          overflow: pw.TextOverflow.clip,
          style: const pw.TextStyle(fontSize: 8, lineSpacing: 1.2),
        ),
      ],
    ),
  );

  pw.Widget _header(
    Inspection inspection,
    bool ar,
    pw.MemoryImage? logo,
    String orgName,
  ) {
    final siteName = ar
        ? (inspection.siteNameAr.isNotEmpty
              ? inspection.siteNameAr
              : inspection.buildingCode)
        : (inspection.siteNameEn.isNotEmpty
              ? inspection.siteNameEn
              : inspection.buildingCode);

    final logoWidget = logo != null
        ? pw.SizedBox(
            width: 158,
            height: 54,
            child: pw.Image(logo, fit: pw.BoxFit.contain),
          )
        : pw.Text(
            orgName.isNotEmpty ? orgName : 'ORG',
            textAlign: ar ? pw.TextAlign.right : pw.TextAlign.left,
            textDirection: ar ? pw.TextDirection.rtl : pw.TextDirection.ltr,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
          );

    // Titles hug the edge opposite the logo — not centered in the gap.
    final titles = pw.ConstrainedBox(
      constraints: const pw.BoxConstraints(maxWidth: 340),
      child: pw.Column(
        crossAxisAlignment: ar
            ? pw.CrossAxisAlignment.end
            : pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            ar
                ? 'خدمة الإدارة المتكاملة للمرافق لصالح $orgName'
                : 'Integrated Facilities Management Service for $orgName',
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
      decoration: pw.BoxDecoration(
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

  pw.Widget _titleBanner(Inspection inspection, bool ar) {
    final reference = inspection.referenceNo.trim();
    final templateVersion = inspection.templateVersionSnapshot;
    final identity = [
      if (reference.isNotEmpty) reference,
      if (templateVersion != null)
        ar ? 'إصدار القائمة $templateVersion' : 'Checklist v$templateVersion',
    ].join('  •  ');
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 7),
      decoration: pw.BoxDecoration(
        color: _gold,
        border: pw.Border.all(color: _border, width: 0.9),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            ar
                ? 'تقرير الفحص اليومي للمرافق'
                : 'Daily Facilities Inspection Report',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: _accentText,
            ),
            textDirection: ar ? pw.TextDirection.rtl : pw.TextDirection.ltr,
          ),
          if (identity.isNotEmpty) ...[
            pw.SizedBox(height: 2),
            pw.Text(
              identity,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 7.5, color: _accentText),
              textDirection: ar ? pw.TextDirection.rtl : pw.TextDirection.ltr,
            ),
          ],
        ],
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
    const double dateBlockW = 100;
    const double floorLabelW = 50;

    pw.TextStyle labelStyle() => pw.TextStyle(
      fontSize: 7.5,
      fontWeight: pw.FontWeight.bold,
      color: _accentText,
    );
    pw.TextStyle valueStyle() => pw.TextStyle(
      fontSize: 8.5,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.black,
    );

    pw.Border cellBorderAll() => pw.Border.all(color: _border, width: 0.75);

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
        decoration: pw.BoxDecoration(color: bg, border: cellBorderAll()),
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
          goldLabel(ar ? 'الموقع:' : 'Location:', width: labelW, height: rowH),
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
                  flex: 2,
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
                pw.Expanded(
                  flex: 3,
                  child: val(
                    inspection.bldgNo,
                    height: halfH,
                    align: pw.TextAlign.center,
                    forceLtr: true,
                  ),
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
                pw.Expanded(
                  flex: 3,
                  child: val(
                    inspection.bldgNo,
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
                pw.Expanded(
                  flex: 2,
                  child: val(
                    inspection.floorLabel,
                    height: halfH,
                    align: pw.TextAlign.center,
                  ),
                ),
              ],
      ),
    );

    final leftHalf = pw.Expanded(child: pw.Column(children: [pinRow, bldgRow]));

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
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        decoration: pw.BoxDecoration(border: cellBorderAll()),
        alignment: pw.Alignment.center,
        child: signatureImage == null
            ? pw.SizedBox()
            : pw.Image(signatureImage, fit: pw.BoxFit.contain),
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
            children: ar ? [nameHalf, locationHalf] : [locationHalf, nameHalf],
          ),
        ),
        pw.SizedBox(
          height: sigH,
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: ar ? [rightHalf, leftHalf] : [leftHalf, rightHalf],
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
      return _fixedRowCell(child: pw.SizedBox(width: 14, height: 14));
    }
    final color = _markColor(item, column);
    // Draw the tick geometrically — Unicode ✓ is missing in Noto and renders as ⊞.
    // PdfGraphics uses PDF coords (origin bottom-left, Y up) — invert Y vs Flutter.
    return _fixedRowCell(
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
          color: PdfColors.white,
        ),
        textDirection: ar ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      ),
    );
  }

  /// Fixed data-row height so empty / photo rows match.
  static const _itemRowH = 36.0;

  /// Preferred photo icon width before shrink (≥ 1 cm).
  static const _photoMinWidthCm = 72.0 / 2.54; // ≈ 28.35 pt

  /// A4 content width after MultiPage left/right margins (24+24).
  double get _tableContentWidth => PdfPageFormat.a4.width - 48;

  /// Remarks column width from table flex (3.2 / 8 of leftover after fixed cols).
  double get _remarksColWidth {
    const fixedCols = 30.0 * 4; // item + Yes/No/NA
    const flexSum = 4.8 + 3.2;
    return (_tableContentWidth - fixedCols) * (3.2 / flexSum);
  }

  /// Icon-only photo chip (hyperlink on the icon). Sized to fit remarks cell.
  pw.Widget _photoIconLink({
    required ({String path, RemarkPhotoKind kind}) photo,
    required String? url,
    required String reference,
    required double width,
    required double height,
  }) {
    final isFix = photo.kind == RemarkPhotoKind.fix;
    final accent = isFix ? _fixGreen : _problemRed;
    final w = width.clamp(3.0, 200.0);
    final h = height.clamp(3.0, 200.0);
    final icon = pw.Container(
      width: w,
      height: h,
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: accent, width: 0.9),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(1.2)),
      ),
      alignment: pw.Alignment.center,
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Container(
            width: w * 0.42,
            height: (h * 0.16).clamp(1.0, 6.0),
            decoration: pw.BoxDecoration(
              color: accent,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(0.8)),
            ),
          ),
          pw.SizedBox(height: (h * 0.05).clamp(0.4, 2.0)),
          pw.Container(
            width: w * 0.55,
            height: (h * 0.42).clamp(2.0, 14.0),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: accent, width: 0.7),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(1)),
            ),
            alignment: pw.Alignment.center,
            child: pw.Container(
              width: (w * 0.2).clamp(1.5, 8.0),
              height: (w * 0.2).clamp(1.5, 8.0),
              decoration: pw.BoxDecoration(
                shape: pw.BoxShape.circle,
                border: pw.Border.all(color: accent, width: 0.6),
              ),
            ),
          ),
          pw.SizedBox(height: 0.5),
          pw.Text(
            reference,
            style: pw.TextStyle(
              color: accent,
              fontSize: (h * 0.16).clamp(3.2, 5.2),
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty) return icon;
    return pw.UrlLink(destination: url, child: icon);
  }

  /// Lays out remark photos as issue↔fix pairs inside [boxW]×[boxH].
  ///
  /// Tight gap inside a pair; wider gap between pairs. Width defaults to ≥1cm;
  /// shrinks only when count exceeds the cell.
  pw.Widget _remarksPhotosRow({
    required List<({String path, RemarkPhotoKind kind, String pairId})> photos,
    required Map<String, String> photoLinks,
    required Map<String, String> photoReferences,
    required double boxW,
    required double boxH,
    required bool hasText,
    required bool ar,
  }) {
    if (photos.isEmpty || boxW <= 0 || boxH <= 0) return pw.SizedBox();
    const pairGap = 0.8;
    const betweenGap = 3.0;
    final n = photos.length;
    var betweenCount = 0;
    for (var i = 1; i < photos.length; i++) {
      if (photos[i].pairId != photos[i - 1].pairId) betweenCount++;
    }
    final innerGaps = (n - 1 - betweenCount).clamp(0, 1000) * pairGap;
    final gaps = innerGaps + betweenGap * betweenCount;
    final fitW = ((boxW - gaps) / n).clamp(3.0, boxW);
    final w = fitW < _photoMinWidthCm ? fitW : _photoMinWidthCm;
    final photoBandH = hasText ? (boxH * 0.55).clamp(6.0, boxH) : boxH;
    final h = photoBandH.clamp(5.0, boxH);

    return pw.SizedBox(
      width: boxW,
      height: h,
      child: pw.Row(
        mainAxisAlignment: ar
            ? pw.MainAxisAlignment.end
            : pw.MainAxisAlignment.start,
        children: [
          for (var i = 0; i < photos.length; i++) ...[
            if (i > 0)
              pw.SizedBox(
                width: photos[i].pairId == photos[i - 1].pairId
                    ? pairGap
                    : betweenGap,
              ),
            _photoIconLink(
              photo: (path: photos[i].path, kind: photos[i].kind),
              url: photoLinks[photos[i].path],
              reference: photoReferences[photos[i].path] ?? '',
              width: w,
              height: h,
            ),
          ],
        ],
      ),
    );
  }

  pw.Widget _fixedRowCell({
    required pw.Widget child,
    pw.Alignment alignment = pw.Alignment.center,
    pw.EdgeInsets padding = const pw.EdgeInsets.symmetric(
      vertical: 4,
      horizontal: 2,
    ),
  }) {
    return pw.Container(
      height: _itemRowH,
      alignment: alignment,
      padding: padding,
      child: child,
    );
  }

  pw.Widget _remarksCellContent({
    required InspectionItem item,
    required Map<String, String> photoLinks,
    required Map<String, String> photoReferences,
    required bool ar,
    required pw.TextAlign descAlign,
  }) {
    final text = item.actionsTaken.trim();
    final hasText = text.isNotEmpty;
    final photos = item.remarkPhotos;
    // Inner size of the fixed remarks box (cell padding accounted for).
    const padX = 6.0;
    const padY = 4.0;
    final boxW = (_remarksColWidth - padX).clamp(40.0, _remarksColWidth);
    final boxH = (_itemRowH - padY).clamp(12.0, _itemRowH);

    return pw.SizedBox(
      width: boxW,
      height: boxH,
      child: pw.Column(
        crossAxisAlignment: ar
            ? pw.CrossAxisAlignment.end
            : pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          if (photos.isNotEmpty)
            _remarksPhotosRow(
              photos: photos,
              photoLinks: photoLinks,
              photoReferences: photoReferences,
              boxW: boxW,
              boxH: hasText ? boxH : boxH,
              hasText: hasText,
              ar: ar,
            ),
          if (photos.isNotEmpty && hasText) pw.SizedBox(height: 1),
          if (hasText)
            pw.Expanded(
              child: pw.Text(
                text,
                style: const pw.TextStyle(
                  fontSize: 6.5,
                  color: PdfColors.black,
                  lineSpacing: 1.05,
                ),
                textAlign: descAlign,
                textDirection: ar ? pw.TextDirection.rtl : pw.TextDirection.ltr,
                maxLines: photos.isEmpty ? 3 : 2,
                overflow: pw.TextOverflow.clip,
              ),
            ),
        ],
      ),
    );
  }

  pw.Widget _itemsTable(
    List<InspectionItem> items,
    String language,
    bool ar,
    Map<String, String> photoLinks,
    Map<String, String> photoReferences,
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
      _fixedRowCell(
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
      _fixedRowCell(
        alignment: ar ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
        padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
        child: pw.Text(
          item.descriptionFor(language),
          style: const pw.TextStyle(
            fontSize: 7.5,
            lineSpacing: 1.05,
            color: PdfColors.black,
          ),
          textAlign: descAlign,
          textDirection: ar ? pw.TextDirection.rtl : pw.TextDirection.ltr,
          maxLines: 3,
          overflow: pw.TextOverflow.clip,
        ),
      ),
      _markCell(item, ChecklistResponse.yes),
      _markCell(item, ChecklistResponse.no),
      _markCell(item, ChecklistResponse.na),
      _fixedRowCell(
        alignment: ar ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
        padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 3),
        child: _remarksCellContent(
          item: item,
          photoLinks: photoLinks,
          photoReferences: photoReferences,
          ar: ar,
          descAlign: descAlign,
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

  /// Sticky page footer: site + zone logos (swap corners by language).
  pw.Widget _pageFooter({
    required bool ar,
    required pw.MemoryImage? siteLogo,
    required pw.MemoryImage? zoneLogo,
    required String orgName,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.SizedBox(height: 8),
        _footerLogos(
          ar: ar,
          siteLogo: siteLogo,
          zoneLogo: zoneLogo,
          orgName: orgName,
        ),
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

  pw.Widget _footerLogos({
    required bool ar,
    required pw.MemoryImage? siteLogo,
    required pw.MemoryImage? zoneLogo,
    required String orgName,
  }) {
    // Absolute page corners (LTR row): EN site=left zone=right; AR zone=left site=right.
    final left = ar ? zoneLogo : siteLogo;
    final right = ar ? siteLogo : zoneLogo;
    final credit = orgName.trim().isEmpty ? '© Facilities' : '© $orgName';
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (left != null)
          pw.SizedBox(
            width: 108,
            height: 36,
            child: pw.Image(left, fit: pw.BoxFit.contain),
          )
        else
          pw.SizedBox(width: 108, height: 36),
        pw.Text(
          credit,
          textAlign: ar ? pw.TextAlign.right : pw.TextAlign.left,
          textDirection: ar ? pw.TextDirection.rtl : pw.TextDirection.ltr,
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
        if (right != null)
          pw.SizedBox(
            width: 108,
            height: 36,
            child: pw.Image(right, fit: pw.BoxFit.contain),
          )
        else
          pw.SizedBox(width: 108, height: 36),
      ],
    );
  }
}
