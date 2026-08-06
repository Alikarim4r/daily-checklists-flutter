import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:checklist_shared/checklist_shared.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/ops_dashboard_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ChecklistChrome.use(ChecklistBrand.viewer);
  await bootstrapSupabase();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const ViewerRoot(),
    ),
  );
}

class ViewerRoot extends ConsumerStatefulWidget {
  const ViewerRoot({super.key});

  @override
  ConsumerState<ViewerRoot> createState() => _ViewerRootState();
}

class _ViewerRootState extends ConsumerState<ViewerRoot> {
  String language = 'en';

  @override
  Widget build(BuildContext context) {
    final rtl = isRtlLanguage(language);
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: language == 'ar' ? 'فحص يومي — عرض' : 'Daily Checklists — Viewer',
      debugShowCheckedModeBanner: false,
      theme: ChecklistChrome.theme(),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: ChecklistChrome.accent,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: themeMode,
      builder: (context, child) => Directionality(
        textDirection: rtl ? ui.TextDirection.rtl : ui.TextDirection.ltr,
        child: child ?? const SizedBox.shrink(),
      ),
      home: ChecklistAuthGate(
        appTitle: language == 'ar' ? 'لوحة العرض والاعتماد' : 'Viewer & Review',
        subtitle: language == 'ar'
            ? 'عرض المعتمد • تعديل واعتماد حسب الصلاحية'
            : 'Approved view • Edit & approve by permission',
        allowedForProfile: (p) =>
            p.isPlatformOwner || p.role.canUseViewer,
        siteAccessRequirement: SiteAccessRequirement.read,
        homeBuilder: (context, profile) => ViewerHome(
          profile: profile,
          language: language,
          onLanguageChanged: (v) => setState(() => language = v),
        ),
      ),
    );
  }
}

class ViewerHome extends ConsumerStatefulWidget {
  const ViewerHome({
    super.key,
    required this.profile,
    required this.language,
    required this.onLanguageChanged,
  });

  final Profile profile;
  final String language;
  final ValueChanged<String> onLanguageChanged;

  @override
  ConsumerState<ViewerHome> createState() => _ViewerHomeState();
}

class _ViewerHomeState extends ConsumerState<ViewerHome> {
  List<ChecklistSite> sites = [];
  List<CampusChecklistGroup> campusGroups = [];
  List<UserSiteAccess> myAccess = [];
  List<Inspection> records = [];
  String? siteFilter;
  DateTime date = DateTime.now();
  Inspection? selected;
  Set<int> overdueIndexes = {};
  bool loading = true;
  String? message;
  /// 0=all visible, 1=pending review, 2=approved only (reviewers).
  int listMode = 0;
  Map<String, Set<int>> overdueByInspectionId = {};
  List<ChecklistNotice> notices = [];

  String get language => widget.language;

