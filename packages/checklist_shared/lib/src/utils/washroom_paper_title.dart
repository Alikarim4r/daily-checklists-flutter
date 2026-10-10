import '../models/inspection.dart';

/// Exact headline requested for the MOEHE toilet maintenance and cleaning
/// checklists. Returns null for every other form, preserving its old header.
/// The organizational service line immediately above stays unchanged.
String? washroomPaperSecondLine(Inspection inspection) {
  final name = inspection.siteNameEn.toLowerCase();
  final code = inspection.buildingCode.toUpperCase();
  final type =
      (inspection.siteChecklistType.isNotEmpty
              ? inspection.siteChecklistType
              : inspection.templateCodeSnapshot ?? '')
          .toUpperCase();

  // Check scope first: never override other facilities/cleaning checklists.
  final isToilet =
      name.contains('toilet') ||
      name.contains('washroom') ||
      code.contains('-WC-');
  if (!isToilet) return null;

  if (type == 'MOEHE_WC_CLEANING_V1' ||
      RegExp(r'^B[0-9]+-WC-.*-CL$').hasMatch(code)) {
    return 'Facilities Daily Checklists - Toilet Cleaning';
  }
  if (type == 'LIB_WASHROOM_HYGIENE_SAFETY_A0000000_V3' ||
      RegExp(r'^B[0-9]+-WC-.*-FM$').hasMatch(code)) {
    return 'Facilities Daily Checklists - Toilet Maintenance';
  }
  return null;
}
