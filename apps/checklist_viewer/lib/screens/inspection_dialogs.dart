import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/checkview_tokens.dart';
import '../design/checkview_errors.dart';
import '../design/checkview_widgets.dart';

/// Items that can carry a corrective action (answered, not N/A, not ideal).
List<InspectionItem> failedInspectionItems(Inspection inspection) => inspection
    .items
    .where(
      (item) =>
          item.id != null &&
          item.response != null &&
          item.response != ChecklistResponse.na &&
          !item.isIdealAnswer,
    )
    .toList();

String isoDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

/// Asks for the mandatory reason for return / reject / cancel.
Future<String?> requestWorkflowReason(
  BuildContext context, {
  required String language,
  required String action,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _ReasonDialog(language: language, action: action),
  );
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.language, required this.action});

  final String language;
  final String action;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ar = widget.language == 'ar';
    final title = switch (widget.action) {
      'return' => ar ? 'إعادة الفحص للتصحيح' : 'Return for correction',
      'reject' => ar ? 'رفض الفحص' : 'Reject inspection',
      _ => ar ? 'إلغاء الفحص' : 'Cancel inspection',
    };
    final confirm = switch (widget.action) {
      'return' => ar ? 'إعادة' : 'Return',
      'reject' => ar ? 'رفض' : 'Reject',
      _ => ar ? 'إلغاء الفحص' : 'Cancel inspection',
    };
    return AlertDialog(
      title: Text(title),
      scrollable: true,
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              ar
                  ? 'يظهر هذا السبب على الفحص.'
                  : 'This reason is shown on the inspection.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: CvSpace.md),
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: ar ? 'السبب (إلزامي)' : 'Reason (required)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(ar ? 'رجوع' : 'Close'),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, _) => FilledButton(
            onPressed: value.text.trim().isEmpty
                ? null
                : () => Navigator.pop(context, value.text.trim()),
            child: Text(confirm),
          ),
        ),
      ],
    );
  }
}

/// Workflow note (return / reject / cancel reason) above the form.
class InspectionWorkflowNote extends StatelessWidget {
  const InspectionWorkflowNote({
    super.key,
    required this.inspection,
    required this.language,
  });

  final Inspection inspection;
  final String language;

  @override
  Widget build(BuildContext context) {
    final tone = switch (inspection.reviewStatus) {
      ReviewStatus.returned => CvBannerTone.warning,
      ReviewStatus.rejected || ReviewStatus.canceled => CvBannerTone.error,
      _ => CvBannerTone.info,
    };
    return CvBanner(
      tone: tone,
      title: inspection.reviewStatus.labelFor(language),
      message: inspection.workflowNote!.trim(),
    );
  }
}

enum ReportDelivery { share, print }

class ReportRequest {
  const ReportRequest(this.delivery, this.photoMode);

  final ReportDelivery delivery;
  final ReportPhotoMode photoMode;
}

/// One sheet for delivery and photo handling, replacing two sequential sheets.
Future<ReportRequest?> showReportOptionsSheet(
  BuildContext context,
  String language,
) {
  return showModalBottomSheet<ReportRequest>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: CvSpace.sm),
      child: _ReportOptionsSheet(language: language),
    ),
  );
}

class _ReportOptionsSheet extends StatefulWidget {
  const _ReportOptionsSheet({required this.language});

  final String language;

  @override
  State<_ReportOptionsSheet> createState() => _ReportOptionsSheetState();
}

class _ReportOptionsSheetState extends State<_ReportOptionsSheet> {
  ReportDelivery delivery = ReportDelivery.share;
  ReportPhotoMode photoMode = ReportPhotoMode.links;

