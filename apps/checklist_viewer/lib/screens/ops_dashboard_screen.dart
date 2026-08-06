import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Full operations hub: KPIs, follow-ups, and site ranking.
class OpsDashboardScreen extends ConsumerStatefulWidget {
  const OpsDashboardScreen({
    super.key,
    required this.profile,
    required this.language,
    required this.onOpenInspection,
  });

  final Profile profile;
  final String language;
  final Future<void> Function(String inspectionId) onOpenInspection;

  @override
  ConsumerState<OpsDashboardScreen> createState() => _OpsDashboardScreenState();
}

class _OpsDashboardScreenState extends ConsumerState<OpsDashboardScreen> {
  OpsPeriod period = OpsPeriod.today;
  String? siteFilter;
  OpsSnapshot? snapshot;
  List<ChecklistSite> sites = [];
  List<CampusChecklistGroup> campusGroups = [];
  bool loading = true;
  String? error;

  bool get ar => widget.language == 'ar';

  String _siteFilterLabel(ChecklistSite s) {
    CampusChecklistGroup? group;
    for (final g in campusGroups) {
      if (g.checklists.any((c) => c.id == s.id)) {
        group = g;
        break;
      }
    }
    final campus = group?.campus?.nameFor(widget.language);
    if (campus == null || campus.isEmpty) {
      return '${s.buildingCode} — ${s.nameFor(widget.language)}';
    }
    return '$campus › ${s.buildingCode}';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final siteList = await ref
          .read(siteRepositoryProvider)
          .listAccessibleCampusGroups(profile: widget.profile);
      final snap = await ref.read(opsMetricsRepositoryProvider).load(
            profile: widget.profile,
            period: period,
            siteId: siteFilter,
            language: widget.language,
          );
      if (!mounted) return;
      setState(() {
        campusGroups = siteList;
        sites = [for (final g in siteList) ...g.checklists];
        snapshot = snap;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = '$e';
        loading = false;
      });
    }
  }

  String _pct(double v) => '${(v * 100).clamp(0, 100).toStringAsFixed(0)}%';

  String _periodLabel(OpsPeriod p) => switch (p) {
        OpsPeriod.today => ar ? 'اليوم' : 'Today',
        OpsPeriod.days7 => ar ? '7 أيام' : '7 days',
        OpsPeriod.days30 => ar ? '30 يوماً' : '30 days',
      };

  @override
  Widget build(BuildContext context) {
    final snap = snapshot;
    return Scaffold(
      appBar: checklistGradientAppBar(
        title: ar ? 'المتابعة والإشراف' : 'Ops & Supervision',
        actions: [
          IconButton(
            tooltip: ar ? 'تحديث' : 'Refresh',
            onPressed: loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          _filtersBar(),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            error!,
                            style: const TextStyle(color: Colors.red),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : snap == null
                        ? Center(
                            child: Text(
                              ar ? 'لا توجد بيانات' : 'No data',
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                              children: [
                                _sectionTitle(
                                  ar ? 'مؤشرات الأداء' : 'KPI Overview',
                                ),
                                const SizedBox(height: 10),
                                _kpiGrid(snap),
                                const SizedBox(height: 22),
                                _sectionTitle(
                                  ar ? 'متابعة مطلوبة' : 'Follow-up',
                                ),
                                const SizedBox(height: 8),
                                _followUpSection(
                                  title: ar
                                      ? 'بانتظار الاعتماد'
                                      : 'Pending approval',
                                  items: snap.followUpsOf(
                                    FollowUpKind.pendingReview,
                                  ),
                                  color: ChecklistChrome.accent,
                                  icon: Icons.rate_review_outlined,
                                ),
                                _followUpSection(
                                  title: ar ? 'بنود متأخرة' : 'Overdue',
                                  items:
                                      snap.followUpsOf(FollowUpKind.overdue),
                                  color: const Color(0xFFB91C1C),
                                  icon: Icons.warning_amber_rounded,
                                ),
                                _followUpSection(
                                  title:
                                      ar ? 'مشاكل مفتوحة' : 'Open problems',
                                  items: snap.followUpsOf(
                                    FollowUpKind.openProblems,
                                  ),
                                  color: const Color(0xFFEA580C),
                                  icon: Icons.build_circle_outlined,
                                ),
                                const SizedBox(height: 18),
                                _sectionTitle(
                                  ar ? 'ترتيب المواقع' : 'Site ranking',
                                ),
                                const SizedBox(height: 8),
                                _sitesRanking(
                                  title: ar ? 'الأفضل أداءً' : 'Top sites',
                                  rows: snap.bestSites,
                                  positive: true,
                                ),
                                const SizedBox(height: 12),
                                _sitesRanking(
                                  title: ar
                                      ? 'تحتاج اهتماماً'
                                      : 'Needs attention',
                                  rows: snap.worstSites,
                                  positive: false,
                                ),
                              ],
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _filtersBar() {
    return Material(
      color: ChecklistChrome.surface,
      elevation: 0.5,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              ar ? 'الفترة' : 'Period',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: ChecklistChrome.inkMuted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 6),
            SegmentedButton<OpsPeriod>(
              segments: [
                for (final p in OpsPeriod.values)
                  ButtonSegment(value: p, label: Text(_periodLabel(p))),
              ],
              selected: {period},
              showSelectedIcon: false,
              onSelectionChanged: (s) {
                setState(() => period = s.first);
                _load();
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              // ignore: deprecated_member_use
              value: siteFilter,
              decoration: InputDecoration(
                labelText: ar ? 'قائمة الفحص' : 'Checklist',
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(ar ? 'كل القوائم' : 'All checklists'),
                ),
                for (final s in sites)
                  DropdownMenuItem<String?>(
                    value: s.id,
                    child: Text(
                      _siteFilterLabel(s),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) {
                setState(() => siteFilter = v);
                _load();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: ChecklistChrome.ink,
      ),
    );
  }

  Widget _kpiGrid(OpsSnapshot snap) {
    final cards = <_KpiCardData>[
      _KpiCardData(
        label: ar ? 'الالتزام اليومي' : 'Daily compliance',
        value: _pct(snap.dailyCompliance),
        detail: ar
            ? '${(snap.dailyCompliance * snap.siteCount).round()}/${snap.siteCount} مواقع'
            : '${(snap.dailyCompliance * snap.siteCount).round()}/${snap.siteCount} sites',
        progress: snap.dailyCompliance,
        color: const Color(0xFF15803D),
        icon: Icons.fact_check_outlined,
      ),
      _KpiCardData(
        label: ar ? 'بانتظار الاعتماد' : 'Pending review',
        value: '${snap.pendingReviewCount}',
        detail: ar ? 'فحوصات للقرار' : 'Awaiting decision',
        progress: snap.siteCount == 0
            ? 0
            : (snap.pendingReviewCount / snap.siteCount).clamp(0, 1),
        color: ChecklistChrome.accent,
        icon: Icons.rate_review_outlined,
      ),
      _KpiCardData(
        label: ar ? 'فحوصات متأخرة' : 'Overdue inspections',
        value: '${snap.overdueInspectionCount}',
        detail: ar ? 'بمواقع فيها بنود متأخرة' : 'Sites with overdue items',
        progress: snap.siteCount == 0
            ? 0
            : (snap.overdueInspectionCount / snap.siteCount).clamp(0, 1),
        color: const Color(0xFFB91C1C),
        icon: Icons.warning_amber_rounded,
      ),
      _KpiCardData(
        label: ar ? 'مشاكل مفتوحة' : 'Open problems',
        value: '${snap.openProblemCount}',
        detail: ar ? 'بنود بدون إصلاح' : 'Items without fix photo',
        progress: 0,
        color: const Color(0xFFEA580C),
        icon: Icons.build_circle_outlined,
      ),
      _KpiCardData(
        label: ar ? 'نسبة الإنجاز' : 'Completion rate',
        value: _pct(snap.completionRate),
        detail: ar
            ? '${snap.approvedInPeriod}/${snap.totalInspectionsInPeriod} معتمد'
            : '${snap.approvedInPeriod}/${snap.totalInspectionsInPeriod} approved',
        progress: snap.completionRate,
        color: ChecklistChrome.primary,
        icon: Icons.verified_outlined,
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 720;
        if (wide) {
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final card in cards)
                SizedBox(
                  width: (c.maxWidth - 20) / 3,
                  child: _kpiCard(card),
                ),
            ],
          );
        }
        return Column(
          children: [
            for (final card in cards) ...[
              _kpiCard(card),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }

  Widget _kpiCard(_KpiCardData data) {
    return ChecklistBrandCard(
      borderColor: data.color.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ChecklistIconWell(icon: data.icon),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  data.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: ChecklistChrome.ink,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            data.value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: data.color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            data.detail,
            style: TextStyle(color: ChecklistChrome.inkMuted, fontSize: 12),
          ),
          if (data.progress > 0) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: data.progress.clamp(0, 1),
                minHeight: 7,
                backgroundColor: data.color.withValues(alpha: 0.12),
                color: data.color,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _followUpSection({
    required String title,
    required List<FollowUpItem> items,
    required Color color,
    required IconData icon,
  }) {
    return ChecklistBrandCard(
      borderColor: color.withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: ChecklistChrome.ink,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${items.length}',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Text(
              ar ? 'لا يوجد عناصر حالياً' : 'Nothing to follow up',
              style: TextStyle(color: ChecklistChrome.inkMuted),
            )
          else
            ...items.take(12).map(
              (item) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(item.title),
                subtitle: Text(item.subtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => widget.onOpenInspection(item.inspectionId),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sitesRanking({
    required String title,
    required List<SiteKpiRow> rows,
    required bool positive,
  }) {
    final accent =
        positive ? const Color(0xFF15803D) : const Color(0xFFB45309);
    return ChecklistBrandCard(
      borderColor: accent.withValues(alpha: 0.25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: ChecklistChrome.ink,
            ),
          ),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            Text(
              ar ? 'لا مواقع في النطاق' : 'No sites in scope',
              style: TextStyle(color: ChecklistChrome.inkMuted),
            )
          else
            ...rows.map((r) {
              final scorePct = (r.score * 100).clamp(0, 100).toStringAsFixed(0);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${r.buildingCode} — ${r.siteName}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          '$scorePct%',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ar
                          ? 'مثالي ${_pct(r.idealRate)} · اعتماد ${_pct(r.approvalRate)} · مشاكل ${r.openProblemCount}'
                          : 'Ideal ${_pct(r.idealRate)} · Approved ${_pct(r.approvalRate)} · Issues ${r.openProblemCount}',
                      style: TextStyle(
                        fontSize: 11,
                        color: ChecklistChrome.inkMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: r.score.clamp(0, 1),
                        minHeight: 6,
                        backgroundColor: accent.withValues(alpha: 0.12),
                        color: accent,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _KpiCardData {
  const _KpiCardData({
    required this.label,
    required this.value,
    required this.detail,
    required this.progress,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final String detail;
  final double progress;
  final Color color;
  final IconData icon;
}
