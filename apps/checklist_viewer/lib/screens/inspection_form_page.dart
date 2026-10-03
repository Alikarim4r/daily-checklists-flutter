import 'dart:math' as math;
import 'dart:typed_data';

import 'package:checklist_shared/checklist_shared.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:signature/signature.dart';

import '../design/checkview_errors.dart';
import '../design/checkview_widgets.dart';
import 'corrective_actions_screen.dart';
import 'inspection_dialogs.dart';

enum _FormMenuAction { createCorrectiveAction, save, cancelInspection }

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
  bool exporting = false;
  final SignatureController _signature = SignatureController(
    penStrokeWidth: 2.4,
    penColor: kSignatureInkColor,
    exportBackgroundColor: Colors.white,
    exportPenColor: kSignatureInkColor,
  );
  Uint8List? _signaturePreviewBytes;
  final Set<String> _pendingMediaDeletes = {};

  bool get ar => widget.language == 'ar';

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
        title: Text(ar ? 'صورة المشكلة ناقصة' : 'Issue photo missing'),
        content: Text(result.messageFor(widget.language)),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(ar ? 'تم الحفظ' : 'Saved')));
      }
    } catch (e) {
      if (mounted) setState(() => message = cvUserMessage(e, widget.language));
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
        title: Text(ar ? 'إرسال التقرير' : 'Submit report'),
        content: Text(
          ar ? 'تأكيد إرسال سجل الفحص؟' : 'Submit this inspection for review?',
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
    if (ok != true || !mounted) return;
    setState(() => saving = true);
    try {
      await _persistSignatureIfNeeded();
      await ref.read(inspectionRepositoryProvider).saveItems(inspection);
      await ref.read(inspectionRepositoryProvider).submit(inspection);
      final full = await ref
          .read(inspectionRepositoryProvider)
          .getById(inspection.id);
      if (full != null && mounted) setState(() => inspection = full);
      await widget.onChanged();
    } catch (e) {
      if (mounted) setState(() => message = cvUserMessage(e, widget.language));
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
      if (full != null && mounted) setState(() => inspection = full);
      await widget.onChanged();
      await ChecklistFeedback.success(
        soundEnabled: ref.read(soundEnabledProvider),
        hapticsEnabled: ref.read(hapticsEnabledProvider),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ar ? 'تم الاعتماد' : 'Approved')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => message = cvUserMessage(e, widget.language));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _decideWorkflow(String action) async {
    if (!inspection.awaitingReview || !_isReviewer || !_canManage) return;
    final reason = await requestWorkflowReason(
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
      if (mounted) {
        setState(() => message = cvUserMessage(exception, widget.language));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _cancelWorkflow() async {
    if (inspection.isTerminal || !widget.profile.isPlatformOwner) return;
    final reason = await requestWorkflowReason(
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
      if (mounted) {
        setState(() => message = cvUserMessage(exception, widget.language));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _exportReport() async {
    final request = await showReportOptionsSheet(context, widget.language);
    if (request == null || !mounted) return;
    setState(() => exporting = true);
    try {
      final exporter = InspectionReportExporter();
      if (request.delivery == ReportDelivery.print) {
        await exporter.print(
          inspection,
          language: widget.language,
          photoMode: request.photoMode,
        );
      } else {
        await exporter.export(
          inspection,
          language: widget.language,
          photoMode: request.photoMode,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is InspectionReportEvidenceException
                  ? e.messageFor(widget.language)
                  : cvUserMessage(e, widget.language),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  Future<void> _createCorrectiveAction() async {
    final created = await createCorrectiveActionForInspection(
      context: context,
      ref: ref,
      inspection: inspection,
      language: widget.language,
    );
    if (!created || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CorrectiveActionsScreen(
          profile: widget.profile,
          language: widget.language,
          inspectionId: inspection.id,
        ),
      ),
    );
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
            siteId: inspection.siteId,
            inspectionId: inspection.id,
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
      await ref.read(inspectionRepositoryProvider).saveItems(inspection);
    } catch (e) {
      if (mounted) setState(() => message = cvUserMessage(e, widget.language));
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
            .deleteInspectionItem(inspection, item.id!);
      }
      if (!mounted) return;
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
      if (mounted) setState(() => message = cvUserMessage(e, widget.language));
    }
  }

  Future<void> _addCustomItem() async {
    if (!_canManage) return;
    final draft = await requestCustomItem(context, language: widget.language);
    if (draft == null) return;
    final desc = draft.descriptionEn.isNotEmpty
        ? draft.descriptionEn
        : draft.descriptionAr;
    if (desc.isEmpty) return;
    final nextIndex = inspection.items.isEmpty
        ? 1
        : inspection.items.map((e) => e.itemIndex).reduce(math.max) + 1;
    final item = InspectionItem(
      itemIndex: nextIndex,
      description: desc,
      descriptionAr: draft.descriptionAr.isEmpty ? null : draft.descriptionAr,
      defaultAnswer: draft.defaultAnswer,
      isCustom: true,
    );
    if (!mounted) return;
    setState(() => inspection.items.add(item));
    await ref.read(inspectionRepositoryProvider).saveItems(inspection);
    final full = await ref
        .read(inspectionRepositoryProvider)
        .getById(inspection.id);
    if (full != null && mounted) setState(() => inspection = full);
    await widget.onChanged();
  }

  Widget? _actionBar({
    required bool canEdit,
    required bool canSubmit,
    required bool canApprove,
    required bool busy,
  }) {
    final actions = <CvAction>[
      if (canApprove) ...[
        CvAction(
          label: ar ? 'إعادة' : 'Return',
          onPressed: busy ? null : () => _decideWorkflow('return'),
        ),
        CvAction(
          label: ar ? 'رفض' : 'Reject',
          onPressed: busy ? null : () => _decideWorkflow('reject'),
        ),
        CvAction(
          label: ar ? 'اعتماد' : 'Approve',
          primary: true,
          onPressed: busy ? null : _approve,
        ),
      ] else if (canSubmit) ...[
        if (canEdit)
          CvAction(label: ar ? 'حفظ' : 'Save', onPressed: busy ? null : _save),
        CvAction(
          label: ar ? 'إرسال للاعتماد' : 'Submit for review',
          primary: true,
          onPressed: busy ? null : _submit,
        ),
      ] else if (canEdit)
        CvAction(
          label: ar ? 'حفظ التعديلات' : 'Save changes',
          primary: true,
          onPressed: busy ? null : _save,
        ),
    ];
    return actions.isEmpty ? null : CvActionBar(actions: actions);
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = _canEdit;
    final canManage = _canManage;
    final canApprove = inspection.awaitingReview && _isReviewer && _canManage;
    final canSubmit = !inspection.isSubmitted && _canWrite;
    final canCreateAction =
        !inspection.isTerminal && failedInspectionItems(inspection).isNotEmpty;
    final canCancel = !inspection.isTerminal && widget.profile.isPlatformOwner;
    final busy = saving || exporting;
    final compactHeader =
        MediaQuery.viewInsetsOf(context).bottom > 0 ||
        MediaQuery.sizeOf(context).height < 560;
    final menu = <PopupMenuEntry<_FormMenuAction>>[
      if (canCreateAction)
        PopupMenuItem(
          value: _FormMenuAction.createCorrectiveAction,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.add_task_outlined),
            title: Text(ar ? 'إنشاء إجراء تصحيحي' : 'Create corrective action'),
          ),
        ),
      if (canApprove && canEdit)
        PopupMenuItem(
          value: _FormMenuAction.save,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.save_outlined),
            title: Text(ar ? 'حفظ التعديلات' : 'Save changes'),
          ),
        ),
      if (canCancel)
        PopupMenuItem(
          value: _FormMenuAction.cancelInspection,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.block_outlined),
            title: Text(ar ? 'إلغاء الفحص' : 'Cancel inspection'),
          ),
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          inspection.buildingCode,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: ar ? 'تقرير PDF' : 'PDF report',
            onPressed: busy ? null : _exportReport,
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
          if (menu.isNotEmpty)
            PopupMenuButton<_FormMenuAction>(
              tooltip: ar ? 'إجراءات أخرى' : 'More actions',
              enabled: !busy,
              icon: const Icon(Icons.more_vert),
              itemBuilder: (_) => menu,
              onSelected: (action) => switch (action) {
                _FormMenuAction.createCorrectiveAction =>
                  _createCorrectiveAction(),
                _FormMenuAction.save => _save(),
                _FormMenuAction.cancelInspection => _cancelWorkflow(),
              },
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Keep the form usable with the keyboard open or on short screens.
          if (compactHeader)
            CvDatumLine(loading: busy)
          else
            inspectionTitleBlock(
              inspection: inspection,
              language: widget.language,
              loading: busy,
            ),
          if (message != null)
            CvBanner(
              tone: CvBannerTone.error,
              message: message!,
              onDismiss: () => setState(() => message = null),
            ),
          if (inspection.workflowNote?.trim().isNotEmpty == true)
            InspectionWorkflowNote(
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
      bottomNavigationBar: _actionBar(
        canEdit: canEdit,
        canSubmit: canSubmit,
        canApprove: canApprove,
        busy: busy,
      ),
    );
  }
}
