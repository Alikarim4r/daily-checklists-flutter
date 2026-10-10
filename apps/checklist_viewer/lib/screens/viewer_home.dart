import 'dart:math' as math;
import 'dart:typed_data';

import 'package:checklist_shared/checklist_shared.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:signature/signature.dart';

import '../design/checkview_tokens.dart';
import '../design/checkview_errors.dart';
import '../design/checkview_widgets.dart';
import 'checkview_notices.dart';
import 'corrective_actions_screen.dart';
import 'inspection_dialogs.dart';
import 'inspection_form_page.dart';

const _attentionPreviewCount = 5;

enum _OwnerAction { correctDate, cancelInspection }

/// Inspections workspace: drill-down browse, records and (on wide screens)
/// the selected inspection beside the list.
class ViewerHome extends ConsumerStatefulWidget {
  const ViewerHome({
    super.key,
    required this.profile,
    required this.language,
    required this.onOpenSettings,
    this.active = true,
  });

  final Profile profile;
  final String language;
  final VoidCallback onOpenSettings;

  /// False while another shell destination is visible; gates back handling.
  final bool active;

  @override
  ConsumerState<ViewerHome> createState() => ViewerHomeState();
}

class ViewerHomeState extends ConsumerState<ViewerHome> {
  List<ChecklistSite> sites = [];
  List<CampusChecklistGroup> campusGroups = [];
  List<UserSiteAccess> myAccess = [];
  List<Inspection> records = [];
  String? siteFilter;

  /// Drill-down: org → zone → campus → checklist.
  OrgBrowseSection? browseOrg;
  ZoneBrowseSection? browseZone;
  CampusChecklistGroup? browseCampus;
  String? browseCategory;
  String? browseSubcategory;
  List<OrgBrowseSection> orgSections = [];
  List<LocationScopeLeaf> _locationLeaves = [];
  ChecklistFilterSelection topFilters = const ChecklistFilterSelection();
  ChecklistScopeFilters get _filterScope => ChecklistScopeFilters.fromSections(
    orgSections,
    locationLeaves: _locationLeaves,
  );
  List<OrgBrowseSection> get _filteredSections =>
      _filterScope.filteredSections(orgSections, topFilters);

  void _onTopFiltersChanged(ChecklistFilterSelection next) {
    final wasOnChecklist = siteFilter != null;
    setState(() {
      topFilters = next;
      browseOrg = null;
      browseZone = null;
      browseCampus = null;
      browseCategory = null;
      browseSubcategory = null;
      siteFilter = null;
      selected = null;
    });
    if (wasOnChecklist) _load();
  }

  DateTime date = qatarBusinessNow();
  Inspection? selected;
  Set<int> overdueIndexes = {};
  Map<String, String> issueOpenTooltips = {};
  bool loading = true;
  bool _loadedOnce = false;
  String? message;

  /// Non-error progress (for example report export).
  String? _status;
  bool _showAllAttention = false;

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
  bool get ar => language == 'ar';

  bool get _canNavBack =>
      browseOrg != null ||
      browseZone != null ||
      browseCampus != null ||
      browseCategory != null ||
      browseSubcategory != null ||
      siteFilter != null;

  String get _appBarTitle {
    if (siteFilter != null) {
      final site = sites.where((s) => s.id == siteFilter).firstOrNull;
      if (site != null) return site.buildingCode;
    }
    if (browseSubcategory != null) {
      return ChecklistSubcategories.title(browseSubcategory!, language);
    }
    if (browseCategory != null) {
      return ChecklistCategories.title(browseCategory!, language);
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
    return checkViewName;
  }

  String get _locationPath {
    final parts = <String>[
      if (browseOrg != null) browseOrg!.organization.nameFor(language),
      if (browseZone != null) browseZone!.titleFor(language),
      if (browseCampus != null) browseCampus!.titleFor(language),
      if (browseCategory != null)
        ChecklistCategories.title(browseCategory!, language),
      if (browseSubcategory != null)
        ChecklistSubcategories.title(browseSubcategory!, language),
      if (siteFilter != null)
        sites.where((s) => s.id == siteFilter).firstOrNull?.buildingCode ?? '',
    ].where((part) => part.trim().isNotEmpty).toList();
    if (parts.isEmpty) return ar ? 'كل المواقع' : 'All locations';
    return parts.join('  /  ');
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
    if (browseSubcategory != null) {
      setState(() {
        browseSubcategory = null;
        selected = null;
      });
      return;
    }
    if (browseCategory != null) {
      setState(() {
        browseCategory = null;
        browseSubcategory = null;
        selected = null;
      });
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
      browseCategory = null;
      browseSubcategory = null;
      siteFilter = null;
      selected = null;
    });
  }

