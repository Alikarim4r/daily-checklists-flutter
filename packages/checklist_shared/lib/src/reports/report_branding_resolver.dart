import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'report_branding.dart';

/// Loads org/zone/site logos for on-screen forms and PDF export.
class ReportBrandingResolver {
  ReportBrandingResolver(this._client);

  final SupabaseClient _client;
  static const _cacheLifetime = Duration(minutes: 5);
  static final Map<
    String,
    ({Future<ReportBrandingBytes> future, DateTime expiresAt})
  >
  _cache = {};

  /// Call after an administrator changes any organization/zone/site logo.
  static void clearCache() => _cache.clear();

  Future<ReportBrandingBytes> resolveForSite({
    required String siteId,
    required String language,
  }) {
    final key = '$siteId:$language';
    final now = DateTime.now();
    final cached = _cache[key];
    if (cached != null && cached.expiresAt.isAfter(now)) {
      return cached.future;
    }
    final future = _resolveForSite(siteId: siteId, language: language);
    _cache[key] = (future: future, expiresAt: now.add(_cacheLifetime));
    // Evict failed lookups without creating an ignored rethrowing Future. The
    // latter surfaced as an unhandled exception even when FutureBuilder was
    // correctly rendering its fallback branding.
    future.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {
        if (identical(_cache[key]?.future, future)) _cache.remove(key);
      },
    );
    return future;
  }

  Future<ReportBrandingBytes> _resolveForSite({
    required String siteId,
    required String language,
  }) async {
    final siteRow = await _client
        .from('sites')
        .select(
          'id, organization_id, zone_id, parent_site_id, report_logo_path',
        )
        .eq('id', siteId)
        .maybeSingle();
    if (siteRow == null) {
      return _fallbackBundled();
    }

    final orgId = siteRow['organization_id'] as String?;
    final zoneId = siteRow['zone_id'] as String?;
    final parentId = siteRow['parent_site_id'] as String?;
    var siteLogoPath = siteRow['report_logo_path'] as String?;

    final parentFuture =
        (siteLogoPath == null || siteLogoPath.isEmpty) && parentId != null
        ? _client
              .from('sites')
              .select('report_logo_path')
              .eq('id', parentId)
              .maybeSingle()
        : Future<Map<String, dynamic>?>.value(null);
    final zoneFuture = zoneId != null
        ? _client
              .from('zones')
              .select('report_logo_path')
              .eq('id', zoneId)
              .maybeSingle()
        : Future<Map<String, dynamic>?>.value(null);
    final orgFuture = orgId != null
        ? _client
              .from('organizations')
              .select('name_en, name_ar, logo_en_path, logo_ar_path')
              .eq('id', orgId)
              .maybeSingle()
        : Future<Map<String, dynamic>?>.value(null);
    final lookups = await Future.wait<Map<String, dynamic>?>([
      parentFuture,
      zoneFuture,
      orgFuture,
    ]);
    siteLogoPath ??= lookups[0]?['report_logo_path'] as String?;
    final zoneLogoPath = lookups[1]?['report_logo_path'] as String?;

    String orgNameEn = '';
    String orgNameAr = '';
    String? logoEn;
    String? logoAr;
    final org = lookups[2];
    if (org != null) {
      orgNameEn = (org['name_en'] ?? '') as String;
      orgNameAr = (org['name_ar'] ?? '') as String;
      logoEn = org['logo_en_path'] as String?;
      logoAr = org['logo_ar_path'] as String?;
    }

    final orgPath = language == 'ar'
        ? (logoAr?.isNotEmpty == true ? logoAr : logoEn)
        : (logoEn?.isNotEmpty == true ? logoEn : logoAr);

    // Only MOEHE HQ keeps legacy bundled logos when slots are empty.
    const moeheOrgId = 'a0000000-0000-4000-8000-000000000001';
    final useLegacyFallback = orgId == moeheOrgId;
    final media = await Future.wait<Object?>([
      _downloadOrNull(orgPath),
      _downloadOrNull(zoneLogoPath),
      _downloadOrNull(siteLogoPath),
      useLegacyFallback
          ? _fallbackBundled()
          : Future<ReportBrandingBytes?>.value(null),
    ]);
    final orgBytes = media[0] as List<int>?;
    final zoneBytes = media[1] as List<int>?;
    final siteBytes = media[2] as List<int>?;
    final fallback = media[3] as ReportBrandingBytes?;

    return ReportBrandingBytes(
      orgHeaderLogo: orgBytes ?? fallback?.orgHeaderLogo,
      zoneFooterLogo: zoneBytes ?? fallback?.zoneFooterLogo,
      siteFooterLogo: siteBytes ?? fallback?.siteFooterLogo,
      orgNameEn: orgNameEn.isNotEmpty ? orgNameEn : (fallback?.orgNameEn ?? ''),
      orgNameAr: orgNameAr.isNotEmpty ? orgNameAr : (fallback?.orgNameAr ?? ''),
    );
  }

  Future<List<int>?> _downloadOrNull(String? path) async {
    if (path == null || path.trim().isEmpty) return null;
    try {
      return await _client.storage.from(kReportLogosBucket).download(path);
    } catch (_) {
      return null;
    }
  }

  Future<ReportBrandingBytes> _fallbackBundled() async {
    Future<List<int>?> load(String asset) async {
      try {
        final data = await rootBundle.load(asset);
        return data.buffer.asUint8List();
      } catch (_) {
        return null;
      }
    }

    return ReportBrandingBytes(
      orgHeaderLogo: await load(
        'packages/checklist_shared/assets/branding/moehe_logo.png',
      ),
      // Historical layout: left waseef (= site slot), right footer2 (= zone slot)
      siteFooterLogo: await load(
        'packages/checklist_shared/assets/branding/logo_waseef.png',
      ),
      zoneFooterLogo: await load(
        'packages/checklist_shared/assets/branding/logo_footer2.png',
      ),
      orgNameEn: 'MOEHE',
      orgNameAr: 'وزارة التربية والتعليم والتعليم العالي',
    );
  }
}