  @override
  Widget build(BuildContext context) {
    final ar = widget.language == 'ar';
    final theme = Theme.of(context);
    Widget group(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(
        CvSpace.xl,
        CvSpace.lg,
        CvSpace.xl,
        CvSpace.xs,
      ),
      child: Semantics(
        header: true,
        child: Text(label, style: theme.textTheme.labelSmall),
      ),
    );
    final deliveries = [
      CvChoice(
        value: ReportDelivery.share,
        icon: Icons.ios_share_outlined,
        label: ar ? 'حفظ / مشاركة PDF' : 'Save or share PDF',
        description: ar
            ? 'احفظ الملف ثم اطبعه من عارض PDF'
            : 'Save the file, then print it from your PDF viewer',
      ),
      CvChoice(
        value: ReportDelivery.print,
        icon: Icons.print_outlined,
        label: ar ? 'طباعة مباشرة' : 'Print directly',
        description: ar
            ? 'إرسال مباشر إلى الطابعة'
            : 'Send straight to a printer',
      ),
    ];
    final photoModes = [
      CvChoice(
        value: ReportPhotoMode.links,
        icon: Icons.link_outlined,
        label: ar ? 'مراجع وروابط الصور' : 'Photo references and secure links',
        description: ar
            ? 'تقرير خفيف مع مرجع ثابت ورابط آمن لكل صورة'
            : 'Lighter file with a stable reference and secure link per photo',
      ),
      CvChoice(
        value: ReportPhotoMode.embedded,
        icon: Icons.photo_library_outlined,
        label: ar ? 'تضمين الصور في التقرير' : 'Include photos in the PDF',
        description: ar
            ? 'يضيف قسم أدلة الصور مع مراجع البنود'
            : 'Adds an evidence section with item references',
      ),
    ];
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CvSheetHeader(title: ar ? 'تقرير الفحص' : 'Inspection report'),
          const Divider(),
          group(ar ? 'طريقة الإخراج' : 'Output'),
          for (final choice in deliveries)
            CvChoiceRow(
              choice: choice,
              selected: delivery == choice.value,
              onTap: () => setState(() => delivery = choice.value),
            ),
          group(ar ? 'الصور' : 'Photos'),
          for (final choice in photoModes)
            CvChoiceRow(
              choice: choice,
              selected: photoMode == choice.value,
              onTap: () => setState(() => photoMode = choice.value),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CvSpace.xl,
              CvSpace.lg,
              CvSpace.xl,
              CvSpace.xl,
            ),
            child: FilledButton.icon(
              onPressed: () =>
                  Navigator.pop(context, ReportRequest(delivery, photoMode)),
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
              label: Text(ar ? 'إنشاء التقرير' : 'Create report'),
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool> createCorrectiveActionForInspection({
  required BuildContext context,
  required WidgetRef ref,
  required Inspection inspection,
  required String language,
}) async {
  final failed = failedInspectionItems(inspection);
  if (failed.isEmpty) return false;
  final created = await showDialog<bool>(
    context: context,
    builder: (_) =>
        _CorrectiveActionDialog(ref: ref, failed: failed, language: language),
  );
  return created == true;
}

class _CorrectiveActionDialog extends StatefulWidget {
  const _CorrectiveActionDialog({
    required this.ref,
    required this.failed,
    required this.language,
  });

  final WidgetRef ref;
  final List<InspectionItem> failed;
  final String language;

  @override
  State<_CorrectiveActionDialog> createState() =>
      _CorrectiveActionDialogState();
}

class _CorrectiveActionDialogState extends State<_CorrectiveActionDialog> {
  late InspectionItem selected = widget.failed.first;
  var priority = CorrectiveActionPriority.medium;
  var dueDate = qatarBusinessNow().add(const Duration(days: 7));
  var evidenceRequired = true;
  var saving = false;
  late final description = TextEditingController(text: selected.actionsTaken);

  bool get ar => widget.language == 'ar';

  @override
  void dispose() {
    description.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final now = qatarBusinessNow();
    final picked = await showDatePicker(
      context: context,
      initialDate: dueDate,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 730)),
    );
    if (picked != null && mounted) setState(() => dueDate = picked);
  }

  Future<void> _create() async {
    final text = description.text.trim();
    if (text.isEmpty) return;
    setState(() => saving = true);
    try {
      await widget.ref
          .read(correctiveActionRepositoryProvider)
          .create(
            inspectionItemId: selected.id!,
            description: text,
            priority: priority,
            dueDate: dueDate,
            evidenceRequired: evidenceRequired,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (exception) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(cvUserMessage(exception, widget.language))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = CheckViewColors.of(context);
    return AlertDialog(
      title: Text(ar ? 'إجراء تصحيحي جديد' : 'New corrective action'),
      scrollable: true,
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<InspectionItem>(
              initialValue: selected,
              isExpanded: true,
              decoration: InputDecoration(labelText: ar ? 'البند' : 'Item'),
              items: [
                for (final item in widget.failed)
                  DropdownMenuItem(
                    value: item,
                    child: Text(
                      '${item.itemIndex}. '
                      '${item.descriptionFor(widget.language)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: saving
                  ? null
                  : (value) {
                      if (value != null) setState(() => selected = value);
                    },
            ),
            const SizedBox(height: CvSpace.md),
            TextField(
              controller: description,
              enabled: !saving,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: ar ? 'وصف الإجراء المطلوب' : 'Required action',
              ),
            ),
            const SizedBox(height: CvSpace.md),
            DropdownButtonFormField<CorrectiveActionPriority>(
              initialValue: priority,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: ar ? 'الأولوية' : 'Priority',
              ),
              items: [
                for (final value in CorrectiveActionPriority.values)
                  DropdownMenuItem(
                    value: value,
                    child: Text(value.labelFor(widget.language)),
                  ),
              ],
              onChanged: saving
                  ? null
                  : (value) {
                      if (value != null) setState(() => priority = value);
                    },
            ),
            const SizedBox(height: CvSpace.sm),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(ar ? 'تاريخ الاستحقاق' : 'Due date'),
              subtitle: Text(
                isoDate(dueDate),
                style: TextStyle(color: c.ink, fontFeatures: cvTabular),
              ),
              trailing: Icon(Icons.edit_calendar_outlined, color: c.accent),
              onTap: saving ? null : _pickDueDate,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: evidenceRequired,
              onChanged: saving
                  ? null
                  : (value) => setState(() => evidenceRequired = value),
              title: Text(
                ar ? 'يتطلب دليلًا قبل الإغلاق' : 'Require closure evidence',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context, false),
          child: Text(ar ? 'إلغاء' : 'Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : _create,
          child: saving
              ? SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.inkMuted,
                  ),
                )
              : Text(ar ? 'إنشاء' : 'Create'),
        ),
      ],
    );
  }
}

/// Inspection title block shared by the phone page and the wide detail pane.
CvTitleBlock inspectionTitleBlock({
  required Inspection inspection,
  required String language,
  bool loading = false,
}) {
  final ar = language == 'ar';
  final siteName = (ar && inspection.siteNameAr.trim().isNotEmpty)
      ? inspection.siteNameAr.trim()
      : inspection.siteNameEn.trim();
  final inspector = inspection.inspectorName.trim();
  return CvTitleBlock(
    loading: loading,
    fields: [
      CvTitleField(
        label: ar ? 'الموقع' : 'Site',
        value: siteName.isEmpty
            ? inspection.buildingCode
            : '${inspection.buildingCode}   $siteName',
        flex: 3,
        maxLines: 2,
      ),
      CvTitleField(
        label: ar ? 'التاريخ' : 'Date',
        value: inspection.dateIso,
        flex: 2,
      ),
      CvTitleField(
        label: ar ? 'المفتش' : 'Inspector',
        value: inspector.isEmpty ? (ar ? 'غير محدد' : 'Not set') : inspector,
        flex: 2,
        maxLines: 2,
      ),
      CvTitleField(
        label: ar ? 'الحالة' : 'State',
        flex: 2,
        child: CvStatusMark(
          label: inspection.reviewStatus.labelFor(language),
          tone: cvReviewTone(inspection.reviewStatus),
        ),
      ),
    ],
  );
}

class CustomItemDraft {
  const CustomItemDraft({
    required this.descriptionEn,
    required this.descriptionAr,
    required this.defaultAnswer,
  });

