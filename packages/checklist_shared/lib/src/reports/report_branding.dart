/// Report logo storage + layout constants for Daily Checklists.
library;

const kReportLogosBucket = 'report-logos';

/// Logical slot size ≈ 6 × 2 cm for org header logos.
const kOrgLogoSlotW = 228.0;
const kOrgLogoSlotH = 76.0;

/// Slightly shorter for footer zone/site logos.
const kFooterLogoSlotW = 180.0;
const kFooterLogoSlotH = 60.0;

class ReportBrandingBytes {
  const ReportBrandingBytes({
    this.orgHeaderLogo,
    this.zoneFooterLogo,
    this.siteFooterLogo,
    this.orgNameEn = '',
    this.orgNameAr = '',
  });

  /// Locale-resolved organization header logo.
  final List<int>? orgHeaderLogo;

  /// Zone footer logo (EN bottom-right / AR bottom-left).
  final List<int>? zoneFooterLogo;

  /// Site footer logo (EN bottom-left / AR bottom-right).
  final List<int>? siteFooterLogo;

  final String orgNameEn;
  final String orgNameAr;

  String orgNameFor(String language) =>
      language == 'ar' && orgNameAr.trim().isNotEmpty ? orgNameAr : orgNameEn;
}
