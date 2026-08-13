import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:checklist_shared/checklist_shared.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signature/signature.dart';

import 'screens/corrective_actions_screen.dart';
import 'screens/ops_dashboard_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ChecklistChrome.use(ChecklistBrand.viewer);
  await bootstrapSupabase();
  StructuredErrorReporter.install(appKey: 'viewer');
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

Future<String?> _requestWorkflowReason(
  BuildContext context, {
  required String language,
  required String action,
}) async {
  final ar = language == 'ar';
  final controller = TextEditingController();
  final title = switch (action) {
    'return' => ar ? 'إعادة الفحص للتصحيح' : 'Return for correction',
    'reject' => ar ? 'رفض الفحص' : 'Reject inspection',
    _ => ar ? 'إلغاء الفحص' : 'Cancel inspection',
  };
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        minLines: 3,
        maxLines: 6,
        decoration: InputDecoration(
          labelText: ar ? 'السبب (إلزامي)' : 'Reason (required)',
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(ar ? 'إلغاء' : 'Close'),
        ),
        FilledButton(
          onPressed: () {
            final value = controller.text.trim();
            if (value.isNotEmpty) Navigator.pop(dialogContext, value);
          },
          child: Text(ar ? 'تأكيد' : 'Confirm'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

class _WorkflowNoteBanner extends StatelessWidget {
  const _WorkflowNoteBanner({required this.inspection, required this.language});

  final Inspection inspection;
  final String language;

  @override
  Widget build(BuildContext context) {
    final ar = language == 'ar';
    final color = switch (inspection.reviewStatus) {
      ReviewStatus.returned => const Color(0xFFB45309),
      ReviewStatus.rejected || ReviewStatus.canceled => const Color(0xFFB91C1C),
      _ => Theme.of(context).colorScheme.primary,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: ChecklistBrandCard(
        borderColor: color,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${inspection.reviewStatus.labelFor(language)}: '
                '${inspection.workflowNote}',
                textAlign: ar ? TextAlign.right : TextAlign.left,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<ReportPhotoMode?> _pickReportPhotoMode(
  BuildContext context,
  String language,
) {
  final ar = language == 'ar';
  return showModalBottomSheet<ReportPhotoMode>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.link_outlined),
            title: Text(
              ar ? 'مراجع وروابط الصور' : 'Photo references & secure links',
            ),
            subtitle: Text(
              ar
                  ? 'تقرير خفيف مع مرجع ثابت ورابط آمن لكل صورة'
                  : 'Lightweight report with a stable reference and secure link',
            ),
            onTap: () => Navigator.pop(context, ReportPhotoMode.links),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(
              ar ? 'تضمين الصور في التقرير' : 'Include photos in PDF',
            ),
            subtitle: Text(
              ar
                  ? 'يضيف قسم أدلة الصور مع مراجع البنود'
                  : 'Adds a structured evidence section with item references',
            ),
            onTap: () => Navigator.pop(context, ReportPhotoMode.embedded),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

Future<bool> _createCorrectiveActionForInspection({
  required BuildContext context,
  required WidgetRef ref,
  required Inspection inspection,
  required String language,
}) async {
  final ar = language == 'ar';
  final failed = inspection.items
      .where(
        (item) =>
            item.id != null &&
            item.response != null &&
            item.response != ChecklistResponse.na &&
            !item.isIdealAnswer,
      )
      .toList();
  if (failed.isEmpty) return false;
  var selected = failed.first;
  var priority = CorrectiveActionPriority.medium;
  var dueDate = qatarBusinessNow().add(const Duration(days: 7));
  var evidenceRequired = true;
  final description = TextEditingController(text: selected.actionsTaken);
  final created = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(ar ? 'إجراء تصحيحي جديد' : 'New corrective action'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<InspectionItem>(
                  initialValue: selected,
                  decoration: InputDecoration(labelText: ar ? 'البند' : 'Item'),
                  items: [
                    for (final item in failed)
                      DropdownMenuItem(
                        value: item,
                        child: SizedBox(
                          width: 390,
                          child: Text(
                            '${item.itemIndex} — ${item.descriptionFor(language)}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => selected = value);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: description,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: ar ? 'وصف الإجراء المطلوب' : 'Required action',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<CorrectiveActionPriority>(
                  initialValue: priority,
                  decoration: InputDecoration(
                    labelText: ar ? 'الأولوية' : 'Priority',
                  ),
                  items: [
                    for (final value in CorrectiveActionPriority.values)
                      DropdownMenuItem(
                        value: value,
                        child: Text(value.labelFor(language)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => priority = value);
                  },
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: Text(ar ? 'تاريخ الاستحقاق' : 'Due date'),
                  subtitle: Text(
                    '${dueDate.year}-${dueDate.month.toString().padLeft(2, '0')}-'
                    '${dueDate.day.toString().padLeft(2, '0')}',
                  ),
                  onTap: () async {
                    final now = qatarBusinessNow();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: dueDate,
                      firstDate: DateTime(now.year, now.month, now.day),
                      lastDate: now.add(const Duration(days: 730)),
                    );
                    if (picked != null) {
                      setDialogState(() => dueDate = picked);
                    }
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: evidenceRequired,
                  onChanged: (value) =>
                      setDialogState(() => evidenceRequired = value),
                  title: Text(
                    ar
                        ? 'يتطلب دليلًا قبل الإغلاق'
                        : 'Require closure evidence',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(ar ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final text = description.text.trim();
              if (text.isEmpty) return;
              try {
                await ref
                    .read(correctiveActionRepositoryProvider)
                    .create(
                      inspectionItemId: selected.id!,
                      description: text,
                      priority: priority,
                      dueDate: dueDate,
                      evidenceRequired: evidenceRequired,
                    );
                if (context.mounted) Navigator.pop(context, true);
              } catch (exception) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('$exception')));
              }
            },
            child: Text(ar ? 'إنشاء' : 'Create'),
          ),
        ],
      ),
    ),
  );
  description.dispose();
  return created == true;
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
    // Resolve a single ThemeData into `theme:` only (no light/dark AnimatedTheme
    // cross-fade). ThemeMode.system follows the platform brightness.
    final platformDark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
    final useDark = switch (themeMode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => platformDark,
    };
    return MaterialApp(
      key: ValueKey(useDark ? 'viewer-dark' : 'viewer-light'),
      title: language == 'ar' ? 'فحص عرض' : 'Inspection Viewer',
      debugShowCheckedModeBanner: false,
      theme: useDark ? ChecklistChrome.darkTheme() : ChecklistChrome.theme(),
      themeMode: ThemeMode.light,
      themeAnimationDuration: Duration.zero,
      themeAnimationStyle: AnimationStyle.noAnimation,
      builder: (context, child) => Directionality(
        textDirection: rtl ? ui.TextDirection.rtl : ui.TextDirection.ltr,
        child: ChecklistAppBackground(child: child ?? const SizedBox.shrink()),
      ),
      home: ChecklistAuthGate(
        appTitle: language == 'ar' ? 'فحص عرض' : 'Inspection Viewer',
        subtitle: language == 'ar'
            ? 'عرض المعتمد وتعديل واعتماد حسب الصلاحية'
            : 'Approved view, edit and approve by permission',
        language: language,
        onLanguageChanged: (v) => setState(() {
          language = viewerLanguages.contains(v) ? v : 'en';
        }),
        allowSelfRegistration: true,
        registrationRequestedRole: 'viewer',
        brandMarkAsset: 'assets/branding/app_icon_simple.png',
        allowedForProfile: (p) => p.isPlatformOwner || p.role.canUseViewer,
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

  /// Drill-down: org → zone → campus → checklist.
  OrgBrowseSection? browseOrg;
  ZoneBrowseSection? browseZone;
  CampusChecklistGroup? browseCampus;
  List<OrgBrowseSection> orgSections = [];
  DateTime date = qatarBusinessNow();
  Inspection? selected;
  Set<int> overdueIndexes = {};
  Map<String, String> issueOpenTooltips = {};
  bool loading = true;
  String? message;

  /// 0=all visible, 1=pending review, 2=approved only (reviewers).
  int listMode = 0;
  Map<String, Set<int>> overdueByInspectionId = {};
  List<ChecklistNotice> notices = [];
  List<WorkflowNotification> workflowNotifications = [];
  String? openingInspectionId;
  int _loadGeneration = 0;
  int? _lastNoticeCount;
  final SignatureController _signature = SignatureController(
    penStrokeWidth: 2.4,
    penColor: kSignatureInkColor,
    exportBackgroundColor: Colors.white,
    exportPenColor: kSignatureInkColor,
  );
  Uint8List? _signaturePreviewBytes;
  final Set<String> _pendingMediaDeletes = {};

  String get language => widget.language;

  bool get _canNavBack =>
      browseOrg != null ||
      browseZone != null ||
      browseCampus != null ||
      siteFilter != null;

  String get _appBarTitle {
    if (siteFilter != null) {
      final site = sites.where((s) => s.id == siteFilter).firstOrNull;
      if (site != null) return site.buildingCode;
    }
    if (browseCampus != null) {
      return browseCampus!.titleFor(language);
    }
    if (browseZone != null) {
      return browseZone!.titleFor(language);
    }
    if (browseOrg != null) {
      return browseOrg!.organization.nameFor(language);
    }
    return language == 'ar' ? 'عرض الفحص' : 'Inspection Viewer';
  }

  void _navBack() {
    if (siteFilter != null) {
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
        selected = null;
      });
      return;
    }
    if (browseZone != null) {
      setState(() {
        browseZone = null;
        selected = null;
      });
      return;
    }
    if (browseOrg != null) {
      setState(() {
        browseOrg = null;
        selected = null;
      });
    }
  }

  void _openOrg(OrgBrowseSection org) {
    setState(() {
      browseOrg = org;
      browseZone = null;
      browseCampus = null;
      siteFilter = null;
      selected = null;
    });
  }

  void _openZone(ZoneBrowseSection zone) {
    setState(() {
      browseZone = zone;
      browseCampus = null;
      siteFilter = null;
      selected = null;
    });
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
      loading = true;
      message = null;
      _signaturePreviewBytes = null;
    });
    _signature.clear();
    try {
      final access = await ref.read(siteRepositoryProvider).listMySiteAccess();
      if (mounted) setState(() => myAccess = access);

      if (_canWriteSite(site.id)) {
        final repo = ref.read(inspectionRepositoryProvider);
        var insp = await repo.getForSiteDate(siteId: site.id, date: date);
        insp ??= await repo.createDraft(
          site: site,
          date: date,
          inspectorName: '',
          inspectionTime: DateFormat('h:mm a').format(qatarBusinessNow()),
          language: language,
        );
        if (!insp.isSubmitted) {
          final prior = await repo.getLatestOtherForSite(
            siteId: site.id,
            excludeInspectionId: insp.id,
          );
          if (prior != null) {
            final changed = applyOpenProblemCarryForward(
              current: insp,
              sourceByIndex: {for (final i in prior.items) i.itemIndex: i},
            );
            if (changed) {
              await repo.saveItems(insp);
            }
          }
        }
        await _load();
        if (!mounted) return;
        await _open(insp);
        return;
      }
      await _load();
    } catch (e) {
      if (mounted) {
        setState(
          () => message = e is InspectionReportEvidenceException
              ? e.messageFor(language)
              : e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _signature.dispose();
    super.dispose();
  }

  bool get _wide => MediaQuery.sizeOf(context).width >= 900;

  bool get _isReviewer => widget.profile.canReviewInspections;

  /// Regular viewers only see approved; writers/reviewers also see drafts.
  List<ReviewStatus>? _reviewFilterFor(List<UserSiteAccess> access) {
    if (_isReviewer) {
      if (listMode == 1) return [ReviewStatus.submitted];
      if (listMode == 2) return [ReviewStatus.approved];
      return [
        ReviewStatus.approved,
        ReviewStatus.submitted,
        ReviewStatus.draft,
        ReviewStatus.returned,
        ReviewStatus.rejected,
        ReviewStatus.canceled,
      ];
    }
    if (_canWriteAnySiteFor(access)) {
      return [
        ReviewStatus.approved,
        ReviewStatus.draft,
        ReviewStatus.submitted,
        ReviewStatus.returned,
        ReviewStatus.rejected,
        ReviewStatus.canceled,
      ];
    }
    return [ReviewStatus.approved];
  }

  bool _canWriteAnySiteFor(List<UserSiteAccess> access) {
    if (widget.profile.isPlatformOwner ||
        widget.profile.role == UserRole.superAdmin) {
      return true;
    }
    return access.any((a) => a.canWrite && a.isCurrentlyValid);
  }

  /// Direct USA or campus (parent) grant for a checklist unit.
  bool _hasAccessFlag(String siteId, bool Function(UserSiteAccess a) flag) {
    if (myAccess.any(
      (a) => a.siteId == siteId && a.isCurrentlyValid && flag(a),
    )) {
      return true;
    }
    final site = sites.where((s) => s.id == siteId).firstOrNull;
    final parentId = site?.parentSiteId;
    if (parentId == null) return false;
    return myAccess.any(
      (a) => a.siteId == parentId && a.isCurrentlyValid && flag(a),
    );
  }

  bool _canWriteSite(String siteId) {
    if (widget.profile.isPlatformOwner) return true;
    if (widget.profile.role == UserRole.superAdmin) {
      final home = widget.profile.homeOrganizationId;
      if (home == null) return true;
      final site = sites.where((s) => s.id == siteId).firstOrNull;
      if (site != null) return site.organizationId == home;
      return true;
    }
    return _hasAccessFlag(siteId, (a) => a.canWrite);
  }

  bool _canWriteSelected() {
    final insp = selected;
    if (insp == null) return false;
    return _canWriteSite(insp.siteId);
  }

  bool _canManageSelected() {
    final insp = selected;
    if (insp == null) return false;
    if (widget.profile.isPlatformOwner) return true;
    if (widget.profile.role == UserRole.superAdmin) {
      return _canWriteSite(insp.siteId);
    }
    return _hasAccessFlag(insp.siteId, (a) => a.canManage);
  }

  String _resolveOrgId(Inspection insp) {
    if (insp.organizationId.isNotEmpty) return insp.organizationId;
    final site = sites.where((s) => s.id == insp.siteId).firstOrNull;
    return site?.organizationId ?? '';
  }

  bool get _canEditSelected {
    final insp = selected;
    if (insp == null) return false;
    // Approved forms are view-only in Viewer (admin edits come later).
    if (insp.isTerminal) return false;
    if (_canManageSelected()) return true;
    if (!insp.isSubmitted) return _canWriteSelected();
    return false;
  }

  Future<void> _refreshOverdue(Inspection insp) async {
    final lookback = insp.items.isEmpty
        ? 14
        : insp.items
              .map((e) => e.overdueAfterDays)
              .fold<int>(14, (a, b) => math.max(a, b + 2));
    final history = await ref
        .read(inspectionRepositoryProvider)
        .listRecentForSite(
          siteId: insp.siteId,
          asOfDate: insp.inspectionDate,
          lookbackDays: lookback,
        );
    final map = buildProblemHistory(history: history, current: insp);
    final overdue = overdueItemIndexes(inspection: insp, problemByDateIso: map);
    final tips = buildIssueOpenTooltips(
      inspection: insp,
      history: history,
      overdueIndexes: overdue,
      language: language,
    );
    if (mounted) {
      setState(() {
        overdueIndexes = overdue;
        issueOpenTooltips = tips;
      });
    }
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() {
        loading = true;
        message = null;
      });
    }
    try {
      final siteRepo = ref.read(siteRepositoryProvider);
      final inspRepo = ref.read(inspectionRepositoryProvider);
      final orgRepo = ref.read(organizationRepositoryProvider);
      final foundation = await Future.wait<Object>([
        siteRepo.listAccessibleCampusGroups(profile: widget.profile),
        orgRepo.listOrganizations(activeOnly: true),
        orgRepo.listAllZones(),
        siteRepo.listMySiteAccess(),
        _safeUnreadNotifications(),
      ]);
      if (!mounted || generation != _loadGeneration) return;
      final groups = foundation[0] as List<CampusChecklistGroup>;
      final orgs = foundation[1] as List<Organization>;
      final allZones = foundation[2] as List<Zone>;
      final access = foundation[3] as List<UserSiteAccess>;
      final workflow = foundation[4] as List<WorkflowNotification>;
      final sections = groupCampusGroupsByOrgThenZone(
        organizations: orgs,
        zones: allZones.where((z) => z.isActive).toList(),
        groups: groups,
      );
      final siteList = [for (final g in groups) ...g.checklists];
      final list = await inspRepo.listInspections(
        siteId: siteFilter,
        date: date,
        reviewStatuses: _reviewFilterFor(access),
      );
      if (!mounted || generation != _loadGeneration) return;
      final checklistTypeBySiteId = {
        for (final site in siteList) site.id: site.checklistType,
      };
      final checklistTypeByInspectionId = <String, String>{};
      for (final row in list) {
        final type = checklistTypeBySiteId[row.siteId];
        if (type != null && type.isNotEmpty) {
          checklistTypeByInspectionId[row.id] = type;
        }
      }
      final itemsByInspection = await inspRepo.listItemsForInspections(
        inspectionIds: list.map((row) => row.id),
        checklistTypeByInspectionId: checklistTypeByInspectionId,
      );
      if (!mounted || generation != _loadGeneration) return;
      for (final row in list) {
        row.items
          ..clear()
          ..addAll(itemsByInspection[row.id] ?? const []);
      }
      final withItems = list;
      final overdueMap = <String, Set<int>>{};
      if (selected != null && overdueByInspectionId.containsKey(selected!.id)) {
        overdueMap[selected!.id] = overdueByInspectionId[selected!.id]!;
      }
      final built = <ChecklistNotice>[
        ...workflowNotificationsToNotices(
          notifications: workflow,
          language: language,
        ),
        ...buildViewerNotices(
          records: withItems,
          overdueByInspectionId: overdueMap,
          canReview: _isReviewer,
          language: language,
        ),
      ];
      final shouldAlert =
          _lastNoticeCount != null && built.length > _lastNoticeCount!;
      setState(() {
        orgSections = sections;
        campusGroups = groups;
        sites = siteList;
        myAccess = access;
        records = withItems;
        overdueByInspectionId = overdueMap;
        notices = built;
        workflowNotifications = workflow;
        _lastNoticeCount = built.length;
        if (selected != null) {
          selected = withItems.where((r) => r.id == selected!.id).firstOrNull;
        }
      });
      if (shouldAlert && ref.read(notificationsEnabledProvider)) {
        await ChecklistFeedback.alert(
          soundEnabled: ref.read(soundEnabledProvider),
          hapticsEnabled: ref.read(hapticsEnabledProvider),
        );
      }
      if (selected != null) await _refreshOverdue(selected!);
    } catch (e, stack) {
      await StructuredErrorReporter.capture(
        e,
        stack,
        module: 'viewer.home_load',
      );
      if (mounted && generation == _loadGeneration) {
        setState(() => message = e.toString());
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => loading = false);
      }
    }
  }

  Future<List<WorkflowNotification>> _safeUnreadNotifications() async {
    try {
      return await ref.read(notificationRepositoryProvider).listUnread();
    } catch (_) {
      return const [];
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
            final full = await ref
                .read(inspectionRepositoryProvider)
                .getById(id);
            if (full != null && mounted) await _open(full);
          },
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openCorrectiveActions() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CorrectiveActionsScreen(
          profile: widget.profile,
          language: language,
        ),
      ),
    );
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
    if (workflowNotifications.isNotEmpty) {
      try {
        await ref.read(notificationRepositoryProvider).markAllRead();
      } catch (_) {}
      if (mounted) {
        setState(() {
          workflowNotifications = [];
          notices = notices
              .where((notice) => notice.kind != ChecklistNoticeKind.workflow)
              .toList();
        });
      }
    }
  }

  Future<void> _exportSelected() async {
    final row = selected;
    if (row == null) return;
    try {
      setState(
        () => message = language == 'ar' ? 'جاري التصدير…' : 'Exporting…',
      );
      final full = row.items.isEmpty
          ? await ref.read(inspectionRepositoryProvider).getById(row.id)
          : row;
      if (full == null) throw Exception('Inspection not found');
      final action = await _pickExportAction();
      if (action == null) {
        if (mounted) setState(() => message = null);
        return;
      }
      if (!mounted) return;
      final photoMode = await _pickReportPhotoMode(context, language);
      if (photoMode == null) {
        if (mounted) setState(() => message = null);
        return;
      }
      final exporter = InspectionReportExporter();
      if (action == 'print') {
        await exporter.print(full, language: language, photoMode: photoMode);
      } else {
        await exporter.export(full, language: language, photoMode: photoMode);
      }
      if (mounted) {
        setState(
          () =>
              message = language == 'ar' ? 'تم تجهيز التقرير' : 'Report ready',
        );
      }
    } catch (e, stack) {
      await StructuredErrorReporter.capture(
        e,
        stack,
        module: 'viewer.inspection_report',
      );
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
    if (openingInspectionId != null) return;
    if (mounted) setState(() => openingInspectionId = row.id);
    try {
      final full = row.items.isNotEmpty
          ? row
          : await ref.read(inspectionRepositoryProvider).getById(row.id);
      if (full == null) {
        setState(
          () => message = language == 'ar'
              ? 'تعذر فتح السجل'
              : 'Could not open record',
        );
        return;
      }
      // Approved for all; drafts/submitted only for writers or reviewers.
      if (full.reviewStatus != ReviewStatus.approved) {
        final allowed = _isReviewer || _canWriteSite(full.siteId);
        if (!allowed) {
          setState(
            () => message = language == 'ar'
                ? 'هذا الفحص غير معتمد للعرض بعد'
                : 'This inspection is not approved for viewing yet',
          );
          return;
        }
      }
      _signature.clear();
      if (mounted) setState(() => _signaturePreviewBytes = null);
      if (!_wide && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => InspectionFormPage(
              profile: widget.profile,
              language: language,
              initial: full,
              myAccess: myAccess,
              sites: sites,
              onChanged: () async {
                await _load();
              },
            ),
          ),
        );
        await _load();
        return;
      }
      if (mounted) setState(() => selected = full);
      await _refreshOverdue(full);
    } finally {
      if (mounted && openingInspectionId == row.id) {
        setState(() => openingInspectionId = null);
      }
    }
  }

  Future<bool> _checkPhotoPolicy(Inspection current) async {
    final orgId = current.organizationId;
    if (orgId.isEmpty) return true;
    final pol = await ref.read(policyRepositoryProvider).getOrCreate(orgId);
    if (!mounted) return false;
    final result = validateProblemPhotos(inspection: current, policy: pol);
    if (result.ok) return true;
    if (result.blocksSubmit) {
      setState(() => message = result.messageFor(language));
      return false;
    }
    if (result.severity == PolicySeverity.info) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.messageFor(language))));
      }
      return true;
    }
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          language == 'ar' ? 'صورة المشكلة ناقصة' : 'Issue photo missing',
        ),
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

  Future<void> _persistSignatureIfNeeded(Inspection current) async {
    if (!_canEditSelected) return;
    if (current.signaturePath != null && current.signaturePath!.isNotEmpty) {
      return;
    }
    if (!_signature.isNotEmpty) return;
    final raw = await _signature.toPngBytes();
    if (raw == null || raw.isEmpty) return;
    final bytes = recolorSignatureToBlueInk(Uint8List.fromList(raw));
    final orgId = _resolveOrgId(current);
    if (orgId.isEmpty) return;
    final path = await ref
        .read(inspectionRepositoryProvider)
        .uploadBytes(
          organizationId: orgId,
          siteId: current.siteId,
          inspectionId: current.id,
          fileName: 'signature.png',
          bytes: bytes,
          contentType: 'image/png',
          evidenceKind: 'signature',
        );
    current.signaturePath = path;
    if (mounted) {
      setState(() => _signaturePreviewBytes = bytes);
      _signature.clear();
    }
  }

  Future<void> _save() async {
    final current = selected;
    if (current == null || !_canEditSelected) return;
    try {
      await _persistSignatureIfNeeded(current);
      await ref.read(inspectionRepositoryProvider).saveItems(current);
      await _flushMediaDeletes();
      await ChecklistFeedback.success(
        soundEnabled: ref.read(soundEnabledProvider),
        hapticsEnabled: ref.read(hapticsEnabledProvider),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              language == 'ar' ? 'تم حفظ التعديلات' : 'Changes saved',
            ),
          ),
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
    if (!mounted) return;
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
      await _persistSignatureIfNeeded(current);
      await ref.read(inspectionRepositoryProvider).saveItems(current);
      await ref.read(inspectionRepositoryProvider).submit(current);
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
      await ref.read(inspectionRepositoryProvider).approveInspection(current);
      await ChecklistFeedback.success(
        soundEnabled: ref.read(soundEnabledProvider),
        hapticsEnabled: ref.read(hapticsEnabledProvider),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              language == 'ar'
                  ? 'تم اعتماد الفحص للعرض'
                  : 'Inspection approved for viewing',
            ),
          ),
        );
      }
      await _load();
      final full = await ref
          .read(inspectionRepositoryProvider)
          .getById(current.id);
      if (full != null) {
        setState(() => selected = full);
        await _refreshOverdue(full);
      }
    } catch (e) {
      setState(() => message = e.toString());
    }
  }

  Future<void> _decideSelectedWorkflow(String action) async {
    final current = selected;
    if (current == null ||
        !current.awaitingReview ||
        !_isReviewer ||
        !_canManageSelected()) {
      return;
    }
    final reason = await _requestWorkflowReason(
      context,
      language: language,
      action: action,
    );
    if (reason == null || !mounted) return;
    try {
      await ref.read(inspectionRepositoryProvider).saveItems(current);
      final repository = ref.read(inspectionRepositoryProvider);
      if (action == 'return') {
        await repository.returnInspection(inspection: current, reason: reason);
      } else {
        await repository.rejectInspection(inspection: current, reason: reason);
      }
      await _load();
      final full = await repository.getById(current.id);
      if (full != null && mounted) setState(() => selected = full);
    } catch (exception) {
      if (mounted) setState(() => message = '$exception');
    }
  }

  Future<void> _cancelSelectedWorkflow() async {
    final current = selected;
    if (current == null ||
        current.isTerminal ||
        !widget.profile.isPlatformOwner) {
      return;
    }
    final reason = await _requestWorkflowReason(
      context,
      language: language,
      action: 'cancel',
    );
    if (reason == null || !mounted) return;
    try {
      if (_canEditSelected) {
        await ref.read(inspectionRepositoryProvider).saveItems(current);
      }
      final repository = ref.read(inspectionRepositoryProvider);
      await repository.cancelInspectionAsOwner(
        inspection: current,
        reason: reason,
      );
      await _load();
      final full = await repository.getById(current.id);
      if (full != null && mounted) setState(() => selected = full);
    } catch (exception) {
      if (mounted) setState(() => message = '$exception');
    }
  }

  Future<void> _changeSelectedDateAsOwner() async {
    final current = selected;
    if (current == null ||
        current.isTerminal ||
        !widget.profile.isPlatformOwner) {
      return;
    }
    final now = qatarBusinessNow();
    final today = DateTime(now.year, now.month, now.day);
    var selectedDate = current.inspectionDate.isAfter(today)
        ? today
        : current.inspectionDate;
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            language == 'ar' ? 'تصحيح تاريخ الفحص' : 'Correct inspection date',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2024),
                    lastDate: today,
                  );
                  if (picked != null) {
                    setDialogState(() => selectedDate = picked);
                  }
                },
                icon: const Icon(Icons.event_outlined),
                label: Text(DateFormat('yyyy-MM-dd').format(selectedDate)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reason,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: language == 'ar'
                      ? 'سبب التصحيح (إلزامي)'
                      : 'Correction reason (required)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(language == 'ar' ? 'إلغاء' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, reason.text.trim().isNotEmpty),
              child: Text(language == 'ar' ? 'حفظ التصحيح' : 'Save correction'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) {
      reason.dispose();
      return;
    }
    try {
      await ref
          .read(inspectionRepositoryProvider)
          .changeInspectionDateAsOwner(
            inspection: current,
            newDate: selectedDate,
            reason: reason.text.trim(),
          );
      if (!mounted) return;
      setState(() => date = selectedDate);
      await _load();
      final full = await ref
          .read(inspectionRepositoryProvider)
          .getById(current.id);
      if (full != null && mounted) await _open(full);
    } catch (error) {
      if (mounted) setState(() => message = '$error');
    } finally {
      reason.dispose();
    }
  }

  Widget _filtersBar({required bool showActions}) {
    final canEdit = _canEditSelected;
    final canApprove =
        selected != null &&
        selected!.awaitingReview &&
        _isReviewer &&
        _canManageSelected();
    final canSubmitDraft =
        selected != null && !selected!.isSubmitted && _canWriteSelected();
    return Material(
      color:
          (Theme.of(context).brightness == Brightness.dark
                  ? ChecklistChrome.darkSurface
                  : Theme.of(context).colorScheme.surface)
              .withValues(alpha: ChecklistChrome.listSurfaceOpacity),
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
                  ButtonSegment(
                    value: 0,
                    label: Text(language == 'ar' ? 'الكل' : 'All'),
                  ),
                  ButtonSegment(
                    value: 1,
                    label: Text(
                      language == 'ar' ? 'بانتظار الاعتماد' : 'Pending',
                    ),
                  ),
                  ButtonSegment(
                    value: 2,
                    label: Text(language == 'ar' ? 'معتمدة' : 'Approved'),
                  ),
                ],
                selected: {listMode},
                onSelectionChanged: (s) async {
                  setState(() => listMode = s.first);
                  await _load();
                },
              ),
            OutlinedButton.icon(
              onPressed: () async {
                final now = qatarBusinessNow();
                final today = DateTime(now.year, now.month, now.day);
                final picked = await showDatePicker(
                  context: context,
                  initialDate: date.isAfter(today) ? today : date,
                  firstDate: DateTime(2024),
                  lastDate: today,
                );
                if (picked == null) return;
                setState(() => date = picked);
                await _load();
              },
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text(DateFormat('yyyy-MM-dd').format(date)),
            ),
            IconButton(
              onPressed: loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
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
                child: Text(
                  language == 'ar' ? 'إرسال التقرير' : 'Submit report',
                ),
              ),
            if (showActions && canApprove)
              OutlinedButton.icon(
                onPressed: () => _decideSelectedWorkflow('return'),
                icon: const Icon(Icons.undo_outlined),
                label: Text(language == 'ar' ? 'إعادة للتصحيح' : 'Return'),
              ),
            if (showActions && canApprove)
              OutlinedButton.icon(
                onPressed: () => _decideSelectedWorkflow('reject'),
                icon: const Icon(Icons.cancel_outlined),
                label: Text(language == 'ar' ? 'رفض' : 'Reject'),
              ),
            if (showActions && canApprove)
              FilledButton.icon(
                onPressed: _approve,
                icon: const Icon(Icons.verified_outlined),
                label: Text(
                  language == 'ar' ? 'اعتماد للعرض' : 'Approve for view',
                ),
              ),
            if (showActions &&
                selected != null &&
                !selected!.isTerminal &&
                widget.profile.isPlatformOwner)
              OutlinedButton.icon(
                onPressed: _changeSelectedDateAsOwner,
                icon: const Icon(Icons.edit_calendar_outlined),
                label: Text(
                  language == 'ar' ? 'تصحيح التاريخ' : 'Correct date',
                ),
              ),
            if (showActions &&
                selected != null &&
                !selected!.isTerminal &&
                widget.profile.isPlatformOwner)
              OutlinedButton.icon(
                onPressed: _cancelSelectedWorkflow,
                icon: const Icon(Icons.block_outlined),
                label: Text(language == 'ar' ? 'إلغاء الفحص' : 'Cancel'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _orgSectionsList() {
    if (orgSections.isEmpty) {
      return Center(
        child: Text(language == 'ar' ? 'لا توجد مواقع' : 'No sites'),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: orgSections.length,
      itemBuilder: (context, i) {
        final org = orgSections[i];
        return ChecklistBrandCard(
          onTap: () => _openOrg(org),
          child: Row(
            children: [
              ChecklistIconWell(icon: Icons.account_balance_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      org.organization.nameFor(language),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      language == 'ar'
                          ? '${org.zones.length} مناطق · ${org.campusCount} مواقع'
                          : '${org.zones.length} zones · ${org.campusCount} sites',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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

  Widget _zonesList(OrgBrowseSection org) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: org.zones.length,
      itemBuilder: (context, i) {
        final zone = org.zones[i];
        return ChecklistBrandCard(
          onTap: () => _openZone(zone),
          child: Row(
            children: [
              ChecklistIconWell(icon: Icons.map_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      zone.titleFor(language),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      language == 'ar'
                          ? '${zone.groups.length} مواقع'
                          : '${zone.groups.length} sites',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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

  Widget _campusesInZoneList(ZoneBrowseSection zone) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: zone.groups.length,
      itemBuilder: (context, i) {
        final group = zone.groups[i];
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
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      language == 'ar'
                          ? '${group.checklists.length} قوائم فحص'
                          : '${group.checklists.length} checklists',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${site.buildingCode} · ${site.checklistType}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
    if (siteFilter != null) {
      return _recordsList();
    }
    if (browseCampus != null) {
      return _campusChecklistsList(browseCampus!);
    }
    if (browseZone != null) {
      return _campusesInZoneList(browseZone!);
    }
    if (browseOrg != null) {
      return _zonesList(browseOrg!);
    }
    return _orgSectionsList();
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
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 24),
      itemCount: records.length,
      itemBuilder: (context, i) {
        final r = records[i];
        final selectedId = selected?.id == r.id;
        final opening = openingInspectionId == r.id;
        return ChecklistBrandCard(
          key: ValueKey(r.id),
          margin: const EdgeInsets.only(bottom: 10),
          padding: EdgeInsets.zero,
          borderColor: selectedId ? ChecklistChrome.accent : null,
          borderWidth: selectedId ? 2 : 1.2,
          onTap: opening ? null : () => _open(r),
          child: ListTile(
            selected: selectedId,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            leading: ChecklistIconWell(
              icon: r.isApproved
                  ? Icons.verified_outlined
                  : r.awaitingReview
                  ? Icons.rate_review_outlined
                  : Icons.description_outlined,
              size: 38,
              iconSize: 19,
            ),
            title: Text(
              r.buildingCode,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              '${r.inspectorName} • ${r.reviewStatus.labelFor(language)}',
            ),
            trailing: opening
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Icon(Icons.chevron_left),
          ),
        );
      },
    );
  }

  Future<void> _pickPhoto(
    InspectionItem item, {
    required bool isIssue,
    String? pairId,
  }) async {
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
      final validation = ImageUploadValidation.validate(bytes);
      if (!validation.ok) {
        throw FormatException(validation.messageFor(language));
      }
      final site = sites.where((s) => s.id == current.siteId).firstOrNull;
      final photoCtx =
          await InspectionPhotoStampResolver(
            ref.read(supabaseClientProvider),
          ).buildContext(
            site: site,
            language: language,
            buildingCode: current.buildingCode,
            inspectionDateIso: current.dateIso,
            inspectionTime: current.inspectionTime,
            itemIndex: item.itemIndex,
            itemDescription: item.descriptionFor(language),
            inspectorName: current.inspectorName,
            kindLabel: language == 'ar'
                ? (isIssue ? 'مشكلة' : 'إصلاح')
                : (isIssue ? 'Issue' : 'Repair'),
            sourceLabel: language == 'ar' ? 'المعرض' : 'Gallery',
            organizationIdFallback: current.organizationId,
            siteNameFallback: current.siteNameEn.isNotEmpty
                ? current.siteNameEn
                : current.buildingCode,
          );
      final stamped = await InspectionPhotoWatermark().apply(
        imageBytes: bytes,
        context: photoCtx,
        arabic: language == 'ar',
      );
      final orgId = _resolveOrgId(current);
      if (orgId.isEmpty) {
        throw Exception(
          language == 'ar'
              ? 'تعذر تحديد الجهة لرفع الصورة'
              : 'Could not resolve organization for photo upload',
        );
      }
      final kind = isIssue ? 'issue' : 'fix';
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final path = await ref
          .read(inspectionRepositoryProvider)
          .uploadBytes(
            organizationId: orgId,
            siteId: current.siteId,
            inspectionId: current.id,
            fileName: '${item.itemIndex}_${kind}_$stamp.jpg',
            bytes: stamped,
            evidenceItemId: item.id,
            evidenceKind: '${kind}_photo',
          );
      setState(() {
        if (isIssue) {
          item.appendIssueImage(path);
        } else {
          item.appendFixImage(path, pairId: pairId);
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
    String? pairId,
  }) async {
    final current = selected;
    if (current == null || !_canEditSelected) return;
    setState(() {
      if (isIssue) {
        item.removeIssueImage(path, pairId: pairId);
      } else {
        item.removeFixImage(path, pairId: pairId);
      }
    });
    await ref.read(inspectionRepositoryProvider).saveItems(current);
    try {
      await ref.read(inspectionRepositoryProvider).deleteMedia(path);
    } catch (_) {
      // The database no longer references the object; cleanup can be retried.
    }
  }

  Future<void> _flushMediaDeletes() async {
    final repository = ref.read(inspectionRepositoryProvider);
    for (final path in _pendingMediaDeletes.toList()) {
      try {
        await repository.deleteMedia(path);
        _pendingMediaDeletes.remove(path);
      } catch (_) {
        // Retain for the next successful save.
      }
    }
  }

  Future<void> _deleteCustomItem(InspectionItem item) async {
    final current = selected;
    if (current == null || !_canManageSelected() || !item.isCustom) return;
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
            .deleteInspectionItem(current, item.id!);
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
          SnackBar(content: Text(ar ? 'تم حذف البند' : 'Item deleted')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => message = '$e');
    }
  }

  Future<void> _addCustomItem() async {
    final current = selected;
    if (current == null || !_canManageSelected()) return;
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
                  labelText: language == 'ar'
                      ? 'الوصف (EN)'
                      : 'Description (EN)',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ar,
                decoration: InputDecoration(
                  labelText: language == 'ar'
                      ? 'الوصف (AR)'
                      : 'Description (AR)',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: def,
                decoration: InputDecoration(
                  labelText: language == 'ar'
                      ? 'الإجابة المثالية'
                      : 'Ideal answer',
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
    final full = await ref
        .read(inspectionRepositoryProvider)
        .getById(current.id);
    if (full != null && mounted) {
      setState(() => selected = full);
      await _refreshOverdue(full);
    }
  }

  Widget _formPane() {
    if (selected == null) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surface.withValues(
          alpha: ChecklistChrome.listSurfaceOpacity,
        ),
        child: Center(
          child: Text(
            language == 'ar'
                ? 'اختر سجلًا لعرض النموذج على ورقة A4'
                : 'Select a record to view the A4 form',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    final canEdit = _canEditSelected;
    final canManage = _canManageSelected();
    return A4PaperSheet(
      child: ChecklistFormLayout(
        inspection: selected!,
        language: language,
        forceTableLayout: true,
        readOnly: !canEdit,
        overdueItemIndexes: overdueIndexes,
        issueOpenTooltipsByPath: issueOpenTooltips,
        onInspectorChanged: (v) => setState(() => selected!.inspectorName = v),
        onTimeChanged: (v) => setState(() => selected!.inspectionTime = v),
        onFloorChanged: (v) => setState(() => selected!.floorLabel = v),
        onResponseChanged: (item, value) {
          final err = item.trySetResponse(value, language: language);
          if (err != null && mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(err)));
          }
          setState(() {});
        },
        onActionsChanged: (item, value) =>
            setState(() => item.actionsTaken = value),
        onPickIssuePhoto: canEdit
            ? (item, [pairId]) =>
                  _pickPhoto(item, isIssue: true, pairId: pairId)
            : null,
        onPickFixPhoto: canEdit
            ? (item, [pairId]) =>
                  _pickPhoto(item, isIssue: false, pairId: pairId)
            : null,
        onClearIssuePhoto: canEdit
            ? (item, path, [pairId]) =>
                  _clearPhoto(item, path, isIssue: true, pairId: pairId)
            : null,
        onClearFixPhoto: canEdit
            ? (item, path, [pairId]) =>
                  _clearPhoto(item, path, isIssue: false, pairId: pairId)
            : null,
        onAddItem: canManage ? _addCustomItem : null,
        onDeleteItem: canManage ? _deleteCustomItem : null,
        signatureController: canEdit ? _signature : null,
        signaturePreviewBytes: _signaturePreviewBytes,
        onClearSignature: canEdit
            ? () {
                _signature.clear();
                final oldPath = selected!.signaturePath;
                if (oldPath != null && oldPath.isNotEmpty) {
                  _pendingMediaDeletes.add(oldPath);
                }
                setState(() {
                  selected!.signaturePath = null;
                  _signaturePreviewBytes = null;
                });
              }
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
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
            tooltip: language == 'ar'
                ? 'الإجراءات التصحيحية'
                : 'Corrective actions',
            onPressed: _openCorrectiveActions,
            icon: const Icon(Icons.build_circle_outlined),
          ),
          IconButton(
            tooltip: language == 'ar'
                ? 'المتابعة والإشراف'
                : 'Ops & Supervision',
            onPressed: _openOpsDashboard,
            icon: const Icon(Icons.analytics_outlined),
          ),
          if (ref.watch(notificationsEnabledProvider))
            ChecklistNoticeBell(notices: notices, onOpen: _openNotices),
          if (selected != null)
            IconButton(
              tooltip: language == 'ar' ? 'تصدير PDF' : 'Export PDF',
              onPressed: _exportSelected,
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
          IconButton(
            tooltip: language == 'ar' ? 'تحديث' : 'Refresh',
            onPressed: loading ? null : _load,
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
    required this.sites,
    required this.onChanged,
  });

  final Profile profile;
  final String language;
  final Inspection initial;
  final List<UserSiteAccess> myAccess;
  final List<ChecklistSite> sites;
  final Future<void> Function() onChanged;

  @override
  ConsumerState<InspectionFormPage> createState() => _InspectionFormPageState();
}

class _InspectionFormPageState extends ConsumerState<InspectionFormPage> {
  late Inspection inspection;
  Set<int> overdueIndexes = {};
  Map<String, String> issueOpenTooltips = {};
  String? message;
  bool saving = false;
  final SignatureController _signature = SignatureController(
    penStrokeWidth: 2.4,
    penColor: kSignatureInkColor,
    exportBackgroundColor: Colors.white,
    exportPenColor: kSignatureInkColor,
  );
  Uint8List? _signaturePreviewBytes;
  final Set<String> _pendingMediaDeletes = {};

  @override
  void initState() {
    super.initState();
    inspection = widget.initial;
    _loadOverdue();
  }

  @override
  void dispose() {
    _signature.dispose();
    super.dispose();
  }

  bool get _isReviewer => widget.profile.canReviewInspections;

  bool _hasAccessFlag(String siteId, bool Function(UserSiteAccess a) flag) {
    if (widget.myAccess.any((a) => a.siteId == siteId && flag(a))) return true;
    final site = widget.sites.where((s) => s.id == siteId).firstOrNull;
    final parentId = site?.parentSiteId;
    if (parentId == null) return false;
    return widget.myAccess.any((a) => a.siteId == parentId && flag(a));
  }

  String _resolveOrgId() {
    if (inspection.organizationId.isNotEmpty) return inspection.organizationId;
    final site = widget.sites
        .where((s) => s.id == inspection.siteId)
        .firstOrNull;
    return site?.organizationId ?? '';
  }

  bool get _canWrite {
    if (widget.profile.isPlatformOwner) return true;
    if (widget.profile.role == UserRole.superAdmin) {
      final home = widget.profile.homeOrganizationId;
      if (home == null) return true;
      final site = widget.sites
          .where((s) => s.id == inspection.siteId)
          .firstOrNull;
      if (site != null) return site.organizationId == home;
      return true;
    }
    return _hasAccessFlag(inspection.siteId, (a) => a.canWrite);
  }

  bool get _canManage {
    if (widget.profile.isPlatformOwner) return true;
    if (widget.profile.role == UserRole.superAdmin) return _canWrite;
    return _hasAccessFlag(inspection.siteId, (a) => a.canManage);
  }

  bool get _canEdit {
    // Approved forms are view-only in Viewer (admin edits come later).
    if (inspection.isTerminal) return false;
    if (_canManage) return true;
    if (!inspection.isSubmitted) return _canWrite;
    return false;
  }

  Future<void> _loadOverdue() async {
    final lookback = inspection.items
        .map((e) => e.overdueAfterDays)
        .fold<int>(14, (a, b) => math.max(a, b + 2));
    final history = await ref
        .read(inspectionRepositoryProvider)
        .listRecentForSite(
          siteId: inspection.siteId,
          asOfDate: inspection.inspectionDate,
          lookbackDays: lookback,
        );
    final map = buildProblemHistory(history: history, current: inspection);
    final overdue = overdueItemIndexes(
      inspection: inspection,
      problemByDateIso: map,
    );
    final tips = buildIssueOpenTooltips(
      inspection: inspection,
      history: history,
      overdueIndexes: overdue,
      language: widget.language,
    );
    if (mounted) {
      setState(() {
        overdueIndexes = overdue;
        issueOpenTooltips = tips;
      });
    }
  }

  Future<bool> _checkPhotoPolicy() async {
    final orgId = inspection.organizationId;
    if (orgId.isEmpty) return true;
    final pol = await ref.read(policyRepositoryProvider).getOrCreate(orgId);
    if (!mounted) return false;
    final result = validateProblemPhotos(inspection: inspection, policy: pol);
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
        title: Text(
          widget.language == 'ar'
              ? 'صورة المشكلة ناقصة'
              : 'Issue photo missing',
        ),
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

  Future<void> _persistSignatureIfNeeded() async {
    if (!_canEdit) return;
    if (inspection.signaturePath != null &&
        inspection.signaturePath!.isNotEmpty) {
      return;
    }
    if (!_signature.isNotEmpty) return;
    final raw = await _signature.toPngBytes();
    if (raw == null || raw.isEmpty) return;
    final bytes = recolorSignatureToBlueInk(Uint8List.fromList(raw));
    final orgId = _resolveOrgId();
    if (orgId.isEmpty) return;
    final path = await ref
        .read(inspectionRepositoryProvider)
        .uploadBytes(
          organizationId: orgId,
          siteId: inspection.siteId,
          inspectionId: inspection.id,
          fileName: 'signature.png',
          bytes: bytes,
          contentType: 'image/png',
          evidenceKind: 'signature',
        );
    inspection.signaturePath = path;
    if (mounted) {
      setState(() => _signaturePreviewBytes = bytes);
      _signature.clear();
    }
  }

  Future<void> _save() async {
    if (!_canEdit) return;
    setState(() => saving = true);
    try {
      await _persistSignatureIfNeeded();
      await ref.read(inspectionRepositoryProvider).saveItems(inspection);
      await _flushMediaDeletes();
      await widget.onChanged();
      await ChecklistFeedback.success(
        soundEnabled: ref.read(soundEnabledProvider),
        hapticsEnabled: ref.read(hapticsEnabledProvider),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.language == 'ar' ? 'تم الحفظ' : 'Saved'),
          ),
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
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          widget.language == 'ar' ? 'إرسال التقرير' : 'Submit report',
        ),
        content: Text(
          widget.language == 'ar'
              ? 'تأكيد إرسال سجل الفحص؟'
              : 'Submit this inspection?',
        ),
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
      await _persistSignatureIfNeeded();
      await ref.read(inspectionRepositoryProvider).saveItems(inspection);
      await ref.read(inspectionRepositoryProvider).submit(inspection);
      final full = await ref
          .read(inspectionRepositoryProvider)
          .getById(inspection.id);
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
          .approveInspection(inspection);
      final full = await ref
          .read(inspectionRepositoryProvider)
          .getById(inspection.id);
      if (full != null) setState(() => inspection = full);
      await widget.onChanged();
      await ChecklistFeedback.success(
        soundEnabled: ref.read(soundEnabledProvider),
        hapticsEnabled: ref.read(hapticsEnabledProvider),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.language == 'ar' ? 'تم الاعتماد' : 'Approved'),
          ),
        );
      }
    } catch (e) {
      setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _decideWorkflow(String action) async {
    if (!inspection.awaitingReview || !_isReviewer || !_canManage) return;
    final reason = await _requestWorkflowReason(
      context,
      language: widget.language,
      action: action,
    );
    if (reason == null || !mounted) return;
    setState(() => saving = true);
    try {
      await ref.read(inspectionRepositoryProvider).saveItems(inspection);
      final repository = ref.read(inspectionRepositoryProvider);
      if (action == 'return') {
        await repository.returnInspection(
          inspection: inspection,
          reason: reason,
        );
      } else {
        await repository.rejectInspection(
          inspection: inspection,
          reason: reason,
        );
      }
      final full = await repository.getById(inspection.id);
      if (full != null && mounted) setState(() => inspection = full);
      await widget.onChanged();
    } catch (exception) {
      if (mounted) setState(() => message = '$exception');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _cancelWorkflow() async {
    if (inspection.isTerminal || !widget.profile.isPlatformOwner) return;
    final reason = await _requestWorkflowReason(
      context,
      language: widget.language,
      action: 'cancel',
    );
    if (reason == null || !mounted) return;
    setState(() => saving = true);
    try {
      if (_canEdit) {
        await ref.read(inspectionRepositoryProvider).saveItems(inspection);
      }
      final repository = ref.read(inspectionRepositoryProvider);
      await repository.cancelInspectionAsOwner(
        inspection: inspection,
        reason: reason,
      );
      final full = await repository.getById(inspection.id);
      if (full != null && mounted) setState(() => inspection = full);
      await widget.onChanged();
    } catch (exception) {
      if (mounted) setState(() => message = '$exception');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _pickPhoto(
    InspectionItem item, {
    required bool isIssue,
    String? pairId,
  }) async {
    if (!_canEdit) return;
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 1600,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final validation = ImageUploadValidation.validate(bytes);
      if (!validation.ok) {
        throw FormatException(validation.messageFor(widget.language));
      }
      final lang = widget.language;
      ChecklistSite? site;
      try {
        final loaded = await ref.read(siteRepositoryProvider).listSitesByIds([
          inspection.siteId,
        ]);
        site = loaded.isNotEmpty ? loaded.first : null;
      } catch (_) {}
      final photoCtx =
          await InspectionPhotoStampResolver(
            ref.read(supabaseClientProvider),
          ).buildContext(
            site: site,
            language: lang,
            buildingCode: inspection.buildingCode,
            inspectionDateIso: inspection.dateIso,
            inspectionTime: inspection.inspectionTime,
            itemIndex: item.itemIndex,
            itemDescription: item.descriptionFor(lang),
            inspectorName: inspection.inspectorName,
            kindLabel: lang == 'ar'
                ? (isIssue ? 'مشكلة' : 'إصلاح')
                : (isIssue ? 'Issue' : 'Repair'),
            sourceLabel: lang == 'ar' ? 'المعرض' : 'Gallery',
            organizationIdFallback: inspection.organizationId,
            siteNameFallback: inspection.siteNameEn.isNotEmpty
                ? inspection.siteNameEn
                : inspection.buildingCode,
          );
      final stamped = await InspectionPhotoWatermark().apply(
        imageBytes: bytes,
        context: photoCtx,
        arabic: lang == 'ar',
      );
      final orgId = _resolveOrgId();
      if (orgId.isEmpty) {
        throw Exception(
          widget.language == 'ar'
              ? 'تعذر تحديد الجهة لرفع الصورة'
              : 'Could not resolve organization for photo upload',
        );
      }
      final kind = isIssue ? 'issue' : 'fix';
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final path = await ref
          .read(inspectionRepositoryProvider)
          .uploadBytes(
            organizationId: orgId,
            siteId: inspection.siteId,
            inspectionId: inspection.id,
            fileName: '${item.itemIndex}_${kind}_$stamp.jpg',
            bytes: stamped,
            evidenceItemId: item.id,
            evidenceKind: '${kind}_photo',
          );
      setState(() {
        if (isIssue) {
          item.appendIssueImage(path);
        } else {
          item.appendFixImage(path, pairId: pairId);
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
    String? pairId,
  }) async {
    if (!_canEdit) return;
    setState(() {
      if (isIssue) {
        item.removeIssueImage(path, pairId: pairId);
      } else {
        item.removeFixImage(path, pairId: pairId);
      }
    });
    await ref.read(inspectionRepositoryProvider).saveItems(inspection);
    try {
      await ref.read(inspectionRepositoryProvider).deleteMedia(path);
    } catch (_) {
      // The database no longer references the object; cleanup can be retried.
    }
  }

  Future<void> _flushMediaDeletes() async {
    final repository = ref.read(inspectionRepositoryProvider);
    for (final path in _pendingMediaDeletes.toList()) {
      try {
        await repository.deleteMedia(path);
        _pendingMediaDeletes.remove(path);
      } catch (_) {
        // Retain for the next successful save.
      }
    }
  }

  Future<void> _deleteCustomItem(InspectionItem item) async {
    if (!_canManage || !item.isCustom) return;
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
            .deleteInspectionItem(inspection, item.id!);
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
    if (!_canManage) return;
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
                initialValue: def,
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
    final desc = enCtrl.text.trim().isNotEmpty
        ? enCtrl.text.trim()
        : arCtrl.text.trim();
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
    final full = await ref
        .read(inspectionRepositoryProvider)
        .getById(inspection.id);
    if (full != null && mounted) setState(() => inspection = full);
    await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = _canEdit;
    final canManage = _canManage;
    final canApprove = inspection.awaitingReview && _isReviewer && _canManage;
    final hasFailedItems = inspection.items.any(
      (item) =>
          item.id != null &&
          item.response != null &&
          item.response != ChecklistResponse.na &&
          !item.isIdealAnswer,
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: checklistGradientAppBar(
        title: '${inspection.buildingCode} — ${inspection.dateIso}',
        leading: checklistBackButton(context),
        actions: [
          if (hasFailedItems && !inspection.isTerminal)
            IconButton(
              tooltip: widget.language == 'ar'
                  ? 'إنشاء إجراء تصحيحي'
                  : 'Create corrective action',
              onPressed: saving
                  ? null
                  : () async {
                      final created =
                          await _createCorrectiveActionForInspection(
                            context: context,
                            ref: ref,
                            inspection: inspection,
                            language: widget.language,
                          );
                      if (!created || !context.mounted) return;
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CorrectiveActionsScreen(
                            profile: widget.profile,
                            language: widget.language,
                            inspectionId: inspection.id,
                          ),
                        ),
                      );
                    },
              icon: const Icon(Icons.add_task_outlined),
            ),
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
                    if (action == null || !context.mounted) return;
                    final photoMode = await _pickReportPhotoMode(
                      context,
                      widget.language,
                    );
                    if (photoMode == null || !context.mounted) return;
                    try {
                      final exporter = InspectionReportExporter();
                      if (action == 'print') {
                        await exporter.print(
                          inspection,
                          language: widget.language,
                          photoMode: photoMode,
                        );
                      } else {
                        await exporter.export(
                          inspection,
                          language: widget.language,
                          photoMode: photoMode,
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              e is InspectionReportEvidenceException
                                  ? e.messageFor(widget.language)
                                  : '$e',
                            ),
                          ),
                        );
                      }
                    }
                  },
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
          if (canEdit)
            TextButton(
              onPressed: saving ? null : _save,
              child: Text(
                widget.language == 'ar' ? 'حفظ' : 'Save',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          if (!inspection.isSubmitted && _canWrite)
            TextButton(
              onPressed: saving ? null : _submit,
              child: Text(
                widget.language == 'ar' ? 'إرسال' : 'Submit',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          if (canApprove)
            IconButton(
              tooltip: widget.language == 'ar'
                  ? 'إعادة للتصحيح'
                  : 'Return for correction',
              onPressed: saving ? null : () => _decideWorkflow('return'),
              icon: const Icon(Icons.undo_outlined),
            ),
          if (canApprove)
            IconButton(
              tooltip: widget.language == 'ar' ? 'رفض' : 'Reject',
              onPressed: saving ? null : () => _decideWorkflow('reject'),
              icon: const Icon(Icons.cancel_outlined),
            ),
          if (canApprove)
            TextButton(
              onPressed: saving ? null : _approve,
              child: Text(
                widget.language == 'ar' ? 'اعتماد' : 'Approve',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          if (!inspection.isTerminal && widget.profile.isPlatformOwner)
            IconButton(
              tooltip: widget.language == 'ar' ? 'إلغاء الفحص' : 'Cancel',
              onPressed: saving ? null : _cancelWorkflow,
              icon: const Icon(Icons.block_outlined),
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
          if (inspection.workflowNote?.trim().isNotEmpty == true)
            _WorkflowNoteBanner(
              inspection: inspection,
              language: widget.language,
            ),
          Expanded(
            child: A4PaperSheet(
              child: ChecklistFormLayout(
                inspection: inspection,
                language: widget.language,
                forceTableLayout: true,
                readOnly: !canEdit,
                overdueItemIndexes: overdueIndexes,
                issueOpenTooltipsByPath: issueOpenTooltips,
                onInspectorChanged: (v) =>
                    setState(() => inspection.inspectorName = v),
                onTimeChanged: (v) =>
                    setState(() => inspection.inspectionTime = v),
                onFloorChanged: (v) =>
                    setState(() => inspection.floorLabel = v),
                onResponseChanged: (item, value) {
                  final err = item.trySetResponse(
                    value,
                    language: widget.language,
                  );
                  if (err != null && mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(err)));
                  }
                  setState(() {});
                },
                onActionsChanged: (item, value) =>
                    setState(() => item.actionsTaken = value),
                onPickIssuePhoto: canEdit
                    ? (item, [pairId]) =>
                          _pickPhoto(item, isIssue: true, pairId: pairId)
                    : null,
                onPickFixPhoto: canEdit
                    ? (item, [pairId]) =>
                          _pickPhoto(item, isIssue: false, pairId: pairId)
                    : null,
                onClearIssuePhoto: canEdit
                    ? (item, path, [pairId]) =>
                          _clearPhoto(item, path, isIssue: true, pairId: pairId)
                    : null,
                onClearFixPhoto: canEdit
                    ? (item, path, [pairId]) => _clearPhoto(
                        item,
                        path,
                        isIssue: false,
                        pairId: pairId,
                      )
                    : null,
                onAddItem: canManage ? _addCustomItem : null,
                onDeleteItem: canManage ? _deleteCustomItem : null,
                signatureController: canEdit ? _signature : null,
                signaturePreviewBytes: _signaturePreviewBytes,
                onClearSignature: canEdit
                    ? () {
                        _signature.clear();
                        final oldPath = inspection.signaturePath;
                        if (oldPath != null && oldPath.isNotEmpty) {
                          _pendingMediaDeletes.add(oldPath);
                        }
                        setState(() {
                          _signaturePreviewBytes = null;
                          inspection.signaturePath = null;
                        });
                      }
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
