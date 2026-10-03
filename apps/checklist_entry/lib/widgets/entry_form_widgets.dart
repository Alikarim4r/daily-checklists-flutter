part of '../main.dart';

class _SignatureCard extends StatelessWidget {
  const _SignatureCard({
    required this.labels,
    required this.paperTheme,
    required this.readOnly,
    required this.controller,
    required this.previewUrl,
    this.previewBytes,
    required this.onClear,
  });

  final AppLabels labels;
  final FormPaperTheme paperTheme;
  final bool readOnly;
  final SignatureController controller;
  final String? previewUrl;
  final Uint8List? previewBytes;
  final VoidCallback onClear;

  bool get _hasPreview =>
      (previewBytes != null && previewBytes!.isNotEmpty) ||
      (previewUrl != null && previewUrl!.isNotEmpty);

  Widget _previewChild() {
    if (previewBytes != null && previewBytes!.isNotEmpty) {
      return Image.memory(
        previewBytes!,
        fit: BoxFit.fill,
        alignment: Alignment.center,
      );
    }
    return Image.network(
      previewUrl!,
      fit: BoxFit.fill,
      alignment: Alignment.center,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!readOnly) {
      return Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 12),
        child: CiPanel(
          child: ChecklistSignatureEditor(
            controller: controller,
            title: labels.signature,
            clearLabel: labels.clear,
            onClear: onClear,
            height: 220,
            borderColor: paperTheme.border,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 12),
      child: CiPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CiStatusPill(
                  label: labels.signature,
                  tone: _hasPreview ? CiTone.good : CiTone.warning,
                  icon: Icons.draw_outlined,
                ),
                const Spacer(),
                if (_hasPreview)
                  Icon(
                    Icons.verified_outlined,
                    color: CheckInColors.of(context).good,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (_hasPreview && readOnly)
              Container(
                height: 180,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: paperTheme.border, width: 1.5),
                  borderRadius: BorderRadius.circular(CiRadius.control),
                ),
                child: FittedBox(
                  fit: BoxFit.fill,
                  child: SizedBox(
                    width: 400,
                    height: 180,
                    child: _previewChild(),
                  ),
                ),
              )
            else
              Text(
                labels.signature,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

class _EntryItemCard extends StatelessWidget {
  const _EntryItemCard({
    super.key,
    required this.labels,
    required this.paperTheme,
    required this.language,
    required this.item,
    required this.previous,
    required this.readOnly,
    required this.overdue,
    required this.needsIssuePhoto,
    required this.needsFixPhoto,
    required this.onResponse,
    required this.onActions,
    required this.onPickIssue,
    required this.onPickFix,
    required this.onOpenPhoto,
    required this.onClearIssue,
    required this.onClearFix,
  });

  final AppLabels labels;
  final FormPaperTheme paperTheme;
  final String language;
  final InspectionItem item;
  final InspectionItem? previous;
  final bool readOnly;
  final bool overdue;
  final bool needsIssuePhoto;
  final bool needsFixPhoto;
  final ValueChanged<ChecklistResponse?> onResponse;
  final ValueChanged<String> onActions;
  final Future<void> Function([String? pairId]) onPickIssue;
  final Future<void> Function([String? pairId]) onPickFix;
  final Future<void> Function(String path) onOpenPhoto;
  final Future<void> Function(String path, String pairId) onClearIssue;
  final Future<void> Function(String path, String pairId) onClearFix;

  bool get _ar => language == 'ar';

  @override
  Widget build(BuildContext context) {
    final problem = item.isProblem;
    final prevProblem = previous?.isProblem == true;
    final tone = overdue || problem
        ? CiTone.danger
        : needsFixPhoto || needsIssuePhoto
        ? CiTone.warning
        : item.response == null
        ? CiTone.neutral
        : CiTone.good;
    final statusLabel = overdue
        ? labels.overdue
        : needsFixPhoto || needsIssuePhoto
        ? (_ar ? 'صورة مطلوبة' : 'Photo needed')
        : problem
        ? labels.problemIndicator
        : item.response == null
        ? (_ar ? 'غير مكتمل' : 'Not answered')
        : (_ar ? 'مكتمل' : 'Complete');
    final previousLabel = switch (previous?.response) {
      ChecklistResponse.yes => labels.yes,
      ChecklistResponse.no => labels.no,
      ChecklistResponse.na => labels.na,
      null => '—',
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CiInspectionItemFrame(
        index: item.itemIndex,
        title: item.descriptionFor(language),
        tone: tone,
        statusLabel: statusLabel,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Container(
                width: 42,
                height: 3,
                decoration: BoxDecoration(
                  color: paperTheme.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (previous != null) ...[
              const SizedBox(height: 8),
              Text(
                '${labels.previousAnswer} $previousLabel'
                '${prevProblem ? ' · ${labels.previousIssue}' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            CiResponseSelector(
              value: item.response,
              labels: labels,
              enabled: !readOnly,
              onChanged: onResponse,
            ),
            const SizedBox(height: 12),
            _RemarksField(
              key: ValueKey('remarks-${item.id ?? item.itemIndex}'),
              initial: item.actionsTaken,
              readOnly: readOnly,
              label: labels.actions,
              onChanged: onActions,
            ),
            if (problem || needsIssuePhoto || item.photoPairs.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _ar ? 'وحدات المشكلة / الإصلاح' : 'Issue / fix units',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 6),
              for (var i = 0; i < item.photoPairs.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _EntryPhotoPairRow(
                  arabic: _ar,
                  unitIndex: i + 1,
                  pair: item.photoPairs[i],
                  readOnly: readOnly,
                  labels: labels,
                  canDeleteIssue:
                      item.photoPairs[i].issuePath?.startsWith('offline://') ==
                      true,
                  onOpenPhoto: onOpenPhoto,
                  onPickFix: () => onPickFix(item.photoPairs[i].id),
                  onClearIssue: () async => onClearIssue(
                    item.photoPairs[i].issuePath!,
                    item.photoPairs[i].id,
                  ),
                  onClearFix: () async => onClearFix(
                    item.photoPairs[i].fixPath!,
                    item.photoPairs[i].id,
                  ),
                ),
              ],
              if (!readOnly) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => onPickIssue(),
                  icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                  label: Text(
                    _ar
                        ? 'إضافة وحدة (صورة مشكلة)${needsIssuePhoto && item.photoPairs.isEmpty ? ' *' : ''}'
                        : 'Add unit (issue photo)${needsIssuePhoto && item.photoPairs.isEmpty ? ' *' : ''}',
                  ),
                ),
              ],
            ],
            if (prevProblem && needsFixPhoto)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: CiInlineNotice(
                  message: labels.photoFixMessage,
                  tone: CiTone.warning,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EntryPhotoPairRow extends StatelessWidget {
  const _EntryPhotoPairRow({
    required this.arabic,
    required this.unitIndex,
    required this.pair,
    required this.readOnly,
    required this.labels,
    required this.canDeleteIssue,
    required this.onOpenPhoto,
    required this.onPickFix,
    required this.onClearIssue,
    required this.onClearFix,
  });

  final bool arabic;
  final int unitIndex;
  final InspectionPhotoPair pair;
  final bool readOnly;
  final AppLabels labels;
  final bool canDeleteIssue;
  final Future<void> Function(String path) onOpenPhoto;
  final Future<void> Function() onPickFix;
  final Future<void> Function() onClearIssue;
  final Future<void> Function() onClearFix;

  Future<bool> _confirmRemoval(BuildContext context, String kind) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(arabic ? 'إزالة الصورة؟' : 'Remove photo?'),
        content: Text(
          arabic
              ? 'ستُزال صورة $kind من هذا الفحص. لا يمكن التراجع بعد الحفظ.'
              : 'This $kind photo will be removed from the inspection. This cannot be undone after saving.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(arabic ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(arabic ? 'إزالة' : 'Remove'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _showIssueActions(BuildContext context) async {
    if (!pair.hasIssue) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.open_in_full_outlined),
              title: Text(arabic ? 'فتح الصورة' : 'Open photo'),
              onTap: () => Navigator.pop(ctx, 'open'),
            ),
            if (!readOnly && !pair.hasFix)
              ListTile(
                leading: const Icon(Icons.build_circle_outlined),
                title: Text(arabic ? 'إضافة صورة إصلاح' : 'Add fix photo'),
                onTap: () => Navigator.pop(ctx, 'fix'),
              ),
            if (!readOnly && canDeleteIssue)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(arabic ? 'حذف صورة المشكلة' : 'Delete issue photo'),
                onTap: () => Navigator.pop(ctx, 'del'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == 'open') await onOpenPhoto(pair.issuePath!);
    if (action == 'fix') await onPickFix();
    if (action == 'del' &&
        context.mounted &&
        await _confirmRemoval(context, arabic ? 'المشكلة' : 'issue')) {
      await onClearIssue();
    }
  }

  Future<void> _showFixActions(BuildContext context) async {
    if (!pair.hasFix) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.open_in_full_outlined),
              title: Text(arabic ? 'فتح الصورة' : 'Open photo'),
              onTap: () => Navigator.pop(ctx, 'open'),
            ),
            if (!readOnly)
              ListTile(
                leading: const Icon(Icons.remove_circle_outline),
                title: Text(arabic ? 'إزالة صورة الإصلاح' : 'Remove fix photo'),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == 'open') await onOpenPhoto(pair.fixPath!);
    if (action == 'remove' &&
        context.mounted &&
        await _confirmRemoval(context, arabic ? 'الإصلاح' : 'fix')) {
      await onClearFix();
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = photoPairLabel(unitIndex, arabic: arabic);
    final colors = CheckInColors.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        border: Border.all(color: colors.line),
        borderRadius: BorderRadius.circular(CiRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Material(
            color: pair.hasIssue ? colors.dangerSoft : colors.surface,
            borderRadius: BorderRadius.circular(CiRadius.control),
            child: InkWell(
              borderRadius: BorderRadius.circular(CiRadius.control),
              onTap: pair.hasIssue ? () => _showIssueActions(context) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.image_outlined,
                      size: 20,
                      color: pair.hasIssue ? colors.danger : colors.inkMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        pair.hasIssue
                            ? (readOnly || pair.hasFix
                                  ? (arabic
                                        ? '${labels.issuePhoto} ✓ — اضغط للفتح'
                                        : '${labels.issuePhoto} ✓ — tap to open')
                                  : (arabic
                                        ? '${labels.issuePhoto} ✓ — فتح أو إضافة إصلاح'
                                        : '${labels.issuePhoto} ✓ — open or add fix'))
                            : labels.issuePhoto,
                        style: TextStyle(
                          fontSize: 12,
                          color: pair.hasIssue
                              ? colors.danger
                              : colors.inkMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (pair.hasFix) ...[
            const SizedBox(height: 6),
            Material(
              color: colors.goodSoft,
              borderRadius: BorderRadius.circular(CiRadius.control),
              child: InkWell(
                borderRadius: BorderRadius.circular(CiRadius.control),
                onTap: () => _showFixActions(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.build_circle_outlined,
                        size: 20,
                        color: colors.good,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          readOnly
                              ? (arabic
                                    ? '${labels.repairPhoto} ✓ — اضغط للفتح'
                                    : '${labels.repairPhoto} ✓ — tap to open')
                              : (arabic
                                    ? '${labels.repairPhoto} ✓ — فتح أو إزالة'
                                    : '${labels.repairPhoto} ✓ — open or remove'),
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.good,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RemarksField extends StatefulWidget {
  const _RemarksField({
    super.key,
    required this.initial,
    required this.readOnly,
    required this.label,
    required this.onChanged,
  });

  final String initial;
  final bool readOnly;
  final String label;
  final ValueChanged<String> onChanged;

  @override
  State<_RemarksField> createState() => _RemarksFieldState();
}

class _RemarksFieldState extends State<_RemarksField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      enabled: !widget.readOnly,
      controller: _ctrl,
      onChanged: widget.onChanged,
      minLines: 1,
      maxLines: 3,
      textInputAction: TextInputAction.newline,
      scrollPadding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom + 120,
      ),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.readOnly ? null : widget.label,
      ),
    );
  }
}