  final String descriptionEn;
  final String descriptionAr;
  final String defaultAnswer;
}

/// Collects a custom checklist item. Controllers live in the dialog state so
/// they outlive the closing animation.
Future<CustomItemDraft?> requestCustomItem(
  BuildContext context, {
  required String language,
}) {
  return showDialog<CustomItemDraft>(
    context: context,
    builder: (_) => _CustomItemDialog(language: language),
  );
}

class _CustomItemDialog extends StatefulWidget {
  const _CustomItemDialog({required this.language});

  final String language;

  @override
  State<_CustomItemDialog> createState() => _CustomItemDialogState();
}

class _CustomItemDialogState extends State<_CustomItemDialog> {
  final _en = TextEditingController();
  final _ar = TextEditingController();
  var _defaultAnswer = 'Y';

  @override
  void dispose() {
    _en.dispose();
    _ar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ar = widget.language == 'ar';
    return AlertDialog(
      title: Text(ar ? 'إضافة بند' : 'Add item'),
      scrollable: true,
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _en,
              decoration: InputDecoration(
                labelText: ar ? 'الوصف (EN)' : 'Description (EN)',
              ),
            ),
            const SizedBox(height: CvSpace.md),
            TextField(
              controller: _ar,
              decoration: InputDecoration(
                labelText: ar ? 'الوصف (AR)' : 'Description (AR)',
              ),
            ),
            const SizedBox(height: CvSpace.md),
            DropdownButtonFormField<String>(
              initialValue: _defaultAnswer,
              decoration: InputDecoration(
                labelText: ar ? 'الإجابة المثالية' : 'Ideal answer',
              ),
              items: const [
                DropdownMenuItem(value: 'Y', child: Text('Yes / نعم')),
                DropdownMenuItem(value: 'N', child: Text('No / لا')),
              ],
              onChanged: (v) => setState(() => _defaultAnswer = v ?? 'Y'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(ar ? 'إلغاء' : 'Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            CustomItemDraft(
              descriptionEn: _en.text.trim(),
              descriptionAr: _ar.text.trim(),
              defaultAnswer: _defaultAnswer,
            ),
          ),
          child: Text(ar ? 'إضافة' : 'Add'),
        ),
      ],
    );
  }
}

