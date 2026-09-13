import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

/// Fonts bundled with the application so PDF generation is deterministic and
/// remains fully functional without network access.
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

abstract final class ReportFontLoader {
  static const _assetPrefix = 'packages/checklist_shared/assets/fonts';

  static Future<ByteData> _loadAsset(AssetBundle bundle, String name) async {
    try {
      final packaged = await bundle.load('$_assetPrefix/$name');
      if (packaged.lengthInBytes > 0) return packaged;
    } catch (_) {
      // When checklist_shared itself is the root test package Flutter exposes
      // its assets without the packages/checklist_shared prefix.
    }
    return bundle.load('assets/fonts/$name');
  }

  static Future<InspectionReportFonts> load({AssetBundle? bundle}) async {
    final assets = bundle ?? rootBundle;
    final data = await Future.wait([
      _loadAsset(assets, 'NotoSans-Regular.ttf'),
      _loadAsset(assets, 'NotoSans-Bold.ttf'),
      _loadAsset(assets, 'NotoNaskhArabic-Regular.ttf'),
      _loadAsset(assets, 'NotoNaskhArabic-Bold.ttf'),
    ]);
    return InspectionReportFonts(
      latinRegular: pw.Font.ttf(data[0]),
      latinBold: pw.Font.ttf(data[1]),
      arabicRegular: pw.Font.ttf(data[2]),
      arabicBold: pw.Font.ttf(data[3]),
    );
  }
}
