import 'dart:typed_data';

import 'package:checklist_shared/checklist_shared.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

class CorrectiveActionsScreen extends ConsumerStatefulWidget {
  const CorrectiveActionsScreen({
    super.key,
    required this.profile,
    required this.language,
    this.inspectionId,
  });

  final Profile profile;
  final String language;
  final String? inspectionId;

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
  String? error;

  bool get ar => widget.language == 'ar';
  bool get canManage =>
      widget.profile.isPlatformOwner || widget.profile.role.isElevatedAdmin;

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
      if (mounted) setState(() => error = '$exception');
    } finally {
      if (mounted) setState(() => loading = false);
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

  Future<String?> _askComment(String title) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: ar ? 'التعليق الإلزامي' : 'Required comment',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(ar ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final comment = controller.text.trim();
              if (comment.isNotEmpty) Navigator.pop(context, comment);
            },
            child: Text(ar ? 'تأكيد' : 'Confirm'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> _transition(CorrectiveAction action, String transition) async {
    final title = switch (transition) {
      'start' => ar ? 'بدء الإجراء' : 'Start action',
      'request_close' => ar ? 'طلب التحقق والإغلاق' : 'Request verification',
      'close' => ar ? 'إغلاق الإجراء' : 'Close action',
      _ => ar ? 'إلغاء الإجراء' : 'Cancel action',
    };
    final comment = await _askComment(title);
    if (comment == null) return;
    try {
      await ref
          .read(correctiveActionRepositoryProvider)
          .transition(action: action, transition: transition, comment: comment);
      await _load();
    } catch (exception) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$exception')));
    }
  }

  Future<void> _attachEvidence(CorrectiveAction action) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 92,
      );
      if (picked == null) return;
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$exception')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: checklistGradientAppBar(
      title: ar ? 'الإجراءات التصحيحية' : 'Corrective actions',
      leading: checklistBackButton(context),
      actions: [
        IconButton(
          onPressed: loading ? null : _load,
          tooltip: ar ? 'تحديث' : 'Refresh',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(
      children: [
        _filters(),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : error != null
              ? Center(child: Text(error!, textAlign: TextAlign.center))
              : filtered.isEmpty
              ? Center(
                  child: Text(
                    ar ? 'لا توجد إجراءات مطابقة' : 'No matching actions',
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) =>
                        _actionCard(filtered[index]),
                  ),
                ),
        ),
      ],
    ),
  );

  Widget _filters() => Material(
    color: Theme.of(context).colorScheme.surfaceContainer,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 280,
            child: TextField(
              controller: searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                labelText: ar
                    ? 'بحث بالمرجع أو الوصف'
                    : 'Search ref/description',
              ),
            ),
          ),
          DropdownButton<CorrectiveActionStatus?>(
            value: statusFilter,
            hint: Text(ar ? 'كل الحالات' : 'All statuses'),
            items: [
              DropdownMenuItem(
                value: null,
                child: Text(ar ? 'كل الحالات' : 'All statuses'),
              ),
              for (final value in CorrectiveActionStatus.values)
                DropdownMenuItem(
                  value: value,
                  child: Text(value.labelFor(widget.language)),
                ),
            ],
            onChanged: (value) {
              setState(() => statusFilter = value);
              _load();
            },
          ),
          DropdownButton<CorrectiveActionPriority?>(
            value: priorityFilter,
            hint: Text(ar ? 'كل الأولويات' : 'All priorities'),
            items: [
              DropdownMenuItem(
                value: null,
                child: Text(ar ? 'كل الأولويات' : 'All priorities'),
              ),
              for (final value in CorrectiveActionPriority.values)
                DropdownMenuItem(
                  value: value,
                  child: Text(value.labelFor(widget.language)),
                ),
            ],
            onChanged: (value) {
              setState(() => priorityFilter = value);
              _load();
            },
          ),
        ],
      ),
    ),
  );

  Widget _actionCard(CorrectiveAction action) {
    final due =
        '${action.dueDate.year}-${action.dueDate.month.toString().padLeft(2, '0')}-'
        '${action.dueDate.day.toString().padLeft(2, '0')}';
    final color = action.isOverdue
        ? Colors.red
        : action.priority == CorrectiveActionPriority.critical
        ? Colors.deepOrange
        : Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ChecklistBrandCard(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.build_circle_outlined, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      action.referenceNo,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  Chip(label: Text(action.status.labelFor(widget.language))),
                ],
              ),
              const SizedBox(height: 8),
              Text(action.description),
              const SizedBox(height: 8),
              Text(
                '${action.priority.labelFor(widget.language)} · '
                '${ar ? 'الاستحقاق' : 'Due'} $due',
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!action.status.isTerminal)
                    OutlinedButton.icon(
                      onPressed: () => _attachEvidence(action),
                      icon: const Icon(Icons.add_a_photo_outlined),
                      label: Text(ar ? 'إضافة دليل' : 'Add evidence'),
                    ),
                  if (action.status == CorrectiveActionStatus.open)
                    FilledButton(
                      onPressed: () => _transition(action, 'start'),
                      child: Text(ar ? 'بدء' : 'Start'),
                    ),
                  if (action.status == CorrectiveActionStatus.inProgress)
                    FilledButton(
                      onPressed: () => _transition(action, 'request_close'),
                      child: Text(ar ? 'طلب التحقق' : 'Request verification'),
                    ),
                  if (canManage &&
                      action.status ==
                          CorrectiveActionStatus.pendingVerification)
                    FilledButton.icon(
                      onPressed: () => _transition(action, 'close'),
                      icon: const Icon(Icons.verified_outlined),
                      label: Text(ar ? 'تحقق وإغلاق' : 'Verify & close'),
                    ),
                  if (canManage && !action.status.isTerminal)
                    TextButton(
                      onPressed: () => _transition(action, 'cancel'),
                      child: Text(ar ? 'إلغاء الإجراء' : 'Cancel action'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
