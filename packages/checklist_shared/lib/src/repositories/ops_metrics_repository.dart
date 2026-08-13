import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/enums.dart';
import '../models/inspection.dart';
import '../models/ops_metrics.dart';
import '../models/profile.dart';
import '../utils/policy_enforcement.dart';
import '../utils/problem_open_age.dart';
import 'site_repository.dart';

/// Aggregates operational KPIs from existing inspection data (no extra tables).
class OpsMetricsRepository {
  OpsMetricsRepository(this._client, this._sites);

  final SupabaseClient _client;
  final SiteRepository _sites;

  Future<OpsSnapshot> load({
    required Profile profile,
    required OpsPeriod period,
    String? siteId,
    String language = 'en',
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final ar = language == 'ar';
    final now = qatarBusinessNow();
    final (presetFrom, presetTo) = period.range(now);
    final from = dateFrom == null
        ? presetFrom
        : DateTime(dateFrom.year, dateFrom.month, dateFrom.day);
    final to = dateTo == null
        ? presetTo
        : DateTime(dateTo.year, dateTo.month, dateTo.day);
    if (from.isAfter(to)) {
      throw ArgumentError('dateFrom must be on or before dateTo');
    }
    final today = DateTime(now.year, now.month, now.day);
    final complianceDate = to.isAfter(today) ? today : to;
    final complianceDateIso = _iso(complianceDate);

    var sites = await _sites.listAccessibleSites(profile: profile);
    if (siteId != null && siteId.isNotEmpty) {
      sites = sites.where((s) => s.id == siteId).toList();
    }
    final siteIds = sites.map((s) => s.id).toSet();
    if (siteIds.isEmpty) {
      return OpsSnapshot(
        period: period,
        dateFrom: from,
        dateTo: to,
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
            h.reviewStatus == ReviewStatus.draft ||
            h.reviewStatus == ReviewStatus.returned;
      }
      return h.reviewStatus == ReviewStatus.approved;
    }).toList();

    final bySite = <String, List<Inspection>>{};
    for (final h in visible) {
      bySite.putIfAbsent(h.siteId, () => []).add(h);
    }

    final visibleIds = {for (final inspection in visible) inspection.id};
    final periodDetailed = await _listDetailedHistory(
      ranges: [
        for (final id in siteIds)
          {'site_id': id, 'date_from': _iso(from), 'date_to': _iso(to)},
      ],
      approvedOnly: !canReview,
    );
    final periodDetailedBySite = <String, List<Inspection>>{};
    for (final inspection in periodDetailed) {
      if (!visibleIds.contains(inspection.id)) continue;
      periodDetailedBySite
          .putIfAbsent(inspection.siteId, () => [])
          .add(inspection);
    }

    // Open work orders must survive a period filter (for example, an issue
    // opened yesterday must still appear on the Today dashboard). Fetch the
    // latest detailed record and all required history in two batched RPCs.
    final latestDetailed = await _listLatestDetailed(
      siteIds: siteIds.toList(),
      approvedOnly: !canReview,
    );
    final latestBySite = {
      for (final inspection in latestDetailed) inspection.siteId: inspection,
    };
    final historyRanges = <Map<String, dynamic>>[];
    for (final inspection in latestDetailed) {
      final lookback = inspection.items.isEmpty
          ? 14
          : inspection.items
                .map((item) => item.overdueAfterDays)
                .fold<int>(14, (a, b) => a > b + 2 ? a : b + 2);
      historyRanges.add({
        'site_id': inspection.siteId,
        'date_from': _iso(
          inspection.inspectionDate.subtract(Duration(days: lookback)),
        ),
        'date_to': inspection.dateIso,
      });
    }
    final detailedHistory = await _listDetailedHistory(
      ranges: historyRanges,
      approvedOnly: !canReview,
    );
    final historyBySite = <String, List<Inspection>>{};
    for (final inspection in detailedHistory) {
      historyBySite.putIfAbsent(inspection.siteId, () => []).add(inspection);
    }

    final complianceDateDoneSites = <String>{};
    for (final h in visible) {
      if (h.dateIso != complianceDateIso) continue;
      if (h.awaitingReview || h.isApproved || h.isSubmitted) {
        complianceDateDoneSites.add(h.siteId);
      }
    }

    final pendingInScope = visible.where((h) => h.awaitingReview).toList();
    final nonDraft = visible
        .where(
          (h) =>
              h.reviewStatus == ReviewStatus.submitted ||
              h.reviewStatus == ReviewStatus.approved,
        )
        .toList();
    final approved = visible.where((h) => h.isApproved).toList();

    final siteRows = <SiteKpiRow>[];
    final followUps = <FollowUpItem>[];
    var overdueInspectionCount = 0;
    var openProblemTotal = 0;

    // Detailed metrics use latest inspection per site (with items).
    for (final site in sites) {
      final siteHeaders = bySite[site.id] ?? const <Inspection>[];
      final full = latestBySite[site.id];

      var idealRate = 0.0;
      var openProblems = 0;
      var overdueCount = 0;
      final periodAnswered = <InspectionItem>[
        for (final periodInspection
            in periodDetailedBySite[site.id] ?? const <Inspection>[])
          ...periodInspection.items.where((item) => item.response != null),
      ];
      final periodIdeal = periodAnswered
          .where((item) => item.isIdealAnswer)
          .length;
      idealRate = periodAnswered.isEmpty
          ? 0
          : periodIdeal / periodAnswered.length;
      if (full != null && full.items.isNotEmpty) {
        openProblems = full.items
            .where((i) => i.isProblem && !i.hasFixPhoto)
            .length;
        openProblemTotal += openProblems;

        List<Inspection> history = const [];
        var map = <String, Map<int, bool>>{};
        var overdue = <int>{};
        try {
          history = historyBySite[site.id] ?? [full];
          map = buildProblemHistory(history: history, current: full);
          overdue = overdueItemIndexes(inspection: full, problemByDateIso: map);
          overdueCount = overdue.length;
          if (overdue.isNotEmpty) {
            overdueInspectionCount++;
            final sorted = overdue.toList()..sort();
            for (final idx in sorted) {
              InspectionItem? item;
              for (final i in full.items) {
                if (i.itemIndex == idx) {
                  item = i;
                  break;
                }
              }
              final sla = item?.overdueAfterDays ?? 0;
              final openPath = item?.issueImagePaths.isNotEmpty == true
                  ? item!.issueImagePaths.first
                  : null;
              Duration? openFor;
              if (openPath != null) {
                openFor = openDurationForIssue(
                  history: history,
                  current: full,
                  itemIndex: idx,
                  issuePath: openPath,
                  problemByDateIso: map,
                  asOf: now,
                );
              } else {
                final start = problemStreakStart(
                  itemIndex: idx,
                  asOfDate: full.inspectionDate,
                  problemByDateIso: map,
                );
                if (start != null) {
                  openFor = now.difference(start);
                }
              }
              final age = openFor == null
                  ? ''
                  : formatOpenDurationCompact(openFor, arabic: ar);
              followUps.add(
                FollowUpItem(
                  kind: FollowUpKind.overdue,
                  inspectionId: full.id,
                  siteId: site.id,
                  buildingCode: full.buildingCode,
                  dateIso: full.dateIso,
                  title: ar
                      ? 'متأخر — ${full.buildingCode} بند $idx'
                      : 'Overdue — ${full.buildingCode} item $idx',
                  subtitle: ar
                      ? [
                          if (age.isNotEmpty) 'مفتوحة $age',
                          if (sla > 0) 'مهلة $sla يوم',
                          'متجاوزة',
                        ].join(' · ')
                      : [
                          if (age.isNotEmpty) 'Open $age',
                          if (sla > 0) 'SLA $sla d',
                          'OVERDUE',
                        ].join(' · '),
                ),
              );
            }
          }
        } catch (error) {
          throw StateError(
            'Failed to calculate overdue items for ${site.id}: $error',
          );
        }

        for (final item in full.items) {
          if (!(item.isProblem && !item.hasFixPhoto)) continue;
          final sla = item.overdueAfterDays;
          final overdueFlag = overdue.contains(item.itemIndex);
          String age = '';
          final openPath = item.issueImagePaths.isNotEmpty
              ? item.issueImagePaths.first
              : null;
          if (openPath != null && history.isNotEmpty) {
            final openFor = openDurationForIssue(
              history: history,
              current: full,
              itemIndex: item.itemIndex,
              issuePath: openPath,
              problemByDateIso: map,
              asOf: now,
            );
            if (openFor != null) {
              age = formatOpenDurationCompact(openFor, arabic: ar);
            }
          }
          followUps.add(
            FollowUpItem(
              kind: FollowUpKind.openProblems,
              inspectionId: full.id,
              siteId: site.id,
              buildingCode: full.buildingCode,
              dateIso: full.dateIso,
              title: ar
                  ? 'أمر عمل مفتوح — ${full.buildingCode} بند ${item.itemIndex}'
                  : 'Open WO — ${full.buildingCode} item ${item.itemIndex}',
              subtitle: ar
                  ? [
                      if (age.isNotEmpty) 'مفتوحة $age',
                      if (sla > 0) 'مهلة الإصلاح $sla يوم',
                      if (overdueFlag) 'متجاوزة',
                      if (!item.hasIssuePhoto) 'بدون صورة مشكلة',
                    ].join(' · ')
                  : [
                      if (age.isNotEmpty) 'Open $age',
                      if (sla > 0) 'Fix deadline $sla d',
                      if (overdueFlag) 'OVERDUE',
                      if (!item.hasIssuePhoto) 'missing issue photo',
                    ].join(' · '),
            ),
          );
        }
      }

      final approvedCount = siteHeaders.where((h) => h.isApproved).length;
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
          hasComplianceDateSubmission: complianceDateDoneSites.contains(
            site.id,
          ),
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
    final dailyCompliance = siteCount == 0
        ? 0.0
        : complianceDateDoneSites.length / siteCount;
    final completionRate = nonDraft.isEmpty
        ? 0.0
        : approved.length / nonDraft.length;

    return OpsSnapshot(
      period: period,
      dateFrom: from,
      dateTo: to,
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
      const pageSize = 500;
      for (var offset = 0; ; offset += pageSize) {
        final rows = await _client
            .from('checklist_inspections')
            .select('*, sites(name_en, name_ar, pin, organization_id)')
            .inFilter('site_id', slice)
            .gte('inspection_date', fromIso)
            .lte('inspection_date', toIso)
            .order('inspection_date', ascending: false)
            .range(offset, offset + pageSize - 1);
        for (final e in rows as List) {
          out.add(Inspection.fromJson(Map<String, dynamic>.from(e as Map)));
        }
        if (rows.length < pageSize) break;
      }
    }
    out.sort((a, b) => b.inspectionDate.compareTo(a.inspectionDate));
    return out;
  }

  Future<List<Inspection>> _listLatestDetailed({
    required List<String> siteIds,
    required bool approvedOnly,
  }) async {
    if (siteIds.isEmpty) return const [];
    final rows = await _client.rpc(
      'list_latest_checklist_inspections',
      params: {'p_site_ids': siteIds, 'p_approved_only': approvedOnly},
    );
    return _parseDetailedPayloads(rows);
  }

  Future<List<Inspection>> _listDetailedHistory({
    required List<Map<String, dynamic>> ranges,
    required bool approvedOnly,
  }) async {
    if (ranges.isEmpty) return const [];
    final rows = await _client.rpc(
      'list_checklist_inspection_history',
      params: {'p_ranges': ranges, 'p_approved_only': approvedOnly},
    );
    return _parseDetailedPayloads(rows);
  }

  List<Inspection> _parseDetailedPayloads(dynamic rows) {
    final inspections = <Inspection>[];
    for (final raw in rows as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final payload = Map<String, dynamic>.from(row['payload'] as Map);
      final items = [
        for (final item in payload['items'] as List? ?? const [])
          InspectionItem.fromJson(Map<String, dynamic>.from(item as Map)),
      ];
      inspections.add(Inspection.fromJson(payload, items: items));
    }
    return inspections;
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
