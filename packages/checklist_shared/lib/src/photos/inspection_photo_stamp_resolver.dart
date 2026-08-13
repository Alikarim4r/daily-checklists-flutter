import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/organization.dart';
import '../models/profile.dart';
import 'inspection_photo_watermark.dart';

/// Resolves org → zone → site labels for photo stamps.
class InspectionPhotoStampResolver {
  InspectionPhotoStampResolver(this._client);

  final SupabaseClient _client;

  /// Builds stamp context with hierarchy names for [site] (or inspection fallbacks).
  Future<InspectionPhotoContext> buildContext({
    required ChecklistSite? site,
    required String language,
    required String buildingCode,
    required String inspectionDateIso,
    required String inspectionTime,
    required int itemIndex,
    required String itemDescription,
    required String inspectorName,
    required String kindLabel,
    required String sourceLabel,
    String? organizationIdFallback,
    String? siteNameFallback,
  }) async {
    String orgName = '';
    String zoneName = '';
    String siteName = '';

    final siteRow = site;
    if (siteRow != null) {
      siteName = siteRow.nameFor(language).trim().isNotEmpty
          ? siteRow.nameFor(language)
          : siteRow.buildingCode;

      // Prefer campus · unit when nested under a campus.
      if (siteRow.parentSiteId != null && siteRow.parentSiteId!.isNotEmpty) {
        try {
          final parent = await _client
              .from('sites')
              .select('name_en, name_ar, zone_id, organization_id')
              .eq('id', siteRow.parentSiteId!)
              .maybeSingle();
          if (parent != null) {
            final pEn = (parent['name_en'] as String?)?.trim() ?? '';
            final pAr = (parent['name_ar'] as String?)?.trim() ?? '';
            final campusLabel = language == 'ar' && pAr.isNotEmpty ? pAr : pEn;
            if (campusLabel.isNotEmpty) {
              final unit = siteRow.nameFor(language);
              siteName = '$campusLabel · $unit';
            }
          }
        } catch (_) {}
      }

      final orgId = siteRow.organizationId.isNotEmpty
          ? siteRow.organizationId
          : organizationIdFallback;
      if (orgId != null && orgId.isNotEmpty) {
        try {
          final org = await _client
              .from('organizations')
              .select('name_en, name_ar')
              .eq('id', orgId)
              .maybeSingle();
          if (org != null) {
            final o = Organization.fromJson(
              Map<String, dynamic>.from(org)..['id'] = orgId,
            );
            orgName = o.nameFor(language);
          }
        } catch (_) {}
      }

      String? zoneId = siteRow.zoneId;
      if ((zoneId == null || zoneId.isEmpty) && siteRow.parentSiteId != null) {
        try {
          final parent = await _client
              .from('sites')
              .select('zone_id')
              .eq('id', siteRow.parentSiteId!)
              .maybeSingle();
          zoneId = parent?['zone_id'] as String?;
        } catch (_) {}
      }
      if (zoneId != null && zoneId.isNotEmpty) {
        try {
          final zone = await _client
              .from('zones')
              .select('name_en, name_ar, code')
              .eq('id', zoneId)
              .maybeSingle();
          if (zone != null) {
            final z = Zone.fromJson(
              Map<String, dynamic>.from(zone)
                ..['id'] = zoneId
                ..['organization_id'] = siteRow.organizationId.isNotEmpty
                    ? siteRow.organizationId
                    : (organizationIdFallback ?? ''),
            );
            zoneName = z.nameFor(language);
          }
        } catch (_) {}
      }
    } else if (siteNameFallback != null) {
      siteName = siteNameFallback;
    }

    if (orgName.isEmpty) {
      orgName = language == 'ar' ? 'الجهة' : 'Organization';
    }

    return InspectionPhotoContext(
      organizationName: orgName,
      zoneName: zoneName,
      siteName: siteName.isNotEmpty
          ? siteName
          : (siteNameFallback ?? buildingCode),
      buildingCode: buildingCode,
      inspectionDateIso: inspectionDateIso,
      inspectionTime: inspectionTime,
      itemIndex: itemIndex,
      itemDescription: itemDescription,
      inspectorName: inspectorName,
      kindLabel: kindLabel,
      sourceLabel: sourceLabel,
    );
  }
}
