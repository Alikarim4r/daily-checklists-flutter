import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/checkadmin_errors.dart';
import '../design/checkadmin_tokens.dart';
import '../design/checkadmin_widgets.dart';

/// Submitted inspections awaiting administrative review.
class ReviewsTab extends ConsumerStatefulWidget {
  const ReviewsTab({super.key, required this.profile, required this.language});

  final Profile profile;
  final String language;

  @override
  ConsumerState<ReviewsTab> createState() => _ReviewsTabState();
}

class _ReviewsTabState extends ConsumerState<ReviewsTab> {
  List<Inspection> rows = [];
  bool loading = true;
  String? message;

  bool get ar => widget.language == 'ar';
  String _t(String en, String arText) => ar ? arText : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      message = null;
    });
    try {
      final list = await ref
          .read(inspectionRepositoryProvider)
          .listPendingReview();
      if (mounted) setState(() => rows = list);
    } catch (e) {
      if (mounted) {
        setState(() => message = checkAdminUserMessage(e, widget.language));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _open(Inspection inspection) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => _ReviewEditScreen(
          profile: widget.profile,
          inspection: inspection,
          language: widget.language,
        ),
      ),
    );
    if (updated == true) await _load();
  }

  String _dateGroupLabel(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    const enMonths = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    const arMonths = [
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];
    return ar
        ? '${d.day} ${arMonths[d.month - 1]} ${d.year}'
        : '${d.day.toString().padLeft(2, '0')} ${enMonths[d.month - 1]} ${d.year}';
  }

  double _codeSlotWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 340) return 48;
    if (width < 390) return 52;
    return 56;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<Inspection>>{};
    for (final row in rows) {
      grouped.putIfAbsent(row.dateIso, () => <Inspection>[]).add(row);
    }
    final c = CheckAdminColors.of(context);
    final codeWidth = _codeSlotWidth(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (message != null)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              CaSpace.gutter,
              CaSpace.sm,
              CaSpace.gutter,
              0,
            ),
            child: CaInlineNotice(
              message: message!,
              tone: CaTone.danger,
              onDismiss: () => setState(() => message = null),
            ),
          ),
        CaSectionLabel(
          title: _t('Awaiting review', 'بانتظار الاعتماد'),
          count: rows.length,
          trailing: IconButton(
            tooltip: _t('Refresh', 'تحديث'),
            onPressed: loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        Expanded(
          child: loading && rows.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(CaSpace.gutter),
                  child: CaSkeletonList(rows: 7),
                )
              : rows.isEmpty
              ? CaEmptyState(
                  icon: Icons.task_alt_rounded,
                  title: _t(
                    'Review queue is clear',
                    'لا توجد فحوصات بانتظار الاعتماد',
                  ),
                  message: _t(
                    'New submitted inspections will appear here automatically.',
                    'ستظهر الفحوصات المرسلة الجديدة هنا تلقائيًا.',
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.viewPaddingOf(context).bottom + 16,
                    ),
                    children: [
                      for (final entry in grouped.entries) ...[
                        Container(
                          constraints: const BoxConstraints(minHeight: 28),
                          alignment: AlignmentDirectional.centerStart,
                          padding: const EdgeInsetsDirectional.fromSTEB(
                            CaSpace.gutter,
                            4,
                            CaSpace.gutter,
                            4,
                          ),
                          color: c.canvas,
                          child: Text(
                            '${_dateGroupLabel(entry.key)} · ${entry.value.length}',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: c.inkMuted,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: ar ? 0 : .6,
                                ),
                          ),
                        ),
                        CaLedger(
                          children: [
                            for (final r in entry.value)
                              CaCommandRow(
                                minHeight: 64,
                                leading: CaCodeBadge(
                                  code: r.buildingCode,
                                  width: codeWidth,
                                ),
                                title: ar && r.siteNameAr.isNotEmpty
                                    ? r.siteNameAr
                                    : (r.siteNameEn.isNotEmpty
                                          ? r.siteNameEn
                                          : r.buildingCode),
                                subtitle: _t(
                                  '${r.inspectorName.isEmpty ? 'Inspector not set' : r.inspectorName} · ${r.items.length} items',
                                  '${r.inspectorName.isEmpty ? 'لم يحدد المفتش' : r.inspectorName} · ${r.items.length} بند',
                                ),
                                onTap: () => _open(r),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _ReviewEditScreen extends ConsumerStatefulWidget {
  const _ReviewEditScreen({
    required this.profile,
    required this.inspection,
    required this.language,
  });

  final Profile profile;
  final Inspection inspection;
  final String language;

  @override
  ConsumerState<_ReviewEditScreen> createState() => _ReviewEditScreenState();
}

class _ReviewEditScreenState extends ConsumerState<_ReviewEditScreen> {
  late Inspection inspection;
  bool saving = false;
  String? message;

  bool get ar => widget.language == 'ar';
  String _t(String en, String arText) => ar ? arText : en;

  @override
  void initState() {
    super.initState();
    inspection = widget.inspection;
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      await ref.read(inspectionRepositoryProvider).saveItems(inspection);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t('Changes saved', 'تم حفظ التعديلات'))),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => message = checkAdminUserMessage(e, widget.language));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _approve() async {
    setState(() => saving = true);
    try {
      await ref.read(inspectionRepositoryProvider).saveItems(inspection);
      await ref
          .read(inspectionRepositoryProvider)
          .approveInspection(inspection);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => message = checkAdminUserMessage(e, widget.language));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${inspection.buildingCode} — ${inspection.dateIso}'),
        actions: [
          TextButton(
            onPressed: saving ? null : _save,
            child: Text(_t('Save', 'حفظ')),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: FilledButton.icon(
              onPressed: saving ? null : _approve,
              icon: const Icon(Icons.verified_outlined, size: 18),
              label: Text(_t('Approve', 'اعتماد')),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (message != null)
            Padding(
              padding: const EdgeInsets.all(CaSpace.gutter),
              child: CaInlineNotice(
                message: message!,
                tone: CaTone.danger,
                onDismiss: () => setState(() => message = null),
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(CaSpace.gutter),
              child: CaPageWidth(
                maxWidth: 1200,
                child: ChecklistFormLayout(
                  inspection: inspection,
                  language: widget.language,
                  forceTableLayout: MediaQuery.sizeOf(context).width >= 800,
                  onInspectorChanged: (v) =>
                      setState(() => inspection.inspectorName = v),
                  onTimeChanged: (v) =>
                      setState(() => inspection.inspectionTime = v),
                  onFloorChanged: (v) =>
                      setState(() => inspection.floorLabel = v),
                  onResponseChanged: (item, value) =>
                      setState(() => item.response = value),
                  onActionsChanged: (item, value) =>
                      setState(() => item.actionsTaken = value),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
