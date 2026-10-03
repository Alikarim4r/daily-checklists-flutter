import 'dart:typed_data';

import 'package:checklist_shared/checklist_shared.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../design/checkview_errors.dart';
import '../design/checkview_tokens.dart';
import '../design/checkview_widgets.dart';

class CorrectiveActionsScreen extends ConsumerStatefulWidget {
  const CorrectiveActionsScreen({
    super.key,
    required this.profile,
    required this.language,
    this.inspectionId,
    this.onOpenSettings,
  });

  final Profile profile;
  final String language;
  final String? inspectionId;

  /// Shown as a settings action when hosted in the CheckView shell.
  final VoidCallback? onOpenSettings;

  @override
  ConsumerState<CorrectiveActionsScreen> createState() =>
      _CorrectiveActionsScreenState();
}

class _CorrectiveActionsScreenState
    extends ConsumerState<CorrectiveActionsScreen> {
  final searchController = TextEditingController();
  List<CorrectiveAction> actions = const [];
  CorrectiveActionStatus? statusFilter;
  CorrectiveActionPriority? priorityFilter;
  bool loading = true;
  bool _loadedOnce = false;
  String? error;
  String? _busyActionId;

  bool get ar => widget.language == 'ar';
  bool get canManage =>
      widget.profile.isPlatformOwner || widget.profile.role.isElevatedAdmin;

  bool get _hasFilters =>
      statusFilter != null ||
      priorityFilter != null ||
      searchController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final rows = await ref
          .read(correctiveActionRepositoryProvider)
          .list(
            inspectionId: widget.inspectionId,
            status: statusFilter,
            priority: priorityFilter,
          );
      if (mounted) setState(() => actions = rows);
    } catch (exception) {
      if (mounted) {
        setState(() => error = cvUserMessage(exception, widget.language));
      }
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
          _loadedOnce = true;
        });
      }
    }
  }

  List<CorrectiveAction> get filtered {
    final query = searchController.text.trim().toLowerCase();
    if (query.isEmpty) return actions;
    return actions
        .where(
          (action) =>
              action.referenceNo.toLowerCase().contains(query) ||
              action.description.toLowerCase().contains(query),
        )
        .toList();
  }

  Future<String?> _askComment(String title) {
    return showDialog<String>(
      context: context,
      builder: (_) => _CommentDialog(title: title, language: widget.language),
    );
  }

  Future<void> _transition(CorrectiveAction action, String transition) async {
    final title = switch (transition) {
      'start' => ar ? 'بدء الإجراء' : 'Start action',
      'request_close' => ar ? 'طلب التحقق والإغلاق' : 'Request verification',
      'close' => ar ? 'إغلاق الإجراء' : 'Close action',
      _ => ar ? 'إلغاء الإجراء' : 'Cancel action',
    };
    final comment = await _askComment(title);
    if (comment == null || !mounted) return;
    setState(() => _busyActionId = action.id);
    try {
      await ref
          .read(correctiveActionRepositoryProvider)
          .transition(action: action, transition: transition, comment: comment);
      await _load();
    } catch (exception) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(cvUserMessage(exception, widget.language))),
      );
    } finally {
      if (mounted) setState(() => _busyActionId = null);
    }
  }

  Future<void> _attachEvidence(CorrectiveAction action) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 92,
      );
      if (picked == null || !mounted) return;
      setState(() => _busyActionId = action.id);
      final raw = Uint8List.fromList(await picked.readAsBytes());
      final validation = ImageUploadValidation.validate(raw);
      if (!validation.ok) {
        throw FormatException(validation.messageFor(widget.language));
      }
      final inspection = await ref
          .read(inspectionRepositoryProvider)
          .getById(action.inspectionId);
      if (inspection == null) throw StateError('Inspection not found');
      final item = inspection.items
          .where((candidate) => candidate.id == action.inspectionItemId)
          .firstOrNull;
      if (item == null) throw StateError('Inspection item not found');
      final sites = await ref.read(siteRepositoryProvider).listSitesByIds([
        action.siteId,
      ]);
      final site = sites.isEmpty ? null : sites.first;
      final contextData =
          await InspectionPhotoStampResolver(
            ref.read(supabaseClientProvider),
          ).buildContext(
            site: site,
            language: widget.language,
            buildingCode: inspection.buildingCode,
            inspectionDateIso: inspection.dateIso,
            inspectionTime: inspection.inspectionTime,
            itemIndex: item.itemIndex,
            itemDescription: item.descriptionFor(widget.language),
            inspectorName: widget.profile.fullName,
            kindLabel: ar ? 'إجراء تصحيحي' : 'Corrective action',
            sourceLabel: ar ? 'المعرض' : 'Gallery',
            organizationIdFallback: action.organizationId,
            siteNameFallback: inspection.siteNameEn,
          );
      final stamped = await InspectionPhotoWatermark().apply(
        imageBytes: raw,
        context: contextData,
        arabic: ar,
      );
      final path = await ref
          .read(inspectionRepositoryProvider)
          .uploadBytes(
            organizationId: action.organizationId,
            siteId: action.siteId,
            inspectionId: action.inspectionId,
            fileName:
                'action_${action.id}_${DateTime.now().millisecondsSinceEpoch}.jpg',
            bytes: stamped,
          );
      final reference = await ref
          .read(correctiveActionRepositoryProvider)
          .registerEvidence(actionId: action.id, storagePath: path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ar
                ? 'تم حفظ الدليل بالمرجع $reference'
                : 'Evidence saved as $reference',
          ),
        ),
      );
    } catch (exception) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(cvUserMessage(exception, widget.language))),
      );
    } finally {
      if (mounted) setState(() => _busyActionId = null);
    }
  }

  Future<void> _pickStatus() async {
    const all = -1;
    final picked = await showCvChoiceSheet<int>(
      context: context,
      title: ar ? 'الحالة' : 'Status',
      selected: statusFilter?.index ?? all,
      choices: [
        CvChoice(value: all, label: ar ? 'كل الحالات' : 'All statuses'),
        for (final value in CorrectiveActionStatus.values)
          CvChoice(value: value.index, label: value.labelFor(widget.language)),
      ],
    );
    if (picked == null || !mounted) return;
    final next = picked == all ? null : CorrectiveActionStatus.values[picked];
    if (next == statusFilter) return;
    setState(() => statusFilter = next);
    await _load();
  }

  Future<void> _pickPriority() async {
    const all = -1;
    final picked = await showCvChoiceSheet<int>(
      context: context,
      title: ar ? 'الأولوية' : 'Priority',
      selected: priorityFilter?.index ?? all,
      choices: [
        CvChoice(value: all, label: ar ? 'كل الأولويات' : 'All priorities'),
        for (final value in CorrectiveActionPriority.values)
          CvChoice(value: value.index, label: value.labelFor(widget.language)),
      ],
    );
    if (picked == null || !mounted) return;
    final next = picked == all ? null : CorrectiveActionPriority.values[picked];
    if (next == priorityFilter) return;
    setState(() => priorityFilter = next);
    await _load();
  }

  Future<void> _clearFilters() async {
    searchController.clear();
    setState(() {
      statusFilter = null;
      priorityFilter = null;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(ar ? 'الإجراءات التصحيحية' : 'Corrective actions'),
      actions: [
        IconButton(
          onPressed: loading ? null : _load,
          tooltip: ar ? 'تحديث' : 'Refresh',
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
              label: ar ? 'النطاق' : 'Scope',
              value: widget.inspectionId == null
                  ? (ar ? 'كل الفحوصات' : 'All inspections')
                  : (ar ? 'هذا الفحص' : 'This inspection'),
              flex: 3,
            ),
            CvTitleField(
              label: ar ? 'الحالة' : 'Status',
              value:
                  statusFilter?.labelFor(widget.language) ??
                  (ar ? 'كل الحالات' : 'All statuses'),
              onTap: _pickStatus,
              flex: 2,
            ),
            CvTitleField(
              label: ar ? 'الأولوية' : 'Priority',
              value:
                  priorityFilter?.labelFor(widget.language) ??
                  (ar ? 'كل الأولويات' : 'All priorities'),
              onTap: _pickPriority,
              flex: 2,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            CvSpace.gutter,
            CvSpace.md,
            CvSpace.gutter,
            0,
          ),
          child: TextField(
            controller: searchController,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: ar
                  ? 'بحث بالمرجع أو الوصف'
                  : 'Search reference or description',
              suffixIcon: searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: ar ? 'مسح البحث' : 'Clear search',
                      onPressed: () => setState(searchController.clear),
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
        ),
        Expanded(child: _content()),
      ],
    ),
  );

  Widget _content() {
    if (!_loadedOnce) {
      return ListView(
        padding: const EdgeInsets.all(CvSpace.gutter),
        children: const [CvSkeletonLedger(rows: 4)],
      );
    }
    if (error != null) {
      return CvErrorState(
        title: ar ? 'تعذر تحميل الإجراءات' : 'Corrective actions did not load',
        message: error!,
        retryLabel: ar ? 'إعادة المحاولة' : 'Try again',
        onRetry: _load,
      );
    }
    final rows = filtered;
    if (rows.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            CvEmptyState(
              icon: Icons.task_alt_outlined,
              title: _hasFilters
                  ? (ar ? 'لا توجد إجراءات مطابقة' : 'No matching actions')
                  : (ar ? 'لا توجد إجراءات تصحيحية' : 'No corrective actions'),
              message: _hasFilters
                  ? (ar
                        ? 'غيّر عوامل التصفية أو امسح البحث.'
                        : 'Change the filters or clear the search.')
                  : (ar
                        ? 'تُنشأ الإجراءات من بنود الفحص غير المطابقة.'
                        : 'Actions are created from failed inspection items.'),
              action: _hasFilters
                  ? OutlinedButton(
                      onPressed: _clearFilters,
                      child: Text(ar ? 'مسح التصفية' : 'Clear filters'),
                    )
                  : null,
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: AnimatedOpacity(
        opacity: loading ? 0.55 : 1,
        duration: CvMotion.of(context, CvMotion.quick),
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            CvSpace.gutter,
            0,
            CvSpace.gutter,
            CvSpace.xxl,
          ),
          itemCount: rows.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) return _summary(rows);
            final i = index - 1;
            return CvLedgerTile(
              key: ValueKey(rows[i].id),
              isFirst: i == 0,
              isLast: i == rows.length - 1,
              child: _actionTile(rows[i]),
            );
          },
        ),
      ),
    );
  }

  Widget _summary(List<CorrectiveAction> rows) {
    int count(CorrectiveActionStatus status) =>
        rows.where((action) => action.status == status).length;
    return Padding(
      padding: const EdgeInsets.only(top: CvSpace.lg, bottom: CvSpace.md),
      child: CvTally(
        items: [
          for (final status in const [
            CorrectiveActionStatus.open,
            CorrectiveActionStatus.inProgress,
            CorrectiveActionStatus.pendingVerification,
          ])
            CvTallyItem(
              label: status.labelFor(widget.language),
              count: count(status),
              tone: cvActionStatusTone(status),
            ),
          CvTallyItem(
            label: ar ? 'متأخرة' : 'Overdue',
            count: rows.where((action) => action.isOverdue).length,
            tone: CvTone.rejected,
          ),
        ],
      ),
    );
  }

  String _iso(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Widget _actionTile(CorrectiveAction action) {
    final c = CheckViewColors.of(context);
    final theme = Theme.of(context);
    final busy = _busyActionId == action.id;
    final priorityTone = cvPriorityTone(action.priority);
    const compact = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(0, 48)),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14)),
    );
    final buttons = <Widget>[
      if (!action.status.isTerminal)
        OutlinedButton.icon(
          style: compact,
          onPressed: busy ? null : () => _attachEvidence(action),
          icon: const Icon(Icons.add_a_photo_outlined, size: 18),
          label: Text(ar ? 'إضافة دليل' : 'Add evidence'),
        ),
      if (action.status == CorrectiveActionStatus.open)
        FilledButton(
          style: compact,
          onPressed: busy ? null : () => _transition(action, 'start'),
          child: Text(ar ? 'بدء' : 'Start'),
        ),
      if (action.status == CorrectiveActionStatus.inProgress)
        FilledButton(
          style: compact,
          onPressed: busy ? null : () => _transition(action, 'request_close'),
          child: Text(ar ? 'طلب التحقق' : 'Request verification'),
        ),
      if (canManage &&
          action.status == CorrectiveActionStatus.pendingVerification)
        FilledButton.icon(
          style: compact,
          onPressed: busy ? null : () => _transition(action, 'close'),
          icon: const Icon(Icons.verified_outlined, size: 18),
          label: Text(ar ? 'تحقق وإغلاق' : 'Verify and close'),
        ),
      if (canManage && !action.status.isTerminal)
        TextButton(
          style: compact,
          onPressed: busy ? null : () => _transition(action, 'cancel'),
          child: Text(ar ? 'إلغاء الإجراء' : 'Cancel action'),
        ),
    ];

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        CvSpace.gutter,
        14,
        CvSpace.md,
        CvSpace.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        action.referenceNo,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontFeatures: cvTabular,
                        ),
                      ),
                    ),
                    const SizedBox(width: CvSpace.sm),
                    if (busy)
                      const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Flexible(
                        child: CvStatusMark(
                          label: action.status.labelFor(widget.language),
                          tone: cvActionStatusTone(action.status),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  action.description,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: CvSpace.sm),
                Wrap(
                  spacing: CvSpace.md,
                  runSpacing: 4,
                  children: [
                    CvMeta(
                      action.priority.labelFor(widget.language),
                      icon: Icons.flag_outlined,
                      color: priorityTone == CvTone.neutral
                          ? null
                          : cvToneColor(c, priorityTone),
                    ),
                    CvMeta(
                      ar
                          ? 'الاستحقاق ${_iso(action.dueDate)}'
                          : 'Due ${_iso(action.dueDate)}',
                      icon: Icons.event_outlined,
                      color: action.isOverdue ? c.rejected : null,
                    ),
                    if (action.isOverdue)
                      CvMeta(
                        ar ? 'متأخر' : 'Overdue',
                        icon: Icons.warning_amber_rounded,
                        color: c.rejected,
                      ),
                    if (action.evidenceRequired)
                      CvMeta(
                        ar ? 'يتطلب دليلًا' : 'Evidence required',
                        icon: Icons.photo_camera_outlined,
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (buttons.isNotEmpty) ...[
            const SizedBox(height: CvSpace.md),
            Wrap(
              spacing: CvSpace.sm,
              runSpacing: CvSpace.sm,
              children: buttons,
            ),
          ],
        ],
      ),
    );
  }
}

class _CommentDialog extends StatefulWidget {
  const _CommentDialog({required this.title, required this.language});

  final String title;
  final String language;

  @override
  State<_CommentDialog> createState() => _CommentDialogState();
}

class _CommentDialogState extends State<_CommentDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ar = widget.language == 'ar';
    return AlertDialog(
      title: Text(widget.title),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: _controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: ar ? 'التعليق (إلزامي)' : 'Comment (required)',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(ar ? 'إلغاء' : 'Cancel'),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, _) => FilledButton(
            onPressed: value.text.trim().isEmpty
                ? null
                : () => Navigator.pop(context, value.text.trim()),
            child: Text(ar ? 'تأكيد' : 'Confirm'),
          ),
        ),
      ],
    );
  }
}
