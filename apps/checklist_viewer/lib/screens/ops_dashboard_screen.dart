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
  DateTimeRange? customRange;
  String? siteFilter;
  OpsSnapshot? snapshot;
  List<ChecklistSite> sites = [];
  List<CampusChecklistGroup> campusGroups = [];
  bool loading = true;
  String? error;
  int? _lastUrgentCount;
  int _loadGeneration = 0;

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
    final generation = ++_loadGeneration;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final results = await Future.wait<Object>([
        ref
            .read(siteRepositoryProvider)
            .listAccessibleCampusGroups(profile: widget.profile),
        ref
            .read(opsMetricsRepositoryProvider)
            .load(
              profile: widget.profile,
              period: period,
              siteId: siteFilter,
              language: widget.language,
              dateFrom: customRange?.start,
              dateTo: customRange?.end,
            ),
      ]);
      final siteList = results[0] as List<CampusChecklistGroup>;
      final snap = results[1] as OpsSnapshot;
      if (!mounted || generation != _loadGeneration) return;
      final urgent =
          snap.pendingReviewCount +
          snap.overdueInspectionCount +
          snap.openProblemCount;
      final shouldAlert =
          _lastUrgentCount != null && urgent > _lastUrgentCount!;
      setState(() {
        campusGroups = siteList;
        sites = [for (final g in siteList) ...g.checklists];
        snapshot = snap;
        loading = false;
        _lastUrgentCount = urgent;
      });
      if (shouldAlert && ref.read(notificationsEnabledProvider)) {
        await ChecklistFeedback.alert(
          soundEnabled: ref.read(soundEnabledProvider),
          hapticsEnabled: ref.read(hapticsEnabledProvider),
        );
      }
    } catch (e, stack) {
      await StructuredErrorReporter.capture(
        e,
        stack,
        module: 'viewer.supervision_load',
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        error = '$e';
        loading = false;
      });
    }
  }

  String _pct(double v) => '${(v * 100).clamp(0, 100).toStringAsFixed(0)}%';

  String _periodLabel(OpsPeriod p) => switch (p) {
    OpsPeriod.today => ar ? 'اليوم' : 'Today',
    OpsPeriod.thisWeek => ar ? 'هذا الأسبوع' : 'This week',
    OpsPeriod.thisMonth => ar ? 'هذا الشهر' : 'This month',
    OpsPeriod.lastMonth => ar ? 'الشهر الماضي' : 'Last month',
    OpsPeriod.last3Months => ar ? 'آخر 3 أشهر' : 'Last 3 months',
    OpsPeriod.last6Months => ar ? 'آخر 6 أشهر' : 'Last 6 months',
    OpsPeriod.thisYear => ar ? 'هذه السنة' : 'This year',
  };

  String _iso(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Future<void> _pickCustomRange() async {
    final now = qatarBusinessNow();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: today,
      initialDateRange: customRange ?? DateTimeRange(start: today, end: today),
      helpText: ar ? 'حدد فترة التقرير' : 'Select report range',
    );
    if (picked == null) return;
    setState(() => customRange = picked);
    await _load();
  }

  Future<void> _exportReport() async {
    final snap = snapshot;
    if (snap == null) return;
    try {
      var scope = ar ? 'كل القوائم' : 'All checklists';
      if (siteFilter != null) {
        for (final site in sites) {
          if (site.id == siteFilter) {
            scope = _siteFilterLabel(site);
            break;
          }
        }
      }
      await const OpsReportExporter().sharePdf(
        snapshot: snap,
        language: widget.language,
        scopeLabel: scope,
      );
    } catch (exception, stack) {
      await StructuredErrorReporter.capture(
        exception,
        stack,
        module: 'viewer.supervision_report',
      );
      if (!mounted) return;
      setState(() => error = '$exception');
    }
  }

  @override
  Widget build(BuildContext context) {
    final snap = snapshot;
    return Scaffold(
      appBar: checklistGradientAppBar(
        title: ar ? 'المتابعة والإشراف' : 'Ops & Supervision',
        leading: checklistBackButton(context),
        actions: [
          if (snapshot != null)
            IconButton(
              tooltip: ar ? 'تصدير تقرير PDF' : 'Export PDF report',
              onPressed: loading ? null : _exportReport,
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
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
                ? Center(child: Text(ar ? 'لا توجد بيانات' : 'No data'))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                      children: [
                        _operationalPulse(snap),
                        const SizedBox(height: 18),
                        _sectionTitle(ar ? 'مؤشرات الأداء' : 'KPI Overview'),
                        const SizedBox(height: 10),
                        _kpiGrid(snap),
                        const SizedBox(height: 22),
                        _sectionTitle(ar ? 'متابعة مطلوبة' : 'Follow-up'),
                        const SizedBox(height: 8),
                        _followUpSection(
                          title: ar ? 'بانتظار الاعتماد' : 'Pending approval',
                          items: snap.followUpsOf(FollowUpKind.pendingReview),
                          color: ChecklistChrome.accent,
                          icon: Icons.rate_review_outlined,
                        ),
                        _followUpSection(
                          title: ar ? 'بنود متأخرة' : 'Overdue',
                          items: snap.followUpsOf(FollowUpKind.overdue),
                          color: const Color(0xFFB91C1C),
                          icon: Icons.warning_amber_rounded,
                        ),
                        _followUpSection(
                          title: ar ? 'مشاكل مفتوحة' : 'Open problems',
                          items: snap.followUpsOf(FollowUpKind.openProblems),
                          color: const Color(0xFFEA580C),
                          icon: Icons.build_circle_outlined,
                        ),
                        const SizedBox(height: 18),
                        _sectionTitle(ar ? 'ترتيب المواقع' : 'Site ranking'),
                        const SizedBox(height: 8),
                        _sitesRanking(
                          title: ar ? 'الأفضل أداءً' : 'Top sites',
                          rows: snap.bestSites,
                          positive: true,
                        ),
                        const SizedBox(height: 12),
                        _sitesRanking(
                          title: ar ? 'تحتاج اهتماماً' : 'Needs attention',
                          rows: snap.worstSites,
                          positive: false,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          ar
                              ? 'التقييم يدمج نسبة الإجابة المثالية، الاعتماد، والامتثال اليومي. بنود المتأخرة تستخدم مهلة الأوفر ديو لكل بند من إعدادات القوائم.'
                              : 'Ranking blends ideal answer rate, approval rate, and today’s compliance. Overdue uses each item’s fix deadline from checklist settings.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
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
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface.withValues(
        alpha: ChecklistChrome.listSurfaceOpacity,
      ),
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
                color: colors.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<OpsPeriod>(
              initialValue: period,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: ar ? 'اختيار سريع' : 'Quick range',
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final p in OpsPeriod.values)
                  DropdownMenuItem(value: p, child: Text(_periodLabel(p))),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  period = value;
                  customRange = null;
                });
                _load();
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pickCustomRange,
              icon: const Icon(Icons.date_range_outlined),
              label: Text(
                customRange == null
                    ? (ar ? 'فترة مخصصة' : 'Custom date range')
                    : '${_iso(customRange!.start)} — ${_iso(customRange!.end)}',
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              initialValue: siteFilter,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: ar ? 'قائمة الفحص' : 'Checklist',
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(
                    ar ? 'كل القوائم' : 'All checklists',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                for (final s in sites)
                  DropdownMenuItem<String?>(
                    value: s.id,
                    child: Text(
                      _siteFilterLabel(s),
                      maxLines: 1,
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
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }

  Widget _operationalPulse(OpsSnapshot snap) {
    final urgent =
        snap.pendingReviewCount +
        snap.overdueInspectionCount +
        snap.openProblemCount;
    final healthy = urgent == 0;
    final pulseColor = healthy
        ? const Color(0xFF15803D)
        : urgent <= 3
        ? const Color(0xFFB45309)
        : const Color(0xFFB91C1C);
    final time = TimeOfDay.fromDateTime(snap.asOf.toLocal()).format(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChecklistPulseCard(
          title: healthy
              ? (ar ? 'الوضع التشغيلي مستقر' : 'Operations are stable')
              : (ar ? 'توجد متابعة تحتاج إجراء' : 'Follow-up needs action'),
          subtitle: ar
              ? 'آخر تحديث $time · يعرض المؤشر الالتزام والاعتماد والمشكلات النشطة ضمن النطاق المحدد.'
              : 'Updated $time · The pulse combines compliance, approvals, and active issues in the selected scope.',
          progress: snap.dailyCompliance,
          progressLabel: _pct(snap.dailyCompliance),
          color: pulseColor,
          icon: healthy
              ? Icons.monitor_heart_outlined
              : Icons.notification_important_outlined,
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: pulseColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              ar ? '$urgent إجراء' : '$urgent action(s)',
              style: TextStyle(
                color: pulseColor,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 720;
            final tileWidth = wide
                ? (constraints.maxWidth - 20) / 3
                : constraints.maxWidth;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: tileWidth,
                  child: ChecklistMetricTile(
                    label: ar ? 'بانتظار الاعتماد' : 'Pending approval',
                    value: '${snap.pendingReviewCount}',
                    icon: Icons.rate_review_outlined,
                    color: ChecklistChrome.accent,
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: ChecklistMetricTile(
                    label: ar ? 'قوائم متأخرة' : 'Overdue checklists',
                    value: '${snap.overdueInspectionCount}',
                    icon: Icons.timer_outlined,
                    color: const Color(0xFFB91C1C),
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: ChecklistMetricTile(
                    label: ar ? 'مشكلات مفتوحة' : 'Open problems',
                    value: '${snap.openProblemCount}',
                    icon: Icons.build_circle_outlined,
                    color: const Color(0xFFEA580C),
                  ),
                ),
              ],
            );
          },
        ),
      ],
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
                SizedBox(width: (c.maxWidth - 20) / 3, child: _kpiCard(card)),
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
    final colors = Theme.of(context).colorScheme;
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
                    color: colors.onSurface,
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
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
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
    final colors = Theme.of(context).colorScheme;
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
                    color: colors.onSurface,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
              style: TextStyle(color: colors.onSurfaceVariant),
            )
          else
            ...items
                .take(12)
                .map(
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
    final colors = Theme.of(context).colorScheme;
    final accent = positive ? const Color(0xFF15803D) : const Color(0xFFB45309);
    return ChecklistBrandCard(
      borderColor: accent.withValues(alpha: 0.25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            Text(
              ar ? 'لا مواقع في النطاق' : 'No sites in scope',
              style: TextStyle(color: colors.onSurfaceVariant),
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
                          ? 'مثالي ${_pct(r.idealRate)} · اعتماد ${_pct(r.approvalRate)} · مفتوحة ${r.openProblemCount} · متأخرة ${r.overdueCount}'
                          : 'Ideal ${_pct(r.idealRate)} · Approved ${_pct(r.approvalRate)} · Open ${r.openProblemCount} · Overdue ${r.overdueCount}',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
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
