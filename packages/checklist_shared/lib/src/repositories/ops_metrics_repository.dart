import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/enums.dart';
import '../models/inspection.dart';
import '../models/ops_metrics.dart';
import '../models/profile.dart';
import '../utils/policy_enforcement.dart';
import 'inspection_repository.dart';
import 'site_repository.dart';

/// Aggregates operational KPIs from existing inspection data (no extra tables).
class OpsMetricsRepository {
  OpsMetricsRepository(this._client, this._inspections, this._sites);

  final SupabaseClient _client;
  final InspectionRepository _inspections;
  final SiteRepository _sites;

  Future<OpsSnapshot> load({
    required Profile profile,
    required OpsPeriod period,
    String? siteId,
    String language = 'en',
  }) async {
    final ar = language == 'ar';
    final now = DateTime.now();
    final (from, to) = period.range(now);
    final today = DateTime(now.year, now.month, now.day);
    final todayIso = _iso(today);

    var sites = await _sites.listAccessibleSites(profile: profile);
    if (siteId != null && siteId.isNotEmpty) {
      sites = sites.where((s) => s.id == siteId).toList();
    }
    final siteIds = sites.map((s) => s.id).toSet();
    if (siteIds.isEmpty) {
      return OpsSnapshot(
        period: period,
        asOf: now,
        siteCount: 0,
        dailyCompliance: 0,
        pendingReviewCount: 0,
        overdueInspectionCount: 0,
        openProblemCount: 0,
        completionRate: 0,
        totalInspectionsInPeriod: 0,
        approvedInPeriod: 0,
        sites: const [],
        followUps: const [],
      );
    }

    final canReview = profile.canReviewInspections;
    final headers = await _listHeadersInRange(
      siteIds: siteIds.toList(),
      from: from,
      to: to,
    );

    final visible = headers.where((h) {
      if (canReview) {
        return h.reviewStatus == ReviewStatus.approved ||
            h.reviewStatus == ReviewStatus.submitted ||
            h.reviewStatus == ReviewStatus.draft;
      }
      return h.reviewStatus == ReviewStatus.approved;
    }).toList();

    final bySite = <String, List<Inspection>>{};
    for (final h in visible) {
      bySite.putIfAbsent(h.siteId, () => []).add(h);
    }

    final todayDoneSites = <String>{};
    for (final h in visible) {
      if (h.dateIso != todayIso) continue;
      if (h.awaitingReview || h.isApproved || h.isSubmitted) {
        todayDoneSites.add(h.siteId);
      }
    }

    final pendingInScope = visible.where((h) => h.awaitingReview).toList();
    final nonDraft = visible
        .where((h) => h.reviewStatus != ReviewStatus.draft)
        .toList();
    final approved = visible.where((h) => h.isApproved).toList();

    final siteRows = <SiteKpiRow>[];
    final followUps = <FollowUpItem>[];
    var overdueInspectionCount = 0;
    var openProblemTotal = 0;

    // Detailed metrics use latest inspection per site (with items).
    for (final site in sites) {
      final siteHeaders = bySite[site.id] ?? const <Inspection>[];
      final latestHeader = siteHeaders.isEmpty ? null : siteHeaders.first;
      Inspection? full;
      if (latestHeader != null) {
        full = await _inspections.getById(latestHeader.id);
      }

      var idealRate = 0.0;
      var openProblems = 0;
      var overdueCount = 0;
      final answered = <InspectionItem>[];
      if (full != null && full.items.isNotEmpty) {
        answered.addAll(full.items.where((i) => i.response != null));
        final ideal = answered.where((i) => i.isIdealAnswer).length;
        idealRate = answered.isEmpty ? 0 : ideal / answered.length;
        openProblems = full.items
            .where((i) => i.isProblem && !i.hasFixPhoto)
            .length;
        openProblemTotal += openProblems;

        try {
          final lookback = full.items.isEmpty
              ? 14
              : full.items
                  .map((e) => e.overdueAfterDays)
                  .fold<int>(14, (a, b) => a > b + 2 ? a : b + 2);
          final history = await _inspections.listRecentForSite(
            siteId: site.id,
            asOfDate: full.inspectionDate,
            lookbackDays: lookback,
          );
          final map = buildProblemHistory(history: history, current: full);
          final overdue = overdueItemIndexes(
            inspection: full,
            problemByDateIso: map,
          );
          overdueCount = overdue.length;
          if (overdue.isNotEmpty) {
            overdueInspectionCount++;
            followUps.add(
              FollowUpItem(
                kind: FollowUpKind.overdue,
                inspectionId: full.id,
                siteId: site.id,
                buildingCode: full.buildingCode,
                dateIso: full.dateIso,
                title: ar
                    ? 'بنود متأخرة — ${full.buildingCode}'
                    : 'Overdue items — ${full.buildingCode}',
                subtitle: ar
                    ? 'البنود: ${(overdue.toList()..sort()).join(', ')}'
                    : 'Items: ${(overdue.toList()..sort()).join(', ')}',
              ),
            );
          }
        } catch (_) {}

        if (openProblems > 0) {
          followUps.add(
            FollowUpItem(
              kind: FollowUpKind.openProblems,
              inspectionId: full.id,
              siteId: site.id,
              buildingCode: full.buildingCode,
              dateIso: full.dateIso,
              title: ar
                  ? 'مشاكل مفتوحة — ${full.buildingCode}'
                  : 'Open problems — ${full.buildingCode}',
              subtitle: ar
                  ? '$openProblems بند بدون إصلاح'
                  : '$openProblems item(s) without fix',
            ),
          );
        }
      }

      final approvedCount =
          siteHeaders.where((h) => h.isApproved).length;
      final siteName = language == 'ar' && site.nameAr.isNotEmpty
          ? site.nameAr
          : (site.nameEn.isNotEmpty ? site.nameEn : site.buildingCode);

      siteRows.add(
        SiteKpiRow(
          siteId: site.id,
          buildingCode: site.buildingCode,
          siteName: siteName,
          inspectionsInPeriod: siteHeaders.length,
          approvedCount: approvedCount,
          idealRate: idealRate,
          openProblemCount: openProblems,
          overdueCount: overdueCount,
          hasTodaySubmission: todayDoneSites.contains(site.id),
        ),
      );
    }

    for (final p in pendingInScope) {
      followUps.add(
        FollowUpItem(
          kind: FollowUpKind.pendingReview,
          inspectionId: p.id,
          siteId: p.siteId,
          buildingCode: p.buildingCode,
          dateIso: p.dateIso,
          title: ar
              ? 'بانتظار الاعتماد — ${p.buildingCode}'
              : 'Pending approval — ${p.buildingCode}',
          subtitle: ar
              ? '${p.inspectorName} • ${p.dateIso}'
              : '${p.inspectorName} • ${p.dateIso}',
        ),
      );
    }

    final siteCount = sites.length;
    final dailyCompliance =
        siteCount == 0 ? 0.0 : todayDoneSites.length / siteCount;
    final completionRate =
        nonDraft.isEmpty ? 0.0 : approved.length / nonDraft.length;

    return OpsSnapshot(
      period: period,
      asOf: now,
      siteCount: siteCount,
      dailyCompliance: dailyCompliance,
      pendingReviewCount: pendingInScope.length,
      overdueInspectionCount: overdueInspectionCount,
      openProblemCount: openProblemTotal,
      completionRate: completionRate,
      totalInspectionsInPeriod: nonDraft.length,
      approvedInPeriod: approved.length,
      sites: siteRows,
      followUps: followUps,
    );
  }

  Future<List<Inspection>> _listHeadersInRange({
    required List<String> siteIds,
    required DateTime from,
    required DateTime to,
  }) async {
    if (siteIds.isEmpty) return [];
    final fromIso = _iso(from);
    final toIso = _iso(to);
    // Chunk site IDs to stay within PostgREST URL limits.
    const chunk = 80;
    final out = <Inspection>[];
    for (var i = 0; i < siteIds.length; i += chunk) {
      final slice = siteIds.sublist(
        i,
        i + chunk > siteIds.length ? siteIds.length : i + chunk,
      );
      final rows = await _client
          .from('checklist_inspections')
          .select(
            '*, sites(name_en, name_ar, pin, organization_id)',
          )
          .inFilter('site_id', slice)
          .gte('inspection_date', fromIso)
          .lte('inspection_date', toIso)
          .order('inspection_date', ascending: false);
      for (final e in rows as List) {
        out.add(
          Inspection.fromJson(Map<String, dynamic>.from(e as Map)),
        );
      }
    }
    out.sort((a, b) => b.inspectionDate.compareTo(a.inspectionDate));
    return out;
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