  String _siteFilterLabel(ChecklistSite s) {
    CampusChecklistGroup? group;
    for (final g in campusGroups) {
      if (g.checklists.any((c) => c.id == s.id)) {
        group = g;
        break;
      }
    }
    final campus = group?.campus?.nameFor(language);
    if (campus == null || campus.isEmpty) {
      return '${s.buildingCode} — ${s.nameFor(language)}';
    }
    return '$campus › ${s.buildingCode}';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _wide => MediaQuery.sizeOf(context).width >= 900;

  bool get _isReviewer => widget.profile.canReviewInspections;

  /// Regular viewers only see approved; editors also see submitted for review.
  List<ReviewStatus>? get _reviewFilter {
    if (_isReviewer) {
      if (listMode == 1) return [ReviewStatus.submitted];
      if (listMode == 2) return [ReviewStatus.approved];
      return [ReviewStatus.approved, ReviewStatus.submitted];
    }
    return [ReviewStatus.approved];
  }

  bool _canWriteSelected() {
    final insp = selected;
    if (insp == null) return false;
    if (widget.profile.isPlatformOwner ||
        widget.profile.role == UserRole.superAdmin) {
      return true;
    }
    return myAccess.any((a) => a.siteId == insp.siteId && a.canWrite);
  }

  bool _canManageSelected() {
    final insp = selected;
    if (insp == null) return false;
    if (widget.profile.isPlatformOwner ||
        widget.profile.role == UserRole.superAdmin) {
      return true;
    }
    return myAccess.any((a) => a.siteId == insp.siteId && a.canManage);
  }

  bool get _canEditSelected {
    final insp = selected;
    if (insp == null) return false;
    if (insp.reviewStatus == ReviewStatus.approved) return false;
    if (!insp.isSubmitted) return _canWriteSelected();
    // Submitted awaiting approve: site_admin / super can edit.
    return _isReviewer && _canManageSelected();
  }

  Future<void> _refreshOverdue(Inspection insp) async {
    final lookback = insp.items.isEmpty
        ? 14
        : insp.items
            .map((e) => e.overdueAfterDays)
            .fold<int>(14, (a, b) => math.max(a, b + 2));
    final history =
        await ref.read(inspectionRepositoryProvider).listRecentForSite(
              siteId: insp.siteId,
              asOfDate: insp.inspectionDate,
              lookbackDays: lookback,
            );
    final map = buildProblemHistory(history: history, current: insp);
    final overdue = overdueItemIndexes(
      inspection: insp,
      problemByDateIso: map,
    );
    if (mounted) setState(() => overdueIndexes = overdue);
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      message = null;
    });
    try {
      final siteRepo = ref.read(siteRepositoryProvider);
      final inspRepo = ref.read(inspectionRepositoryProvider);
      final groups =
          await siteRepo.listAccessibleCampusGroups(profile: widget.profile);
      final siteList = [
        for (final g in groups) ...g.checklists,
      ];
      final access = await siteRepo.listMySiteAccess();
      final list = await inspRepo.listInspections(
        siteId: siteFilter,
        date: date,
        reviewStatuses: _reviewFilter,
      );
      final overdueMap = <String, Set<int>>{};
      final withItems = <Inspection>[];
      for (final row in list) {
        try {
          final full = await inspRepo.getById(row.id);
          if (full == null) {
            withItems.add(row);
            continue;
          }
          withItems.add(full);
          final lookback = full.items.isEmpty
              ? 14
              : full.items
                  .map((e) => e.overdueAfterDays)
                  .fold<int>(14, (a, b) => math.max(a, b + 2));
          final history = await inspRepo.listRecentForSite(
            siteId: full.siteId,
            asOfDate: full.inspectionDate,
            lookbackDays: lookback,
          );
          final map = buildProblemHistory(history: history, current: full);
          final overdue = overdueItemIndexes(
            inspection: full,
            problemByDateIso: map,
          );
          if (overdue.isNotEmpty) overdueMap[full.id] = overdue;
        } catch (_) {
          withItems.add(row);
        }
      }
      final built = buildViewerNotices(
        records: withItems,
        overdueByInspectionId: overdueMap,
        canReview: _isReviewer,
        language: language,
      );
      setState(() {
        campusGroups = groups;
        sites = siteList;
        myAccess = access;
        records = withItems;
        overdueByInspectionId = overdueMap;
        notices = built;
        if (selected != null) {
          selected = withItems.where((r) => r.id == selected!.id).firstOrNull;
        }
      });
      if (selected != null) await _refreshOverdue(selected!);
    } catch (e) {
      setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _openOpsDashboard() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OpsDashboardScreen(
          profile: widget.profile,
          language: language,
          onOpenInspection: (id) async {
            if (mounted) Navigator.of(context).pop();
            final match = records.where((r) => r.id == id).firstOrNull;
            if (match != null) {
              await _open(match);
              return;
            }
            final full =
                await ref.read(inspectionRepositoryProvider).getById(id);
            if (full != null && mounted) await _open(full);
          },
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openNotices() async {
    await showChecklistNoticesSheet(
      context: context,
      notices: notices,
      language: language,
      onTap: (id) async {
        if (id == null) return;
        final match = records.where((r) => r.id == id).firstOrNull;
        if (match != null) {
          await _open(match);
          return;
        }
        final full = await ref.read(inspectionRepositoryProvider).getById(id);
        if (full != null && mounted) await _open(full);
      },
    );
  }

  Future<void> _exportSelected() async {
    final row = selected;
    if (row == null) return;
    try {
      setState(() => message = language == 'ar' ? 'جاري التصدير…' : 'Exporting…');
      final full = row.items.isEmpty
          ? await ref.read(inspectionRepositoryProvider).getById(row.id)
          : row;
      if (full == null) throw Exception('Inspection not found');
      final action = await _pickExportAction();
      if (action == null) {
        if (mounted) setState(() => message = null);
        return;
      }
      final exporter = const InspectionReportExporter();
      if (action == 'print') {
        await exporter.print(full, language: language);
      } else {
        await exporter.export(full, language: language);
      }
      if (mounted) {
        setState(() =>
            message = language == 'ar' ? 'تم تجهيز التقرير' : 'Report ready');
      }
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
    }
  }

  Future<String?> _pickExportAction() {
    final ar = language == 'ar';
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.ios_share_outlined),
              title: Text(ar ? 'حفظ / مشاركة PDF' : 'Save / Share PDF'),
              subtitle: Text(
                ar
                    ? 'الطريقة المضمونة — احفظ ثم اطبع من Preview'
                    : 'Reliable — save then print from Preview',
              ),
              onTap: () => Navigator.pop(context, 'share'),
            ),
            ListTile(
              leading: const Icon(Icons.print_outlined),
              title: Text(ar ? 'طباعة مباشرة' : 'Print directly'),
              onTap: () => Navigator.pop(context, 'print'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _open(Inspection row) async {
    final full = await ref.read(inspectionRepositoryProvider).getById(row.id);
    if (full == null) {
      setState(() => message = 'تعذر فتح السجل');
      return;
    }
    // Viewer role must not open non-approved (defense in depth).
    if (!_isReviewer && full.reviewStatus != ReviewStatus.approved) {
      setState(() => message = 'هذا الفحص غير معتمد للعرض بعد');
      return;
    }
    if (!_wide && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => InspectionFormPage(
            profile: widget.profile,
            language: language,
            initial: full,
            myAccess: myAccess,
            onChanged: () async {
              await _load();
            },
          ),
        ),
      );
      await _load();
      return;
    }
    setState(() => selected = full);
    await _refreshOverdue(full);
  }

  Future<bool> _checkPhotoPolicy(Inspection current) async {
    final orgId = current.organizationId;
    if (orgId.isEmpty) return true;
    final pol =
        await ref.read(policyRepositoryProvider).getOrCreate(orgId);
    final result = validateProblemPhotos(inspection: current, policy: pol);
    if (result.ok) return true;
    if (result.blocksSubmit) {
      setState(() => message = result.messageAr);
      return false;
    }
    if (result.severity == PolicySeverity.info) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.messageAr)),
        );
      }
      return true;
    }
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('صورة المشكلة ناقصة'),
        content: Text(result.messageAr),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إكمال الصور'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('متابعة'),
          ),
        ],
      ),
    );
    return proceed == true;
  }

  Future<void> _save() async {
    final current = selected;
    if (current == null || !_canEditSelected) return;
    try {
      await ref.read(inspectionRepositoryProvider).saveItems(current);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ التعديلات')),
        );
      }
      await _load();
    } catch (e) {
      setState(() => message = e.toString());
    }
  }

  Future<void> _submit() async {
    final current = selected;
    if (current == null || current.isSubmitted || !_canWriteSelected()) {
      return;
    }
    if (!await _checkPhotoPolicy(current)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إرسال التقرير'),
        content: const Text(
          'تأكيد إرسال سجل الفحص؟ سيُراجع قبل ظهوره للعارض.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إرسال'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(inspectionRepositoryProvider).saveItems(current);
      await ref.read(inspectionRepositoryProvider).submit(current.id);
      await _load();
      await _open(current);
    } catch (e) {
      setState(() => message = e.toString());
    }
  }

  Future<void> _approve() async {
    final current = selected;
    if (current == null ||
        !current.awaitingReview ||
        !_isReviewer ||
        !_canManageSelected()) {
      return;
    }
    try {
      await ref.read(inspectionRepositoryProvider).saveItems(current);
      await ref
          .read(inspectionRepositoryProvider)
          .approveInspection(current.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم اعتماد الفحص للعرض')),
        );
      }
      await _load();
      final full =
          await ref.read(inspectionRepositoryProvider).getById(current.id);
      if (full != null) {
        setState(() => selected = full);
        await _refreshOverdue(full);
      }
    } catch (e) {
      setState(() => message = e.toString());
    }
  }

  Future<void> _correctItem(InspectionItem item) async {
    if (selected == null || item.id == null || !_canManageSelected()) return;
    // Prefer direct edit while awaiting review; corrections log for approved.
    if (selected!.awaitingReview && _canEditSelected) {
      return;
    }
    final responseCtrl = TextEditingController(
      text: item.response?.dbValue ?? '',
    );
    final actionsCtrl = TextEditingController(text: item.actionsTaken);
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تصحيح بند ${item.itemIndex}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: responseCtrl,
              decoration: const InputDecoration(
                labelText: 'الإجابة (yes/no/na)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: actionsCtrl,
              decoration: const InputDecoration(
                labelText: 'الإجراءات',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'سبب التصحيح',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حفظ التصحيح'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final newResponse = ChecklistResponse.fromDb(responseCtrl.text.trim());
    try {
      await ref.read(correctionRepositoryProvider).correctItem(
            inspectionId: selected!.id,
            itemId: item.id!,
            fieldName: 'response+actions_taken',
            oldValue: '${item.response?.dbValue}|${item.actionsTaken}',
            newValue: '${newResponse?.dbValue}|${actionsCtrl.text}',
            reason: reasonCtrl.text,
            itemPatch: {
              'response': newResponse?.dbValue,
              'actions_taken': actionsCtrl.text,
            },
          );
      final full =
          await ref.read(inspectionRepositoryProvider).getById(selected!.id);
      if (full != null) {
        setState(() => selected = full);
        await _refreshOverdue(full);
      }
    } catch (e) {
      setState(() => message = e.toString());
    }
  }

  Widget _filtersBar({required bool showActions}) {
    final canEdit = _canEditSelected;
    final canApprove = selected != null &&
        selected!.awaitingReview &&
        _isReviewer &&
        _canManageSelected();
    final canSubmitDraft = selected != null &&
        !selected!.isSubmitted &&
        _canWriteSelected();
    return Material(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (_isReviewer)
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('الكل')),
                  ButtonSegment(value: 1, label: Text('بانتظار الاعتماد')),
                  ButtonSegment(value: 2, label: Text('معتمدة')),
                ],
                selected: {listMode},
                onSelectionChanged: (s) async {
                  setState(() => listMode = s.first);
                  await _load();
                },
              ),
            SizedBox(
              width: 300,
              child: DropdownButtonFormField<String?>(
                value: siteFilter,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: language == 'ar'
                      ? 'قوائم الفحص'
                      : 'Checklists',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(
                      language == 'ar'
                          ? 'كل القوائم داخل المواقع'
                          : 'All site checklists',
                    ),
                  ),
                  for (final s in sites)
                    DropdownMenuItem(
                      value: s.id,
                      child: Text(
                        _siteFilterLabel(s),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) async {
                  setState(() => siteFilter = v);
                  await _load();
                },
              ),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: DateTime(2024),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                );
                if (picked == null) return;
                setState(() => date = picked);
                await _load();
              },
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text(DateFormat('yyyy-MM-dd').format(date)),
            ),
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
            if (showActions && canEdit)
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: ViewerPalette.orange,
                ),
                onPressed: _save,
                child: const Text('حفظ'),
              ),
            if (showActions && canSubmitDraft)
              FilledButton(
                onPressed: _submit,
                child: const Text('إرسال التقرير'),
              ),
            if (showActions && canApprove)
              FilledButton.icon(
                onPressed: _approve,
                icon: const Icon(Icons.verified_outlined),
                label: const Text('اعتماد للعرض'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _recordsList() {
    if (records.isEmpty) {
      return const Center(child: Text('لا توجد سجلات فحص'));
    }
    return ListView.builder(
      itemCount: records.length,
      itemBuilder: (context, i) {
        final r = records[i];
        final selectedId = selected?.id == r.id;
        return ListTile(
          selected: selectedId,
          title: Text(r.buildingCode),
          subtitle: Text(
            '${r.inspectorName} • ${r.reviewStatus.labelAr}',
          ),
          trailing: const Icon(Icons.chevron_left),
          onTap: () => _open(r),
        );
      },
    );
  }

  Widget _formPane() {
    if (selected == null) {
      return const ColoredBox(
        color: Color(0xFFE5E7EB),
        child: Center(child: Text('اختر سجلًا لعرض النموذج على ورقة A4')),
      );
    }
    final canEdit = _canEditSelected;
    final canCorrectApproved = selected!.isApproved && _canManageSelected();
    return A4PaperSheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChecklistFormLayout(
            inspection: selected!,
            language: language,
            forceTableLayout: true,
            readOnly: !canEdit,
            overdueItemIndexes: overdueIndexes,
            onInspectorChanged: (v) =>
                setState(() => selected!.inspectorName = v),
            onTimeChanged: (v) =>
                setState(() => selected!.inspectionTime = v),
            onFloorChanged: (v) => setState(() => selected!.floorLabel = v),
            onResponseChanged: (item, value) =>
                setState(() => item.response = value),
            onActionsChanged: (item, value) =>
                setState(() => item.actionsTaken = value),
          ),
          if (canCorrectApproved) ...[
            const SizedBox(height: 16),
            const Divider(),
            const Text(
              'تصحيح بعد الاعتماد (صلاحية إدارة الموقع)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            for (final item in selected!.items)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${item.itemIndex}. ${item.description}'),
                trailing: IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => _correctItem(item),
                ),
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      endDrawer: ChecklistSettingsDrawer(
        profile: widget.profile,
        language: language,
        onLanguageChanged: widget.onLanguageChanged,
        languages: const ['en', 'ar'],
        appIconAsset: 'assets/branding/app_icon_simple.png',
      ),
      appBar: checklistGradientAppBar(
        title: language == 'ar'
            ? 'MOEHE — عرض الفحص'
            : 'MOEHE — Inspection Viewer',
        actions: [
          IconButton(
            tooltip: language == 'ar' ? 'المتابعة والإشراف' : 'Ops & Supervision',
            onPressed: _openOpsDashboard,
            icon: const Icon(Icons.analytics_outlined),
          ),
          ChecklistNoticeBell(
            notices: notices,
            onOpen: _openNotices,
          ),
          if (selected != null)
            IconButton(
              tooltip: language == 'ar' ? 'تصدير PDF' : 'Export PDF',
              onPressed: _exportSelected,
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
          IconButton(
            tooltip: language == 'ar' ? 'تحديث' : 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
          Builder(
            builder: (ctx) => IconButton(
              tooltip: language == 'ar' ? 'الإعدادات' : 'Settings',
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
              icon: const Icon(Icons.settings_outlined),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _filtersBar(showActions: _wide),
          if (message != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(message!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : _wide
                    ? Row(
                        children: [
                          SizedBox(width: 300, child: _recordsList()),
                          const VerticalDivider(width: 1),
                          Expanded(child: _formPane()),
                        ],
                      )
                    : _recordsList(),
          ),
        ],
      ),
    );
  }
}

/// Full-screen PDF-style form for phones.
class InspectionFormPage extends ConsumerStatefulWidget {
  const InspectionFormPage({
    super.key,
    required this.profile,
    required this.language,
    required this.initial,
    required this.myAccess,
    required this.onChanged,
  });

  final Profile profile;
  final String language;
  final Inspection initial;
  final List<UserSiteAccess> myAccess;
  final Future<void> Function() onChanged;

  @override
  ConsumerState<InspectionFormPage> createState() => _InspectionFormPageState();
}

class _InspectionFormPageState extends ConsumerState<InspectionFormPage> {
  late Inspection inspection;
  Set<int> overdueIndexes = {};
  String? message;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    inspection = widget.initial;
    _loadOverdue();
  }

  bool get _isReviewer => widget.profile.canReviewInspections;

  bool get _canWrite {
    if (widget.profile.isPlatformOwner ||
        widget.profile.role == UserRole.superAdmin) {
      return true;
    }
    return widget.myAccess
        .any((a) => a.siteId == inspection.siteId && a.canWrite);
  }

  bool get _canManage {
    if (widget.profile.isPlatformOwner ||
        widget.profile.role == UserRole.superAdmin) {
      return true;
    }
    return widget.myAccess
        .any((a) => a.siteId == inspection.siteId && a.canManage);
  }

  bool get _canEdit {
    if (inspection.reviewStatus == ReviewStatus.approved) return false;
    if (!inspection.isSubmitted) return _canWrite;
    return _isReviewer && _canManage;
  }

  Future<void> _loadOverdue() async {
    final lookback = inspection.items
        .map((e) => e.overdueAfterDays)
        .fold<int>(14, (a, b) => math.max(a, b + 2));
    final history =
        await ref.read(inspectionRepositoryProvider).listRecentForSite(
              siteId: inspection.siteId,
              asOfDate: inspection.inspectionDate,
              lookbackDays: lookback,
            );
    final map = buildProblemHistory(history: history, current: inspection);
    final overdue = overdueItemIndexes(
      inspection: inspection,
      problemByDateIso: map,
    );
    if (mounted) setState(() => overdueIndexes = overdue);
  }

  Future<bool> _checkPhotoPolicy() async {
    final orgId = inspection.organizationId;
    if (orgId.isEmpty) return true;
    final pol =
        await ref.read(policyRepositoryProvider).getOrCreate(orgId);
    final result =
        validateProblemPhotos(inspection: inspection, policy: pol);
    if (result.ok) return true;
    if (result.blocksSubmit) {
      setState(() => message = result.messageAr);
      return false;
    }
    if (result.severity == PolicySeverity.info) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.messageAr)),
        );
      }
      return true;
    }
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('صورة المشكلة ناقصة'),
        content: Text(result.messageAr),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إكمال الصور'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('متابعة'),
          ),
        ],
      ),
    );
    return proceed == true;
  }

  Future<void> _save() async {
    if (!_canEdit) return;
    setState(() => saving = true);
    try {
      await ref.read(inspectionRepositoryProvider).saveItems(inspection);
      await widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم الحفظ')),
        );
      }
    } catch (e) {
      setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _submit() async {
    if (inspection.isSubmitted || !_canWrite) return;
    if (!await _checkPhotoPolicy()) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إرسال التقرير'),
        content: const Text('تأكيد إرسال سجل الفحص؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إرسال'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => saving = true);
    try {
      await ref.read(inspectionRepositoryProvider).saveItems(inspection);
      await ref.read(inspectionRepositoryProvider).submit(inspection.id);
      final full =
          await ref.read(inspectionRepositoryProvider).getById(inspection.id);
      if (full != null) setState(() => inspection = full);
      await widget.onChanged();
    } catch (e) {
      setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _approve() async {
    if (!inspection.awaitingReview || !_isReviewer || !_canManage) return;
    setState(() => saving = true);
    try {
      await ref.read(inspectionRepositoryProvider).saveItems(inspection);
      await ref
          .read(inspectionRepositoryProvider)
          .approveInspection(inspection.id);
      final full =
          await ref.read(inspectionRepositoryProvider).getById(inspection.id);
      if (full != null) setState(() => inspection = full);
      await widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم الاعتماد')),
        );
      }
    } catch (e) {
      setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _correctItem(InspectionItem item) async {
    if (item.id == null || !_canManage || !inspection.isApproved) return;
    final responseCtrl =
        TextEditingController(text: item.response?.dbValue ?? '');
    final actionsCtrl = TextEditingController(text: item.actionsTaken);
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تصحيح بند ${item.itemIndex}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: responseCtrl,
              decoration: const InputDecoration(
                labelText: 'الإجابة (yes/no/na)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: actionsCtrl,
              decoration: const InputDecoration(
                labelText: 'الإجراءات',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'سبب التصحيح',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final newResponse = ChecklistResponse.fromDb(responseCtrl.text.trim());
    await ref.read(correctionRepositoryProvider).correctItem(
          inspectionId: inspection.id,
          itemId: item.id!,
          fieldName: 'response+actions_taken',
          oldValue: '${item.response?.dbValue}|${item.actionsTaken}',
          newValue: '${newResponse?.dbValue}|${actionsCtrl.text}',
          reason: reasonCtrl.text,
          itemPatch: {
            'response': newResponse?.dbValue,
            'actions_taken': actionsCtrl.text,
          },
        );
    final full =
        await ref.read(inspectionRepositoryProvider).getById(inspection.id);
    if (full != null) setState(() => inspection = full);
    await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = _canEdit;
    final canCorrect = inspection.isApproved && _canManage;
    final canApprove =
        inspection.awaitingReview && _isReviewer && _canManage;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: Text('${inspection.buildingCode} — ${inspection.dateIso}'),
        actions: [
          IconButton(
            tooltip: widget.language == 'ar' ? 'تصدير PDF' : 'Export PDF',
            onPressed: saving
                ? null
                : () async {
                    final ar = widget.language == 'ar';
                    final action = await showModalBottomSheet<String>(
                      context: context,
                      showDragHandle: true,
                      builder: (context) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.ios_share_outlined),
                              title: Text(
                                ar ? 'حفظ / مشاركة PDF' : 'Save / Share PDF',
                              ),
                              onTap: () => Navigator.pop(context, 'share'),
                            ),
                            ListTile(
                              leading: const Icon(Icons.print_outlined),
                              title: Text(
                                ar ? 'طباعة مباشرة' : 'Print directly',
                              ),
                              onTap: () => Navigator.pop(context, 'print'),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    );
                    if (action == null || !mounted) return;
                    try {
                      final exporter = const InspectionReportExporter();
                      if (action == 'print') {
                        await exporter.print(
                          inspection,
                          language: widget.language,
                        );
                      } else {
                        await exporter.export(
                          inspection,
                          language: widget.language,
                        );
                      }
                    } catch (e) {
                      if (mounted) setState(() => message = '$e');
                    }
                  },
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
          if (canEdit)
            TextButton(
              onPressed: saving ? null : _save,
              child: const Text('حفظ', style: TextStyle(color: Colors.white)),
            ),
          if (!inspection.isSubmitted && _canWrite)
            TextButton(
              onPressed: saving ? null : _submit,
              child: const Text('إرسال', style: TextStyle(color: Colors.white)),
            ),
          if (canApprove)
            TextButton(
              onPressed: saving ? null : _approve,
              child:
                  const Text('اعتماد', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: Column(
        children: [
          if (message != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(message!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: A4PaperSheet(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ChecklistFormLayout(
                    inspection: inspection,
                    language: widget.language,
                    forceTableLayout: true,
                    readOnly: !canEdit,
                    overdueItemIndexes: overdueIndexes,
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
                  if (canCorrect) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const Text(
                      'تصحيح بعد الاعتماد',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    for (final item in inspection.items)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${item.itemIndex}. ${item.description}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _correctItem(item),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