  void _openZone(ZoneBrowseSection zone) {
    setState(() {
      browseZone = zone;
      browseCampus = null;
      browseCategory = null;
      browseSubcategory = null;
      siteFilter = null;
      selected = null;
    });
  }

  Future<void> _openCampus(CampusChecklistGroup group) async {
    setState(() {
      browseCampus = group;
      browseCategory = null;
      browseSubcategory = null;
      siteFilter = null;
      selected = null;
    });
    await _load();
  }

  void _openCategory(String category) {
    setState(() {
      browseCategory = category;
      browseSubcategory = null;
      selected = null;
    });
  }

  void _openSubcategory(String subcategory) {
    setState(() {
      browseSubcategory = subcategory;
      selected = null;
    });
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
          floorLabel: site.reportFloor,
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
  void didUpdateWidget(covariant ViewerHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Notices are localized when loaded.
    if (oldWidget.language != widget.language) _load();
  }

  @override
  void dispose() {
    _signature.dispose();
    super.dispose();
  }

  bool get _wide => MediaQuery.sizeOf(context).width >= CvBreakpoint.split;

  bool get _isReviewer => widget.profile.canReviewInspections;

  /// Writers and reviewers see the full workflow, viewers only approved.
  bool get _seesWorkflow => _isReviewer || _canWriteAnySiteFor(myAccess);

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

  /// Reloads the workspace (used by the shell when returning to this tab).
  Future<void> reload() => _load();

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
        ref
            .read(locationHierarchyRepositoryProvider)
            .listMyChecklistLocationScope()
            .then((s) => s.leaves)
            .catchError((_) => <LocationScopeLeaf>[]),
      ]);
      if (!mounted || generation != _loadGeneration) return;
      final groups = foundation[0] as List<CampusChecklistGroup>;
      final orgs = foundation[1] as List<Organization>;
      final allZones = foundation[2] as List<Zone>;
      final access = foundation[3] as List<UserSiteAccess>;
      final workflow = foundation[4] as List<WorkflowNotification>;
      final locationLeaves = foundation[5] as List<LocationScopeLeaf>;
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
        _locationLeaves = locationLeaves;
        campusGroups = groups;
        sites = siteList;
        // Refresh category grouping after an administrator reclassifies a list.
        if (browseCampus != null) {
          final previous = browseCampus!;
          browseCampus = groups
              .where(
                (g) => (previous.campus != null
                    ? g.campus?.id == previous.campus!.id
                    : g.campus == null &&
                          g.checklists.any(
                            (site) => previous.checklists.any(
                              (old) => old.id == site.id,
                            ),
                          )),
              )
              .firstOrNull;
          if (browseCampus == null ||
              (browseCategory != null &&
                  !ChecklistCategories.groupAvailable(
                    browseCampus!.checklists,
                  ).containsKey(browseCategory))) {
            browseCategory = null;
            browseSubcategory = null;
          }
        }
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
        setState(() => message = cvUserMessage(e, language));
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          loading = false;
          _loadedOnce = true;
        });
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

  /// Opens an inspection by id (from notices or the operations tab).
  Future<void> openInspectionById(String id) async {
    final match = records.where((r) => r.id == id).firstOrNull;
    if (match != null) {
      await _open(match);
      return;
    }
    final full = await ref.read(inspectionRepositoryProvider).getById(id);
    if (full != null && mounted) await _open(full);
  }

  Future<void> _openNotices() async {
    await showCheckViewNotices(
      context: context,
      notices: notices,
      language: language,
      onTap: (id) async {
        if (id == null) return;
        await openInspectionById(id);
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
      final full = row.items.isEmpty
          ? await ref.read(inspectionRepositoryProvider).getById(row.id)
          : row;
      if (full == null) throw Exception('Inspection not found');
      if (!mounted) return;
      final request = await showReportOptionsSheet(context, language);
      if (request == null || !mounted) return;
      setState(
        () => _status = ar ? 'جاري تجهيز التقرير…' : 'Preparing report…',
      );
      final exporter = InspectionReportExporter();
      if (request.delivery == ReportDelivery.print) {
        await exporter.print(
          full,
          language: language,
          photoMode: request.photoMode,
        );
      } else {
        await exporter.export(
          full,
          language: language,
          photoMode: request.photoMode,
        );
      }
      if (mounted) {
        setState(() => _status = ar ? 'تم تجهيز التقرير' : 'Report ready');
      }
    } catch (e, stack) {
      await StructuredErrorReporter.capture(
        e,
        stack,
        module: 'viewer.inspection_report',
      );
      if (mounted) {
        setState(() {
          _status = null;
          message = e is InspectionReportEvidenceException
              ? e.messageFor(language)
              : e.toString();
        });
      }
    }
  }

  Future<void> _open(Inspection row) async {
    if (openingInspectionId != null) return;
    if (mounted) setState(() => openingInspectionId = row.id);
    try {
      final full = row.items.isNotEmpty
          ? row
          : await ref.read(inspectionRepositoryProvider).getById(row.id);
      if (!mounted) return;
      if (full == null) {
        setState(
          () => message = ar ? 'تعذر فتح السجل' : 'Could not open record',
        );
        return;
      }
      // Approved for all; drafts/submitted only for writers or reviewers.
      if (full.reviewStatus != ReviewStatus.approved) {
        final allowed = _isReviewer || _canWriteSite(full.siteId);
        if (!allowed) {
          setState(
            () => message = ar
                ? 'هذا الفحص غير معتمد للعرض بعد'
                : 'This inspection is not approved for viewing yet',
          );
          return;
        }
      }
      _signature.clear();
      setState(() => _signaturePreviewBytes = null);
      if (!_wide) {
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
      setState(() => selected = full);
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
        title: Text(ar ? 'صورة المشكلة ناقصة' : 'Issue photo missing'),
        content: Text(result.messageFor(language)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(ar ? 'إكمال الصور' : 'Add photos'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(ar ? 'متابعة' : 'Continue'),
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
          SnackBar(content: Text(ar ? 'تم حفظ التعديلات' : 'Changes saved')),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) setState(() => message = cvUserMessage(e, language));
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
        title: Text(ar ? 'إرسال التقرير' : 'Submit report'),
        content: Text(
          ar
              ? 'تأكيد إرسال سجل الفحص؟ سيُراجع قبل ظهوره للعارض.'
              : 'Submit this inspection for review?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(ar ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(ar ? 'إرسال' : 'Submit'),
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
      if (mounted) setState(() => message = cvUserMessage(e, language));
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
              ar ? 'تم اعتماد الفحص للعرض' : 'Inspection approved for viewing',
            ),
          ),
        );
      }
      await _load();
      final full = await ref
          .read(inspectionRepositoryProvider)
          .getById(current.id);
      if (full != null && mounted) {
        setState(() => selected = full);
        await _refreshOverdue(full);
      }
    } catch (e) {
      if (mounted) setState(() => message = cvUserMessage(e, language));
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
    final reason = await requestWorkflowReason(
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
      if (mounted) setState(() => message = cvUserMessage(exception, language));
    }
  }

  Future<void> _cancelSelectedWorkflow() async {
    final current = selected;
    if (current == null ||
        current.isTerminal ||
        !widget.profile.isPlatformOwner) {
      return;
    }
    final reason = await requestWorkflowReason(
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
      if (mounted) setState(() => message = cvUserMessage(exception, language));
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
          title: Text(ar ? 'تصحيح تاريخ الفحص' : 'Correct inspection date'),
          scrollable: true,
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
                  labelText: ar
                      ? 'سبب التصحيح (إلزامي)'
                      : 'Correction reason (required)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(ar ? 'إلغاء' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, reason.text.trim().isNotEmpty),
              child: Text(ar ? 'حفظ التصحيح' : 'Save correction'),
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
      if (mounted) setState(() => message = cvUserMessage(error, language));
    } finally {
      reason.dispose();
    }
  }

  Future<void> _createCorrectiveActionForSelected() async {
    final current = selected;
    if (current == null) return;
    final created = await createCorrectiveActionForInspection(
      context: context,
      ref: ref,
      inspection: current,
      language: language,
    );
    if (!created || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CorrectiveActionsScreen(
          profile: widget.profile,
          language: language,
          inspectionId: current.id,
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = qatarBusinessNow();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: date.isAfter(today) ? today : date,
      firstDate: DateTime(2024),
      lastDate: today,
    );
    if (picked == null || !mounted) return;
    setState(() => date = picked);
    await _load();
  }

  String _listModeLabel(int mode) => switch (mode) {
    1 => ar ? 'بانتظار الاعتماد' : 'Awaiting approval',
    2 => ar ? 'المعتمدة' : 'Approved',
    _ => ar ? 'كل الحالات' : 'All states',
  };

  Future<void> _pickListMode() async {
    final picked = await showCvChoiceSheet<int>(
      context: context,
      title: ar ? 'عرض الفحوصات' : 'Show inspections',
      selected: listMode,
      choices: [
        for (final mode in const [0, 1, 2])
          CvChoice(value: mode, label: _listModeLabel(mode)),
      ],
    );
    if (picked == null || picked == listMode || !mounted) return;
    setState(() => listMode = picked);
    await _load();
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
            kindLabel: ar
                ? (isIssue ? 'مشكلة' : 'إصلاح')
                : (isIssue ? 'Issue' : 'Repair'),
            sourceLabel: ar ? 'المعرض' : 'Gallery',
            organizationIdFallback: current.organizationId,
            siteNameFallback: current.siteNameEn.isNotEmpty
                ? current.siteNameEn
                : current.buildingCode,
          );
      final stamped = await InspectionPhotoWatermark().apply(
        imageBytes: bytes,
        context: photoCtx,
        arabic: ar,
      );
      final orgId = _resolveOrgId(current);
      if (orgId.isEmpty) {
        throw Exception(
          ar
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
      if (!mounted) return;
      setState(() {
        if (isIssue) {
          item.appendIssueImage(path);
        } else {
          item.appendFixImage(path, pairId: pairId);
        }
      });
      await ref.read(inspectionRepositoryProvider).saveItems(current);
    } catch (e) {
      if (mounted) setState(() => message = cvUserMessage(e, language));
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ar ? 'حذف البند؟' : 'Delete item?'),
        content: Text(
          ar
              ? 'سيتم حذف البند المخصص رقم ${item.itemIndex}.'
              : 'Custom item ${item.itemIndex} will be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ar ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
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
      if (!mounted) return;
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ar ? 'تم حذف البند' : 'Item deleted')),
      );
    } catch (e) {
      if (mounted) setState(() => message = cvUserMessage(e, language));
    }
  }

  Future<void> _addCustomItem() async {
    final current = selected;
    if (current == null || !_canManageSelected()) return;
    final en = TextEditingController();
    final arCtrl = TextEditingController();
    var def = 'Y';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(ar ? 'إضافة بند' : 'Add item'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: en,
                decoration: InputDecoration(
                  labelText: ar ? 'الوصف (EN)' : 'Description (EN)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: arCtrl,
                decoration: InputDecoration(
                  labelText: ar ? 'الوصف (AR)' : 'Description (AR)',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: def,
                decoration: InputDecoration(
                  labelText: ar ? 'الإجابة المثالية' : 'Ideal answer',
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
    final desc = en.text.trim().isNotEmpty
        ? en.text.trim()
        : arCtrl.text.trim();
    if (desc.isEmpty) return;
    final nextIndex = current.items.isEmpty
        ? 1
        : current.items.map((e) => e.itemIndex).reduce(math.max) + 1;
    final item = InspectionItem(
      itemIndex: nextIndex,
      description: en.text.trim().isNotEmpty ? en.text.trim() : desc,
      descriptionAr: arCtrl.text.trim().isEmpty ? null : arCtrl.text.trim(),
      defaultAnswer: def,
      isCustom: true,
    );
    if (!mounted) return;
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

  // -------------------------------------------------------------------------
  // Presentation
  // -------------------------------------------------------------------------

  String get _dateIso => DateFormat('yyyy-MM-dd').format(date);

  CvTitleBlock _contextBlock() {
    return CvTitleBlock(
      loading: loading,
      fields: [
        CvTitleField(
          label: ar ? 'الموقع' : 'Location',
          value: _locationPath,
          flex: 3,
          maxLines: 2,
        ),
        CvTitleField(
          label: ar ? 'تاريخ الفحص' : 'Inspection date',
          value: _dateIso,
          onTap: _pickDate,
          flex: 2,
        ),
        if (_isReviewer)
          CvTitleField(
            label: ar ? 'العرض' : 'Showing',
            value: _listModeLabel(listMode),
            onTap: _pickListMode,
            flex: 2,
          ),
      ],
    );
  }

  String _siteName(Inspection r) {
    final name = ar && r.siteNameAr.trim().isNotEmpty
        ? r.siteNameAr
        : r.siteNameEn;
    return name.trim();
  }

  Widget _recordRow(Inspection r) {
    final c = CheckViewColors.of(context);
    final issues = r.items.where((item) => item.isProblem).length;
    final inspector = r.inspectorName.trim();
    final time = r.inspectionTime.trim();
    return CvLedgerRow(
      key: ValueKey(r.id),
      title: r.buildingCode,
      subtitle: _siteName(r),
      selected: selected?.id == r.id,
      busy: openingInspectionId == r.id,
      onTap: () => _open(r),
      meta: [
        CvStatusMark(
          label: r.reviewStatus.labelFor(language),
          tone: cvReviewTone(r.reviewStatus),
        ),
        if (issues > 0)
          CvMeta(
            ar ? '$issues ملاحظات' : '$issues issues',
            icon: Icons.report_problem_outlined,
            color: c.returned,
          ),
        if (inspector.isNotEmpty) CvMeta(inspector, icon: Icons.person_outline),
        if (time.isNotEmpty) CvMeta(time, icon: Icons.schedule_outlined),
        if (r.dateIso != _dateIso)
          CvMeta(r.dateIso, icon: Icons.event_outlined),
      ],
    );
  }

  static const _firstHeaderPadding = EdgeInsets.fromLTRB(
    4,
    CvSpace.lg,
    4,
    CvSpace.sm,
  );

  List<Widget> _rootSections() {
    int count(ReviewStatus status) =>
        records.where((r) => r.reviewStatus == status).length;
    final attention =
        records.where((r) => r.awaitingReview || r.isReturned).toList()..sort(
          (a, b) => a.awaitingReview == b.awaitingReview
              ? 0
              : (a.awaitingReview ? -1 : 1),
        );
    final visibleAttention = _showAllAttention
        ? attention
        : attention.take(_attentionPreviewCount).toList();

    return [
      CvSectionHeader(
        title: ar ? 'الحالة في هذا التاريخ' : 'State on this date',
        padding: _firstHeaderPadding,
      ),
      CvTally(
        items: _seesWorkflow
            ? [
                for (final status in const [
                  ReviewStatus.approved,
                  ReviewStatus.submitted,
                  ReviewStatus.returned,
                  ReviewStatus.draft,
                ])
                  CvTallyItem(
                    label: status.labelFor(language),
                    count: count(status),
                    tone: cvReviewTone(status),
                  ),
              ]
            : [
                CvTallyItem(
                  label: ar ? 'فحوصات معتمدة' : 'Approved inspections',
                  count: count(ReviewStatus.approved),
                  tone: CvTone.approved,
                ),
                CvTallyItem(
                  label: ar ? 'مواقع متاحة' : 'Accessible sites',
                  count: campusGroups.length,
                ),
              ],
      ),
      if (attention.isNotEmpty) ...[
        CvSectionHeader(
          title: ar ? 'يحتاج إلى إجراء' : 'Needs attention',
          count: attention.length,
        ),
        CvLedger(
          children: [
            for (final r in visibleAttention) _recordRow(r),
            if (attention.length > _attentionPreviewCount)
              TextButton(
                onPressed: () =>
                    setState(() => _showAllAttention = !_showAllAttention),
                child: Text(
                  _showAllAttention
                      ? (ar ? 'عرض أقل' : 'Show fewer')
                      : (ar
                            ? 'عرض الكل (${attention.length})'
                            : 'Show all ${attention.length}'),
                ),
              ),
          ],
        ),
      ],
      CvSectionHeader(
        title: ar ? 'المواقع' : 'Locations',
        count: _filteredSections.length,
      ),
      if (_filteredSections.isEmpty)
        CvEmptyState(
          icon: Icons.location_city_outlined,
          title: ar ? 'لا توجد مواقع' : 'No locations yet',
          message: ar
              ? 'تظهر المواقع هنا بعد أن يمنحك المسؤول صلاحية الوصول.'
              : 'Locations appear here once an administrator grants access.',
        )
      else
        CvLedger(
          children: [
            for (final org in _filteredSections)
              CvLedgerRow(
                title: org.organization.nameFor(language),
                onTap: () => _openOrg(org),
                meta: [
                  CvMeta(
                    ar
                        ? '${org.zones.length} مناطق'
                        : '${org.zones.length} zones',
                  ),
                  CvMeta(
                    ar
                        ? '${org.campusCount} مواقع'
                        : '${org.campusCount} sites',
                  ),
                ],
              ),
          ],
        ),
    ];
  }

  /// "3 of 5 recorded" for a campus on the selected date.
  Widget? _coverageMeta(Iterable<ChecklistSite> checklists) {
    if (listMode != 0) return null;
    final ids = {for (final site in checklists) site.id};
    final recorded = records.where((r) => ids.contains(r.siteId)).length;
    return CvMeta(
      ar
          ? '$recorded من ${ids.length} مسجلة'
          : '$recorded of ${ids.length} recorded',
      icon: Icons.fact_check_outlined,
    );
  }

  List<Widget> _zoneSections(OrgBrowseSection org) => [
    CvSectionHeader(
      title: ar ? 'المناطق' : 'Zones',
      count: org.zones.length,
      padding: _firstHeaderPadding,
    ),
    CvLedger(
      children: [
        for (final zone in org.zones)
          CvLedgerRow(
            title: zone.titleFor(language),
            onTap: () => _openZone(zone),
            meta: [
              CvMeta(
                ar
                    ? '${zone.groups.length} مواقع'
                    : '${zone.groups.length} sites',
              ),
            ],
          ),
      ],
    ),
  ];

  List<Widget> _campusSections(ZoneBrowseSection zone) => [
    CvSectionHeader(
      title: ar ? 'المواقع' : 'Sites',
      count: zone.groups.length,
      padding: _firstHeaderPadding,
    ),
    CvLedger(
      children: [
        for (final group in zone.groups)
          CvLedgerRow(
            title: group.titleFor(language),
            onTap: () => _openCampus(group),
            meta: [
              CvMeta(
                ar
                    ? '${group.checklists.length} قوائم فحص'
                    : '${group.checklists.length} checklists',
              ),
              ?_coverageMeta(group.checklists),
            ],
          ),
      ],
    ),
  ];

  Widget _checklistRow(ChecklistSite site) {
    final record = records.where((r) => r.siteId == site.id).firstOrNull;
    return CvLedgerRow(
      title: site.nameFor(language),
      onTap: () => _openChecklist(site),
      meta: [
        CvMeta(site.buildingCode),
        if (site.checklistType.trim().isNotEmpty) CvMeta(site.checklistType),
        if (record != null)
          CvStatusMark(
            label: record.reviewStatus.labelFor(language),
            tone: cvReviewTone(record.reviewStatus),
          )
        else if (listMode == 0)
          CvMeta(ar ? 'لا يوجد سجل' : 'No record'),
      ],
    );
  }

  List<Widget> _categorySections(CampusChecklistGroup group) {
    final categories = ChecklistCategories.groupAvailable(group.checklists);
    return [
      CvSectionHeader(
        title: ar ? 'أصناف قوائم الفحص' : 'Checklist categories',
        count: categories.length,
        padding: _firstHeaderPadding,
      ),
      if (categories.isEmpty)
        CvEmptyState(
          icon: Icons.folder_off_outlined,
          title: ar ? 'لا توجد قوائم فحص' : 'No checklists',
          message: ar
              ? 'لم تُضف بعد قائمة فحص إلى هذا الموقع.'
              : 'No checklists have been assigned to this site.',
        )
      else
        CvLedger(
          children: [
            for (final entry in categories.entries)
              CvLedgerRow(
                title: ChecklistCategories.title(entry.key, language),
                subtitle: ar
                    ? '${entry.value.length} قوائم'
                    : '${entry.value.length} checklists',
                onTap: () => _openCategory(entry.key),
                meta: [?_coverageMeta(entry.value)],
              ),
          ],
        ),
    ];
  }

  List<Widget> _checklistSections(CampusChecklistGroup group) {
    final category = browseCategory;
    if (category == null) return _categorySections(group);
    final units =
        ChecklistCategories.groupAvailable(group.checklists)[category] ??
        const <ChecklistSite>[];
    // Facilities contains the requested Toilet Checklists subfolder.
    // Cleaning lists remain directly in their Cleaning category.
    if (category == 'facilities') {
      final grouped = ChecklistSubcategories.available(units);
      if (browseSubcategory == null) {
        return [
          CvSectionHeader(
            title: ChecklistCategories.title(category, language),
            count: grouped.length,
            padding: _firstHeaderPadding,
          ),
          CvLedger(
            children: [
              for (final group in grouped.entries)
                if (group.key.isNotEmpty)
                  CvLedgerRow(
                    title: ChecklistSubcategories.title(group.key, language),
                    subtitle: ar
                        ? '${group.value.length} قوائم'
                        : '${group.value.length} checklists',
                    onTap: () => _openSubcategory(group.key),
                  )
                else
                  for (final site in group.value) _checklistRow(site),
            ],
          ),
        ];
      }
      final childUnits = grouped[browseSubcategory] ?? const <ChecklistSite>[];
      return [
        CvSectionHeader(
          title: ChecklistSubcategories.title(browseSubcategory!, language),
          count: childUnits.length,
          padding: _firstHeaderPadding,
        ),
        CvLedger(
          children: [for (final site in childUnits) _checklistRow(site)],
        ),
      ];
    }
    return [
      CvSectionHeader(
        title: ChecklistCategories.title(category, language),
        count: units.length,
        padding: _firstHeaderPadding,
      ),
      CvLedger(children: [for (final site in units) _checklistRow(site)]),
    ];
  }

  List<Widget> _recordSections() {
    if (records.isEmpty) {
      return [
        CvEmptyState(
          icon: Icons.event_busy_outlined,
          title: ar
              ? 'لا توجد سجلات فحص في هذا التاريخ'
              : 'No inspection records on this date',
          message: ar
              ? 'اختر تاريخًا آخر لمراجعة الفحوصات السابقة.'
              : 'Choose another date to review earlier inspections.',
          action: OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
            label: Text(ar ? 'اختيار التاريخ' : 'Choose date'),
          ),
        ),
      ];
    }
    return [
      CvSectionHeader(
        title: ar ? 'السجلات' : 'Records',
        count: records.length,
        padding: _firstHeaderPadding,
      ),
      CvLedger(children: [for (final r in records) _recordRow(r)]),
    ];
  }

  Widget _browsePane() {
    if (!_loadedOnce) {
      return ListView(
        padding: const EdgeInsets.all(CvSpace.gutter),
        children: const [CvSkeletonLedger()],
      );
    }
    final List<Widget> sections;
    if (siteFilter != null) {
      sections = _recordSections();
    } else if (browseCampus != null) {
      sections = _checklistSections(browseCampus!);
    } else if (browseZone != null) {
      sections = _campusSections(browseZone!);
    } else if (browseOrg != null) {
      sections = _zoneSections(browseOrg!);
    } else {
      sections = _rootSections();
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: AnimatedOpacity(
        // Stale content stays readable but visibly yields while refreshing.
        opacity: loading ? 0.55 : 1,
        duration: CvMotion.of(context, CvMotion.quick),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            CvSpace.gutter,
            0,
            CvSpace.gutter,
            CvSpace.xxl,
          ),
          children: sections,
        ),
      ),
    );
  }

  Widget _detailToolbar(Inspection insp, {bool inAppBar = false}) {
    final canEdit = _canEditSelected;
    final canApprove =
        insp.awaitingReview && _isReviewer && _canManageSelected();
    final canSubmitDraft = !insp.isSubmitted && _canWriteSelected();
    final canCreateAction =
        !insp.isTerminal && failedInspectionItems(insp).isNotEmpty;
    final isOwner = !insp.isTerminal && widget.profile.isPlatformOwner;
    return Padding(
      padding: inAppBar
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(
              CvSpace.gutter,
              CvSpace.md,
              CvSpace.gutter,
              0,
            ),
      child: Wrap(
        spacing: CvSpace.sm,
        runSpacing: CvSpace.sm,
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: _exportSelected,
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: Text(ar ? 'تقرير PDF' : 'PDF report'),
          ),
          if (canCreateAction)
            OutlinedButton.icon(
              onPressed: _createCorrectiveActionForSelected,
              icon: const Icon(Icons.add_task_outlined, size: 18),
              label: Text(ar ? 'إجراء تصحيحي' : 'Corrective action'),
            ),
          if (isOwner)
            PopupMenuButton<_OwnerAction>(
              tooltip: ar ? 'إجراءات المالك' : 'Owner actions',
              icon: const Icon(Icons.more_horiz),
              onSelected: (action) => switch (action) {
                _OwnerAction.correctDate => _changeSelectedDateAsOwner(),
                _OwnerAction.cancelInspection => _cancelSelectedWorkflow(),
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _OwnerAction.correctDate,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.edit_calendar_outlined),
                    title: Text(ar ? 'تصحيح التاريخ' : 'Correct date'),
                  ),
                ),
                PopupMenuItem(
                  value: _OwnerAction.cancelInspection,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.block_outlined),
                    title: Text(ar ? 'إلغاء الفحص' : 'Cancel inspection'),
                  ),
                ),
              ],
            ),
          if (canEdit && !canSubmitDraft && !canApprove)
            FilledButton(
              onPressed: _save,
              child: Text(ar ? 'حفظ التعديلات' : 'Save changes'),
            ),
          if (canEdit && (canSubmitDraft || canApprove))
            OutlinedButton(onPressed: _save, child: Text(ar ? 'حفظ' : 'Save')),
          if (canSubmitDraft)
            FilledButton(
              onPressed: _submit,
              child: Text(ar ? 'إرسال للاعتماد' : 'Submit for review'),
            ),
          if (canApprove) ...[
            OutlinedButton(
              onPressed: () => _decideSelectedWorkflow('return'),
              child: Text(ar ? 'إعادة للتصحيح' : 'Return'),
            ),
            OutlinedButton(
              onPressed: () => _decideSelectedWorkflow('reject'),
              child: Text(ar ? 'رفض' : 'Reject'),
            ),
            FilledButton(
              onPressed: _approve,
              child: Text(ar ? 'اعتماد للعرض' : 'Approve for view'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detailPane() {
    final insp = selected;
    if (insp == null) {
      return CvEmptyState(
        icon: Icons.description_outlined,
        title: ar ? 'اختر فحصًا' : 'Select an inspection',
        message: ar
            ? 'يظهر هنا نموذج A4 وإجراءات المراجعة وتقرير PDF.'
            : 'Its A4 form, review actions and PDF report appear here.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Remove the redundant selected-site/date/inspector/status strip.
        // Keep the original A4 paper and its own header unchanged.
        if (!_toolbarInAppBar) _detailToolbar(insp),
        if (insp.workflowNote?.trim().isNotEmpty == true)
          InspectionWorkflowNote(inspection: insp, language: language),
        Expanded(child: _formPane()),
      ],
    );
  }

  Widget _formPane() {
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
        onLocationChanged: (v) => setState(() => selected!.locationLabel = v),
        onPinChanged: (v) => setState(() {
          selected!.pin = v;
          selected!.pinOverride = v;
        }),
        onBuildingNoChanged: (v) => setState(() => selected!.buildingCode = v),
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

  Widget _brandMark() {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: CvSpace.gutter),
      child: Center(
        child: ExcludeSemantics(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              'assets/branding/app_icon_simple.png',
              width: 30,
              height: 30,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.square(dimension: 30),
            ),
          ),
        ),
      ),
    );
  }

  bool get _toolbarInAppBar =>
      _wide && MediaQuery.sizeOf(context).width >= 1260;

  @override
  Widget build(BuildContext context) {
    final wide = _wide;
    final canNavBack = _canNavBack;
    return PopScope(
      canPop: !(widget.active && canNavBack),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.active && _canNavBack) _navBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: canNavBack
              ? IconButton(
                  icon: const BackButtonIcon(),
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: _navBack,
                )
              : _brandMark(),
          leadingWidth: canNavBack ? null : 30 + CvSpace.gutter,
          titleSpacing: canNavBack ? 0 : CvSpace.md,
          title: Text(
            _appBarTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (_toolbarInAppBar && selected != null)
              _detailToolbar(selected!, inAppBar: true),
            if (ref.watch(notificationsEnabledProvider))
              CvNoticeBell(
                count: notices.length,
                language: language,
                onOpen: _openNotices,
              ),
            IconButton(
              tooltip: ar ? 'تحديث' : 'Refresh',
              onPressed: loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
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
            ChecklistScopeFilterBar(
              scope: _filterScope,
              selection: topFilters,
              language: language,
              onChanged: _onTopFiltersChanged,
            ),
            _contextBlock(),
            if (message != null)
              CvBanner(
                tone: CvBannerTone.error,
                message: message!,
                onDismiss: () => setState(() => message = null),
              ),
            if (_status != null)
              CvBanner(
                message: _status!,
                onDismiss: () => setState(() => _status = null),
              ),
            Expanded(
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 380, child: _browsePane()),
                        const VerticalDivider(width: 1),
                        Expanded(child: _detailPane()),
                      ],
                    )
                  : _browsePane(),
            ),
          ],
        ),
      ),
    );
  }
}
