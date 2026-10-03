import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/checkview_tokens.dart';
import '../design/checkview_errors.dart';
import '../design/checkview_widgets.dart';

const _followUpPreviewCount = 12;
const _customRangeChoice = -1;

/// Operations overview: compliance pulse, follow-ups, KPIs and site ranking.
class OpsDashboardScreen extends ConsumerStatefulWidget {
  const OpsDashboardScreen({
    super.key,
    required this.profile,
    required this.language,
    required this.onOpenInspection,
    this.onOpenSettings,
  });

  final Profile profile;
  final String language;
  final Future<void> Function(String inspectionId) onOpenInspection;

  /// Shown as a settings action when hosted in the CheckView shell.
  final VoidCallback? onOpenSettings;

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
      return '${s.buildingCode}  ${s.nameFor(widget.language)}';
    }
    return '$campus  /  ${s.buildingCode}';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant OpsDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Follow-up titles are localized by the metrics repository.
    if (oldWidget.language != widget.language) _load();
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

  String get _scopeLabel {
    if (siteFilter != null) {
      for (final site in sites) {
        if (site.id == siteFilter) return _siteFilterLabel(site);
      }
    }
    return ar ? 'كل القوائم' : 'All checklists';
  }

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
    if (picked == null || !mounted) return;
    setState(() => customRange = picked);
    await _load();
  }

  Future<void> _pickPeriod() async {
    final picked = await showCvChoiceSheet<int>(
      context: context,
      title: ar ? 'الفترة' : 'Period',
      selected: customRange != null ? _customRangeChoice : period.index,
      choices: [
        for (final p in OpsPeriod.values)
          CvChoice(value: p.index, label: _periodLabel(p)),
        CvChoice(
          value: _customRangeChoice,
          icon: Icons.date_range_outlined,
          label: ar ? 'فترة مخصصة' : 'Custom date range',
          description: customRange == null
              ? null
              : '${_iso(customRange!.start)}  –  ${_iso(customRange!.end)}',
        ),
      ],
    );
    if (picked == null || !mounted) return;
    if (picked == _customRangeChoice) {
      await _pickCustomRange();
      return;
    }
    setState(() {
      period = OpsPeriod.values[picked];
      customRange = null;
    });
    await _load();
  }

  Future<void> _pickScope() async {
    final picked = await showCvChoiceSheet<String>(
      context: context,
      title: ar ? 'قائمة الفحص' : 'Checklist',
      selected: siteFilter ?? '',
      choices: [
        CvChoice(value: '', label: ar ? 'كل القوائم' : 'All checklists'),
        for (final s in sites)
          CvChoice(value: s.id, label: _siteFilterLabel(s)),
      ],
    );
    if (picked == null || !mounted) return;
    final next = picked.isEmpty ? null : picked;
    if (next == siteFilter) return;
    setState(() => siteFilter = next);
    await _load();
  }

  Future<void> _exportReport() async {
    final snap = snapshot;
    if (snap == null) return;
    try {
      await const OpsReportExporter().sharePdf(
        snapshot: snap,
        language: widget.language,
        scopeLabel: _scopeLabel,
      );
    } catch (exception, stack) {
      await StructuredErrorReporter.capture(
        exception,
        stack,
        module: 'viewer.supervision_report',
      );
      if (!mounted) return;
      setState(() => error = cvUserMessage(exception, widget.language));
    }
  }

  @override
  Widget build(BuildContext context) {
    final snap = snapshot;
    return Scaffold(
      appBar: AppBar(
        title: Text(ar ? 'العمليات' : 'Operations'),
        actions: [
          if (snap != null)
            IconButton(
              tooltip: ar ? 'تقرير PDF' : 'PDF report',
              onPressed: loading ? null : _exportReport,
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
          IconButton(
            tooltip: ar ? 'تحديث' : 'Refresh',
            onPressed: loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          if (widget.onOpenSettings != null)
            IconButton(
              tooltip: ar ? 'الإعدادات' : 'Settings',
              onPressed: widget.onOpenSettings,
              icon: const Icon(Icons.tune),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CvTitleBlock(
            loading: loading,
            fields: [
              CvTitleField(
                label: ar ? 'الفترة' : 'Period',
                value: customRange == null
                    ? _periodLabel(period)
                    : '${_iso(customRange!.start)}  –  '
                          '${_iso(customRange!.end)}',
                onTap: _pickPeriod,
                flex: 2,
                maxLines: 2,
              ),
              CvTitleField(
                label: ar ? 'النطاق' : 'Scope',
                value: _scopeLabel,
                onTap: _pickScope,
                flex: 3,
                maxLines: 2,
              ),
              CvTitleField(
                label: ar ? 'آخر تحديث' : 'Updated',
                value: snap == null
                    ? (ar ? 'جارٍ التحميل' : 'Loading')
                    : TimeOfDay.fromDateTime(
                        snap.asOf.toLocal(),
                      ).format(context),
                flex: 2,
              ),
            ],
          ),
          if (error != null && snap != null)
            CvBanner(
              tone: CvBannerTone.error,
              message: error!,
              onDismiss: () => setState(() => error = null),
            ),
          Expanded(child: _content(snap)),
        ],
      ),
    );
  }

  Widget _content(OpsSnapshot? snap) {
    if (snap == null) {
      if (error != null) {
        return CvErrorState(
          title: ar ? 'تعذر تحميل المؤشرات' : 'Operations data did not load',
          message: error!,
          retryLabel: ar ? 'إعادة المحاولة' : 'Try again',
          onRetry: _load,
        );
      }
      return ListView(
        padding: const EdgeInsets.all(CvSpace.gutter),
        children: const [CvSkeletonLedger(rows: 3)],
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: AnimatedOpacity(
        opacity: loading ? 0.55 : 1,
        duration: CvMotion.of(context, CvMotion.quick),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= CvBreakpoint.twoColumn;
            final primary = _primaryColumn(snap);
            final secondary = _secondaryColumn(snap);
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                CvSpace.gutter,
                CvSpace.lg,
                CvSpace.gutter,
                CvSpace.xxl,
              ),
              children: twoColumns
                  ? [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: primary,
                            ),
                          ),
                          const SizedBox(width: CvSpace.xl),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: secondary,
                            ),
                          ),
                        ],
                      ),
                    ]
                  : [...primary, ...secondary],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _primaryColumn(OpsSnapshot snap) => [
    _PulsePanel(snap: snap, language: widget.language, percent: _pct),
    const SizedBox(height: CvSpace.md),
    CvTally(
      items: [
        CvTallyItem(
          label: ar ? 'بانتظار الاعتماد' : 'Pending approval',
          count: snap.pendingReviewCount,
          tone: CvTone.pending,
        ),
        CvTallyItem(
          label: ar ? 'قوائم متأخرة' : 'Overdue checklists',
          count: snap.overdueInspectionCount,
          tone: CvTone.rejected,
        ),
        CvTallyItem(
          label: ar ? 'مشكلات مفتوحة' : 'Open problems',
          count: snap.openProblemCount,
          tone: CvTone.returned,
        ),
      ],
    ),
    ..._followUp(
      title: ar ? 'بانتظار الاعتماد' : 'Pending approval',
      items: snap.followUpsOf(FollowUpKind.pendingReview),
    ),
    ..._followUp(
      title: ar ? 'بنود متأخرة' : 'Overdue',
      items: snap.followUpsOf(FollowUpKind.overdue),
    ),
    ..._followUp(
      title: ar ? 'مشاكل مفتوحة' : 'Open problems',
      items: snap.followUpsOf(FollowUpKind.openProblems),
    ),
  ];

  List<Widget> _secondaryColumn(OpsSnapshot snap) => [
    CvSectionHeader(title: ar ? 'مؤشرات الأداء' : 'Performance'),
    _KpiGrid(cells: _kpis(snap)),
    CvSectionHeader(title: ar ? 'الأفضل أداءً' : 'Top sites'),
    _ranking(snap.bestSites, positive: true),
    CvSectionHeader(title: ar ? 'تحتاج اهتمامًا' : 'Needs attention'),
    _ranking(snap.worstSites, positive: false),
    Padding(
      padding: const EdgeInsets.fromLTRB(4, CvSpace.lg, 4, 0),
      child: Text(
        ar
            ? 'التقييم يدمج نسبة الإجابة المثالية، الاعتماد، والامتثال اليومي. البنود المتأخرة تستخدم مهلة الإصلاح لكل بند من إعدادات القوائم.'
            : 'Ranking blends ideal answer rate, approval rate, and today’s compliance. Overdue uses each item’s fix deadline from checklist settings.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ),
  ];

  Widget _quietLine(String text) => Padding(
    padding: const EdgeInsets.all(CvSpace.gutter),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: CheckViewColors.of(context).inkMuted,
      ),
    ),
  );

  List<Widget> _followUp({
    required String title,
    required List<FollowUpItem> items,
  }) {
    final visible = items.take(_followUpPreviewCount).toList();
    return [
      CvSectionHeader(title: title, count: items.length),
      CvLedger(
        children: items.isEmpty
            ? [
                _quietLine(
                  ar ? 'لا يوجد ما يحتاج متابعة' : 'Nothing to follow up',
                ),
              ]
            : [
                for (final item in visible)
                  CvLedgerRow(
                    title: item.title,
                    subtitle: item.subtitle,
                    onTap: () => widget.onOpenInspection(item.inspectionId),
                  ),
                if (items.length > visible.length)
                  Padding(
                    padding: const EdgeInsets.all(CvSpace.gutter),
                    child: CvMeta(
                      ar
                          ? 'يعرض ${visible.length} من ${items.length}'
                          : 'Showing ${visible.length} of ${items.length}',
                    ),
                  ),
              ],
      ),
    ];
  }

  List<_KpiCell> _kpis(OpsSnapshot snap) {
    final complianceSites = (snap.dailyCompliance * snap.siteCount).round();
    return [
      _KpiCell(
        label: snap.complianceDateIsToday
            ? (ar ? 'الالتزام اليومي' : 'Daily compliance')
            : (ar ? 'التزام نهاية الفترة' : 'Period-end compliance'),
        value: _pct(snap.dailyCompliance),
        detail: ar
            ? '$complianceSites من ${snap.siteCount} مواقع'
            : '$complianceSites of ${snap.siteCount} sites',
        progress: snap.dailyCompliance,
        tone: CvTone.approved,
      ),
      _KpiCell(
        label: ar ? 'بانتظار الاعتماد' : 'Pending review',
        value: '${snap.pendingReviewCount}',
        detail: ar ? 'فحوصات للقرار' : 'Awaiting decision',
        progress: snap.siteCount == 0
            ? 0
            : (snap.pendingReviewCount / snap.siteCount).clamp(0, 1),
        tone: CvTone.pending,
      ),
      _KpiCell(
        label: ar ? 'فحوصات متأخرة' : 'Overdue inspections',
        value: '${snap.overdueInspectionCount}',
        detail: ar ? 'مواقع فيها بنود متأخرة' : 'Sites with overdue items',
        progress: snap.siteCount == 0
            ? 0
            : (snap.overdueInspectionCount / snap.siteCount).clamp(0, 1),
        tone: CvTone.rejected,
      ),
      _KpiCell(
        label: ar ? 'مشاكل مفتوحة' : 'Open problems',
        value: '${snap.openProblemCount}',
        detail: ar ? 'بنود بدون صورة إصلاح' : 'Items without fix photo',
        progress: 0,
        tone: CvTone.returned,
      ),
      _KpiCell(
        label: ar ? 'نسبة الإنجاز' : 'Completion rate',
        value: _pct(snap.completionRate),
        detail: ar
            ? '${snap.approvedInPeriod} من ${snap.totalInspectionsInPeriod} معتمد'
            : '${snap.approvedInPeriod} of ${snap.totalInspectionsInPeriod} approved',
        progress: snap.completionRate,
        tone: CvTone.accent,
      ),
    ];
  }

  Widget _ranking(List<SiteKpiRow> rows, {required bool positive}) {
    final c = CheckViewColors.of(context);
    final theme = Theme.of(context);
    final tone = positive ? c.approved : c.returned;
    if (rows.isEmpty) {
      return CvLedger(
        children: [_quietLine(ar ? 'لا مواقع في النطاق' : 'No sites in scope')],
      );
    }
    return CvLedger(
      children: [
        for (final r in rows)
          MergeSemantics(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: CvSpace.gutter,
                vertical: CvSpace.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          '${r.buildingCode}   ${r.siteName}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(width: CvSpace.md),
                      Text(
                        _pct(r.score),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: tone,
                          fontFeatures: cvTabular,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: CvSpace.sm),
                  _Bar(value: r.score, color: tone),
                  const SizedBox(height: CvSpace.sm),
                  Wrap(
                    spacing: CvSpace.md,
                    runSpacing: 2,
                    children: [
                      CvMeta(
                        ar
                            ? 'مثالي ${_pct(r.idealRate)}'
                            : 'Ideal ${_pct(r.idealRate)}',
                      ),
                      CvMeta(
                        ar
                            ? 'اعتماد ${_pct(r.approvalRate)}'
                            : 'Approved ${_pct(r.approvalRate)}',
                      ),
                      CvMeta(
                        ar
                            ? 'مفتوحة ${r.openProblemCount}'
                            : 'Open ${r.openProblemCount}',
                      ),
                      CvMeta(
                        ar
                            ? 'متأخرة ${r.overdueCount}'
                            : 'Overdue ${r.overdueCount}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// The opening figure: compliance as a large light numeral beside the
/// operational verdict for the selected scope.
class _PulsePanel extends StatelessWidget {
  const _PulsePanel({
    required this.snap,
    required this.language,
    required this.percent,
  });

  final OpsSnapshot snap;
  final String language;
  final String Function(double) percent;

  @override
  Widget build(BuildContext context) {
    final c = CheckViewColors.of(context);
    final theme = Theme.of(context);
    final ar = language == 'ar';
    final urgent =
        snap.pendingReviewCount +
        snap.overdueInspectionCount +
        snap.openProblemCount;
    final healthy = urgent == 0;
    final verdictTone = healthy
        ? CvTone.approved
        : urgent <= 3
        ? CvTone.pending
        : CvTone.rejected;
    final complianceSites = (snap.dailyCompliance * snap.siteCount).round();

    final figure = MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            snap.complianceDateIsToday
                ? (ar ? 'الالتزام اليومي' : 'Daily compliance')
                : (ar ? 'التزام نهاية الفترة' : 'Period-end compliance'),
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: CvSpace.xs),
          Text(
            percent(snap.dailyCompliance),
            style: theme.textTheme.displaySmall,
          ),
          const SizedBox(height: CvSpace.xs),
          Text(
            ar
                ? '$complianceSites من ${snap.siteCount} مواقع'
                : '$complianceSites of ${snap.siteCount} sites',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );

    final verdict = MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          CvStatusMark(
            tone: verdictTone,
            label: healthy
                ? (ar ? 'مستقر' : 'Stable')
                : (ar ? 'يتطلب إجراء' : 'Action needed'),
          ),
          const SizedBox(height: CvSpace.sm),
          Text(
            healthy
                ? (ar ? 'الوضع التشغيلي مستقر' : 'Operations are stable')
                : (ar ? 'توجد متابعة تحتاج إجراء' : 'Follow-up needs action'),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 2),
          Text(
            ar ? '$urgent بنود متابعة مفتوحة' : '$urgent open follow-ups',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );

    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CvRadius.ledger),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 420) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      figure,
                      const SizedBox(height: CvSpace.lg),
                      verdict,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: figure),
                    const SizedBox(width: CvSpace.xl),
                    Expanded(child: verdict),
                  ],
                );
              },
            ),
            const SizedBox(height: CvSpace.lg),
            _Bar(value: snap.dailyCompliance, color: c.approved, height: 4),
          ],
        ),
      ),
    );
  }
}