/// Owner-only inspection date correction. Returns the new date and the
/// mandatory reason, or null when cancelled.
Future<(DateTime, String)?> requestDateCorrection(
  BuildContext context, {
  required String language,
  required DateTime initialDate,
  required DateTime lastDate,
}) {
  return showDialog<(DateTime, String)>(
    context: context,
    builder: (_) => _DateCorrectionDialog(
      language: language,
      initialDate: initialDate,
      lastDate: lastDate,
    ),
  );
}

class _DateCorrectionDialog extends StatefulWidget {
  const _DateCorrectionDialog({
    required this.language,
    required this.initialDate,
    required this.lastDate,
  });

  final String language;
  final DateTime initialDate;
  final DateTime lastDate;

  @override
  State<_DateCorrectionDialog> createState() => _DateCorrectionDialogState();
}

class _DateCorrectionDialogState extends State<_DateCorrectionDialog> {
  final _reason = TextEditingController();
  late DateTime _date = widget.initialDate;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ar = widget.language == 'ar';
    return AlertDialog(
      title: Text(ar ? 'تصحيح تاريخ الفحص' : 'Correct inspection date'),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2024),
                  lastDate: widget.lastDate,
                );
                if (picked != null && mounted) setState(() => _date = picked);
              },
              icon: const Icon(Icons.event_outlined),
              label: Text(isoDate(_date)),
            ),
            const SizedBox(height: CvSpace.md),
            TextField(
              controller: _reason,
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
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(ar ? 'إلغاء' : 'Cancel'),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _reason,
          builder: (context, value, _) => FilledButton(
            onPressed: value.text.trim().isEmpty
                ? null
                : () => Navigator.pop(context, (_date, value.text.trim())),
            child: Text(ar ? 'حفظ التصحيح' : 'Save correction'),
          ),
        ),
      ],
    );
  }
}
