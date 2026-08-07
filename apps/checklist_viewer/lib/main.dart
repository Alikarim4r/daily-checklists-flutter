import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:checklist_shared/checklist_shared.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
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
        sessionSecurityAppKeyProvider.overrideWithValue('viewer'),
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
      darkTheme: ChecklistChrome.darkTheme(),
      themeMode: themeMode,
      builder: (context, child) => Directionality(
        textDirection: rtl ? ui.TextDirection.rtl : ui.TextDirection.ltr,
        child: ChecklistAppBackground(
          child: child ?? const SizedBox.shrink(),
        ),
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
          onLanguageChanged: (v) => setState(() {
            language = viewerLanguages.contains(v) ? v : 'en';
          }),
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
  /// Mobile/tablet drill-down into a campus before choosing a checklist.
  CampusChecklistGroup? browseCampus;
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

  bool get _canNavBack => browseCampus != null || siteFilter != null;

  String get _appBarTitle {
    if (browseCampus != null && siteFilter == null) {
      return browseCampus!.titleFor(language);
    }
    if (siteFilter != null) {
      final site = sites.where((s) => s.id == siteFilter).firstOrNull;
      if (site != null) return site.buildingCode;
    }
    return language == 'ar'
        ? 'MOEHE — عرض الفحص'
        : 'MOEHE — Inspection Viewer';
  }

  void _navBack() {
    if (siteFilter != null && browseCampus != null) {
      setState(() {
        siteFilter = null;
        selected = null;
      });
      _load();
      return;
    }
    if (siteFilter != null && browseCampus == null) {
      setState(() {
        siteFilter = null;
        selected = null;
      });
      _load();
      return;
    }
    if (browseCampus != null) {
      setState(() {
        browseCampus = null;
        siteFilter = null;
        selected = null;
      });
      _load();
    }
  }

  Future<void> _openCampus(CampusChecklistGroup group) async {
    if (group.checklists.length == 1 && group.campus == null) {
      setState(() {
        browseCampus = null;
        siteFilter = group.checklists.first.id;
        selected = null;
      });
      await _load();
      return;
    }
    setState(() {
      browseCampus = group;
      siteFilter = null;
      selected = null;
    });
    await _load();
  }

  Future<void> _openChecklist(ChecklistSite site) async {
    setState(() {
      siteFilter = site.id;
      selected = null;
    });
    await _load();
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
    // Managers may edit awaiting-review and approved forms on the paper itself.
    if (_canManageSelected()) return true;
    if (insp.reviewStatus == ReviewStatus.approved) return false;
    if (!insp.isSubmitted) return _canWriteSelected();
    return false;
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
      // Parallel hydrate — skip per-record overdue history (done on open).
      final withItems = await Future.wait([
        for (final row in list)
          () async {
            try {
              return await inspRepo.getById(row.id) ?? row;
            } catch (_) {
              return row;
            }
          }(),
      ]);
      final overdueMap = <String, Set<int>>{};
      if (selected != null &&
          overdueByInspectionId.containsKey(selected!.id)) {
        overdueMap[selected!.id] = overdueByInspectionId[selected!.id]!;
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
      setState(() => message = language == 'ar' ? 'تعذر فتح السجل' : 'Could not open record');
      return;
    }
    // Viewer role must not open non-approved (defense in depth).
    if (!_isReviewer && full.reviewStatus != ReviewStatus.approved) {
      setState(() => message = language == 'ar' ? 'هذا الفحص غير معتمد للعرض بعد' : 'This inspection is not approved for viewing yet');
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
      setState(() => message = result.messageFor(language));
      return false;
    }
    if (result.severity == PolicySeverity.info) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.messageFor(language))),
        );
      }
      return true;
    }
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(language == 'ar' ? 'صورة المشكلة ناقصة' : 'Issue photo missing'),
        content: Text(result.messageFor(language)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(language == 'ar' ? 'إكمال الصور' : 'Add photos'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(language == 'ar' ? 'متابعة' : 'Continue'),
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
          SnackBar(content: Text(language == 'ar' ? 'تم حفظ التعديلات' : 'Changes saved')),
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
        title: Text(language == 'ar' ? 'إرسال التقرير' : 'Submit report'),
        content: Text(
          language == 'ar'
              ? 'تأكيد إرسال سجل الفحص؟ سيُراجع قبل ظهوره للعارض.'
              : 'Submit this inspection for review?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(language == 'ar' ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(language == 'ar' ? 'إرسال' : 'Submit'),
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
          SnackBar(content: Text(language == 'ar' ? 'تم اعتماد الفحص للعرض' : 'Inspection approved for viewing')),
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
      color: Theme.of(context).brightness == Brightness.dark
          ? ChecklistChrome.darkSurface
          : Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (_isReviewer)
              SegmentedButton<int>(
                segments: [
                  ButtonSegment(value: 0, label: Text(language == 'ar' ? 'الكل' : 'All')),
                  ButtonSegment(value: 1, label: Text(language == 'ar' ? 'بانتظار الاعتماد' : 'Pending')),
                  ButtonSegment(value: 2, label: Text(language == 'ar' ? 'معتمدة' : 'Approved')),
                ],
                selected: {listMode},
                onSelectionChanged: (s) async {
                  setState(() => listMode = s.first);
                  await _load();
                },
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
                child: Text(language == 'ar' ? 'حفظ' : 'Save'),
              ),
            if (showActions && canSubmitDraft)
              FilledButton(
                onPressed: _submit,
                child: Text(language == 'ar' ? 'إرسال التقرير' : 'Submit report'),
              ),
            if (showActions && canApprove)
              FilledButton.icon(
                onPressed: _approve,
                icon: const Icon(Icons.verified_outlined),
                label: Text(language == 'ar' ? 'اعتماد للعرض' : 'Approve for view'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _campusGroupsList() {
    if (campusGroups.isEmpty) {
      return Center(
        child: Text(
          language == 'ar' ? 'لا توجد مواقع' : 'No sites',
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: campusGroups.length,
      itemBuilder: (context, i) {
        final group = campusGroups[i];
        return ChecklistBrandCard(
          onTap: () => _openCampus(group),
          child: Row(
            children: [
              ChecklistIconWell(
                icon: group.campus != null
                    ? Icons.account_balance_rounded
                    : Icons.apartment_rounded,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.titleFor(language),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: ChecklistChrome.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      language == 'ar'
                          ? '${group.checklists.length} قوائم فحص'
                          : '${group.checklists.length} checklists',
                      style: TextStyle(
                        color: ChecklistChrome.inkMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: ChecklistChrome.accent),
            ],
          ),
        );
      },
    );
  }

  Widget _campusChecklistsList(CampusChecklistGroup group) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: group.checklists.length,
      itemBuilder: (context, i) {
        final site = group.checklists[i];
        return ChecklistBrandCard(
          onTap: () => _openChecklist(site),
          child: Row(
            children: [
              ChecklistIconWell(icon: Icons.checklist_rtl_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      site.nameFor(language),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: ChecklistChrome.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${site.buildingCode} · ${site.checklistType}',
                      style: TextStyle(
                        color: ChecklistChrome.inkMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: ChecklistChrome.accent),
            ],
          ),
        );
      },
    );
  }

  Widget _mobileBrowseBody() {
    if (browseCampus == null && siteFilter == null) {
      return _campusGroupsList();
    }
    if (browseCampus != null && siteFilter == null) {
      return _campusChecklistsList(browseCampus!);
    }
    return _recordsList();
  }

  Widget _recordsList() {
    if (records.isEmpty) {
      return Center(
        child: Text(
          language == 'ar' ? 'لا توجد سجلات فحص' : 'No inspection records',
        ),
      );
    }
    return ListView.builder(
      itemCount: records.length,
      itemBuilder: (context, i) {
        final r = records[i];
        final selectedId = selected?.id == r.id;
        return ListTile(
          key: ValueKey(r.id),
          selected: selectedId,
          title: Text(r.buildingCode),
          subtitle: Text(
            '${r.inspectorName} • ${r.reviewStatus.labelFor(language)}',
          ),
          trailing: const Icon(Icons.chevron_left),
          onTap: () => _open(r),
        );
      },
    );
  }

  Future<void> _pickPhoto(InspectionItem item, {required bool isIssue}) async {
    final current = selected;
    if (current == null || !_canEditSelected) return;
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 1600,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final siteName = language == 'ar' && current.siteNameAr.isNotEmpty
          ? current.siteNameAr
          : (current.siteNameEn.isNotEmpty
              ? current.siteNameEn
              : current.buildingCode);
      final stamped = await InspectionPhotoWatermark().apply(
        imageBytes: bytes,
        context: InspectionPhotoContext(
          siteName: siteName,
          buildingCode: current.buildingCode,
          inspectionDateIso: current.dateIso,
          inspectionTime: current.inspectionTime,
          itemIndex: item.itemIndex,
          itemDescription: item.descriptionFor(language),
          inspectorName: current.inspectorName,
          kindLabel: isIssue
              ? (language == 'ar' ? 'مشكلة' : 'Issue')
              : (language == 'ar' ? 'إصلاح' : 'Repair'),
          sourceLabel: 'Gallery',
        ),
      );
      final orgId = current.organizationId;
      final kind = isIssue ? 'issue' : 'fix';
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final path = await ref.read(inspectionRepositoryProvider).uploadBytes(
            organizationId: orgId,
            siteId: current.siteId,
            inspectionId: current.id,
            fileName: '${item.itemIndex}_${kind}_$stamp.jpg',
            bytes: stamped,
          );
      setState(() {
        if (isIssue) {
          item.appendIssueImage(path);
        } else {
          item.appendFixImage(path);
        }
      });
      await ref.read(inspectionRepositoryProvider).saveItems(current);
    } catch (e) {
      if (mounted) setState(() => message = '$e');
    }
  }

  Future<void> _clearPhoto(
    InspectionItem item,
    String path, {
    required bool isIssue,
  }) async {
    final current = selected;
    if (current == null || !_canEditSelected) return;
    setState(() {
      if (isIssue) {
        item.removeIssueImage(path);
      } else {
        item.removeFixImage(path);
      }
    });
    await ref.read(inspectionRepositoryProvider).saveItems(current);
  }

  Future<void> _deleteCustomItem(InspectionItem item) async {
    final current = selected;
    if (current == null || !_canEditSelected || !item.isCustom) return;
    final ar = language == 'ar';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ar ? 'حذف البند؟' : 'Delete item?'),
        content: Text(
          ar
              ? 'سيتم حذف البند المخصص رقم ${item.itemIndex}.'
              : 'Custom item #${item.itemIndex} will be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ar ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ar ? 'حذف' : 'Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      if (item.id != null) {
        await ref
            .read(inspectionRepositoryProvider)
            .deleteInspectionItem(item.id!);
      }
      setState(() {
        current.items.removeWhere(
          (i) =>
              identical(i, item) ||
              (item.id != null && i.id == item.id) ||
              (i.isCustom &&
                  i.itemIndex == item.itemIndex &&
                  i.description == item.description),
        );
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ar ? 'تم حذف البند' : 'Item deleted'),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => message = '$e');
    }
  }

  Future<void> _addCustomItem() async {
    final current = selected;
    if (current == null || !_canEditSelected) return;
    final en = TextEditingController();
    final ar = TextEditingController();
    var def = 'Y';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(language == 'ar' ? 'إضافة بند' : 'Add item'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: en,
                decoration: InputDecoration(
                  labelText: language == 'ar' ? 'الوصف (EN)' : 'Description (EN)',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ar,
                decoration: InputDecoration(
                  labelText: language == 'ar' ? 'الوصف (AR)' : 'Description (AR)',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: def,
                decoration: InputDecoration(
                  labelText: language == 'ar' ? 'الإجابة المثالية' : 'Ideal answer',
                  border: const OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'Y', child: Text('Yes / نعم')),
                  DropdownMenuItem(value: 'N', child: Text('No / لا')),
                ],
                onChanged: (v) => setLocal(() => def = v ?? 'Y'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(language == 'ar' ? 'إلغاء' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(language == 'ar' ? 'إضافة' : 'Add'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final desc = en.text.trim().isNotEmpty ? en.text.trim() : ar.text.trim();
    if (desc.isEmpty) return;
    final nextIndex = current.items.isEmpty
        ? 1
        : current.items.map((e) => e.itemIndex).reduce(math.max) + 1;
    final item = InspectionItem(
      itemIndex: nextIndex,
      description: en.text.trim().isNotEmpty ? en.text.trim() : desc,
      descriptionAr: ar.text.trim().isEmpty ? null : ar.text.trim(),
      defaultAnswer: def,
      isCustom: true,
    );
    setState(() => current.items.add(item));
    await ref.read(inspectionRepositoryProvider).saveItems(current);
    final full =
        await ref.read(inspectionRepositoryProvider).getById(current.id);
    if (full != null && mounted) {
      setState(() => selected = full);
      await _refreshOverdue(full);
    }
  }

  Widget _formPane() {
    if (selected == null) {
      return ColoredBox(
        color: const Color(0x00E5E7EB),
        child: Center(
          child: Text(
            language == 'ar'
                ? 'اختر سجلًا لعرض النموذج على ورقة A4'
                : 'Select a record to view the A4 form',
          ),
        ),
      );
    }
    final canEdit = _canEditSelected;
    return A4PaperSheet(
      child: ChecklistFormLayout(
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
        onPickIssuePhoto: canEdit
            ? (item) => _pickPhoto(item, isIssue: true)
            : null,
        onPickFixPhoto: canEdit
            ? (item) => _pickPhoto(item, isIssue: false)
            : null,
        onClearIssuePhoto: canEdit
            ? (item, path) => _clearPhoto(item, path, isIssue: true)
            : null,
        onClearFixPhoto: canEdit
            ? (item, path) => _clearPhoto(item, path, isIssue: false)
            : null,
        onAddItem: canEdit ? _addCustomItem : null,
        onDeleteItem: canEdit ? _deleteCustomItem : null,
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
        languages: viewerLanguages,
        appIconAsset: 'assets/branding/app_icon_simple.png',
      ),
      appBar: checklistGradientAppBar(
        title: _appBarTitle,
        leading: _canNavBack
            ? checklistBackButton(context, onPressed: _navBack)
            : null,
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
                          SizedBox(width: 320, child: _mobileBrowseBody()),
                          const VerticalDivider(width: 1),
                          Expanded(child: _formPane()),
                        ],
                      )
                    : _mobileBrowseBody(),
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
    if (_canManage) return true;
    if (inspection.reviewStatus == ReviewStatus.approved) return false;
    if (!inspection.isSubmitted) return _canWrite;
    return false;
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
      setState(() => message = result.messageFor(widget.language));
      return false;
    }
    if (result.severity == PolicySeverity.info) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.messageFor(widget.language))),
        );
      }
      return true;
    }
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.language == 'ar' ? 'صورة المشكلة ناقصة' : 'Issue photo missing'),
        content: Text(result.messageFor(widget.language)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.language == 'ar' ? 'إكمال الصور' : 'Add photos'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.language == 'ar' ? 'متابعة' : 'Continue'),
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
          SnackBar(content: Text(widget.language == 'ar' ? 'تم الحفظ' : 'Saved')),
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
        title: Text(widget.language == 'ar' ? 'إرسال التقرير' : 'Submit report'),
        content: Text(widget.language == 'ar' ? 'تأكيد إرسال سجل الفحص؟' : 'Submit this inspection?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.language == 'ar' ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.language == 'ar' ? 'إرسال' : 'Submit'),
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
          SnackBar(content: Text(widget.language == 'ar' ? 'تم الاعتماد' : 'Approved')),
        );
      }
    } catch (e) {
      setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _pickPhoto(InspectionItem item, {required bool isIssue}) async {
    if (!_canEdit) return;
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 1600,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final lang = widget.language;
      final siteName = lang == 'ar' && inspection.siteNameAr.isNotEmpty
          ? inspection.siteNameAr
          : (inspection.siteNameEn.isNotEmpty
              ? inspection.siteNameEn
              : inspection.buildingCode);
      final stamped = await InspectionPhotoWatermark().apply(
        imageBytes: bytes,
        context: InspectionPhotoContext(
          siteName: siteName,
          buildingCode: inspection.buildingCode,
          inspectionDateIso: inspection.dateIso,
          inspectionTime: inspection.inspectionTime,
          itemIndex: item.itemIndex,
          itemDescription: item.descriptionFor(lang),
          inspectorName: inspection.inspectorName,
          kindLabel: isIssue
              ? (lang == 'ar' ? 'مشكلة' : 'Issue')
              : (lang == 'ar' ? 'إصلاح' : 'Repair'),
          sourceLabel: 'Gallery',
        ),
      );
      final kind = isIssue ? 'issue' : 'fix';
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final path = await ref.read(inspectionRepositoryProvider).uploadBytes(
            organizationId: inspection.organizationId,
            siteId: inspection.siteId,
            inspectionId: inspection.id,
            fileName: '${item.itemIndex}_${kind}_$stamp.jpg',
            bytes: stamped,
          );
      setState(() {
        if (isIssue) {
          item.appendIssueImage(path);
        } else {
          item.appendFixImage(path);
        }
      });
      await ref.read(inspectionRepositoryProvider).saveItems(inspection);
    } catch (e) {
      if (mounted) setState(() => message = '$e');
    }
  }

  Future<void> _clearPhoto(
    InspectionItem item,
    String path, {
    required bool isIssue,
  }) async {
    if (!_canEdit) return;
    setState(() {
      if (isIssue) {
        item.removeIssueImage(path);
      } else {
        item.removeFixImage(path);
      }
    });
    await ref.read(inspectionRepositoryProvider).saveItems(inspection);
  }

  Future<void> _deleteCustomItem(InspectionItem item) async {
    if (!_canEdit || !item.isCustom) return;
    final ar = widget.language == 'ar';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ar ? 'حذف البند؟' : 'Delete item?'),
        content: Text(
          ar
              ? 'سيتم حذف البند المخصص رقم ${item.itemIndex}.'
              : 'Custom item #${item.itemIndex} will be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ar ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ar ? 'حذف' : 'Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      if (item.id != null) {
        await ref
            .read(inspectionRepositoryProvider)
            .deleteInspectionItem(item.id!);
      }
      setState(() {
        inspection.items.removeWhere(
          (i) =>
              identical(i, item) ||
              (item.id != null && i.id == item.id) ||
              (i.isCustom &&
                  i.itemIndex == item.itemIndex &&
                  i.description == item.description),
        );
      });
    } catch (e) {
      if (mounted) setState(() => message = '$e');
    }
  }

  Future<void> _addCustomItem() async {
    if (!_canEdit) return;
    final ar = widget.language == 'ar';
    final enCtrl = TextEditingController();
    final arCtrl = TextEditingController();
    var def = 'Y';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(ar ? 'إضافة بند' : 'Add item'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: enCtrl,
                decoration: InputDecoration(
                  labelText: ar ? 'الوصف (EN)' : 'Description (EN)',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: arCtrl,
                decoration: InputDecoration(
                  labelText: ar ? 'الوصف (AR)' : 'Description (AR)',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: def,
                decoration: InputDecoration(
                  labelText: ar ? 'الإجابة المثالية' : 'Ideal answer',
                  border: const OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'Y', child: Text('Yes / نعم')),
                  DropdownMenuItem(value: 'N', child: Text('No / لا')),
                ],
                onChanged: (v) => setLocal(() => def = v ?? 'Y'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(ar ? 'إلغاء' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(ar ? 'إضافة' : 'Add'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final desc =
        enCtrl.text.trim().isNotEmpty ? enCtrl.text.trim() : arCtrl.text.trim();
    if (desc.isEmpty) return;
    final nextIndex = inspection.items.isEmpty
        ? 1
        : inspection.items.map((e) => e.itemIndex).reduce(math.max) + 1;
    final item = InspectionItem(
      itemIndex: nextIndex,
      description: enCtrl.text.trim().isNotEmpty ? enCtrl.text.trim() : desc,
      descriptionAr: arCtrl.text.trim().isEmpty ? null : arCtrl.text.trim(),
      defaultAnswer: def,
      isCustom: true,
    );
    setState(() => inspection.items.add(item));
    await ref.read(inspectionRepositoryProvider).saveItems(inspection);
    final full =
        await ref.read(inspectionRepositoryProvider).getById(inspection.id);
    if (full != null && mounted) setState(() => inspection = full);
    await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = _canEdit;
    final canApprove =
        inspection.awaitingReview && _isReviewer && _canManage;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: checklistGradientAppBar(
        title: '${inspection.buildingCode} — ${inspection.dateIso}',
        leading: checklistBackButton(context),
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
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$e')),
                        );
                      }
                    }
                  },
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
          if (canEdit)
            TextButton(
              onPressed: saving ? null : _save,
              child: Text(widget.language == 'ar' ? 'حفظ' : 'Save', style: const TextStyle(color: Colors.white)),
            ),
          if (!inspection.isSubmitted && _canWrite)
            TextButton(
              onPressed: saving ? null : _submit,
              child: Text(widget.language == 'ar' ? 'إرسال' : 'Submit', style: const TextStyle(color: Colors.white)),
            ),
          if (canApprove)
            TextButton(
              onPressed: saving ? null : _approve,
              child:
                  Text(widget.language == 'ar' ? 'اعتماد' : 'Approve', style: const TextStyle(color: Colors.white)),
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
              child: ChecklistFormLayout(
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
                onPickIssuePhoto: canEdit
                    ? (item) => _pickPhoto(item, isIssue: true)
                    : null,
                onPickFixPhoto: canEdit
                    ? (item) => _pickPhoto(item, isIssue: false)
                    : null,
                onClearIssuePhoto: canEdit
                    ? (item, path) => _clearPhoto(item, path, isIssue: true)
                    : null,
                onClearFixPhoto: canEdit
                    ? (item, path) => _clearPhoto(item, path, isIssue: false)
                    : null,
                onAddItem: canEdit ? _addCustomItem : null,
                onDeleteItem: canEdit ? _deleteCustomItem : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