class _KpiCell {
  const _KpiCell({
    required this.label,
    required this.value,
    required this.detail,
    required this.progress,
    required this.tone,
  });

  final String label;
  final String value;
  final String detail;
  final double progress;
  final CvTone tone;
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.cells});

  final List<_KpiCell> cells;

  @override
  Widget build(BuildContext context) {
    final c = CheckViewColors.of(context);
    return Material(
      color: c.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CvRadius.ledger),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 720 ? 3 : 2;
          final rows = <List<_KpiCell>>[
            for (var i = 0; i < cells.length; i += columns)
              cells.sublist(i, (i + columns).clamp(0, cells.length)),
          ];
          return Column(
            children: [
              for (var r = 0; r < rows.length; r++) ...[
                if (r > 0) const Divider(),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < columns; i++) ...[
                        if (i > 0) Container(width: 1, color: c.hairline),
                        Expanded(
                          child: i < rows[r].length
                              ? _KpiTile(cell: rows[r][i])
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({required this.cell});

  final _KpiCell cell;

  @override
  Widget build(BuildContext context) {
    final c = CheckViewColors.of(context);
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.all(CvSpace.gutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              cell.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(color: c.inkMuted),
            ),
            const SizedBox(height: CvSpace.xs),
            Text(
              cell.value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w400,
                fontFeatures: cvTabular,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              cell.detail,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            if (cell.progress > 0) ...[
              const SizedBox(height: CvSpace.sm),
              _Bar(value: cell.progress, color: cvToneColor(c, cell.tone)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.color, this.height = 3});

  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: LinearProgressIndicator(
          value: value.clamp(0, 1).toDouble(),
          minHeight: height,
          color: color,
          backgroundColor: CheckViewColors.of(context).hairline,
        ),
      ),
    );
  }
}
