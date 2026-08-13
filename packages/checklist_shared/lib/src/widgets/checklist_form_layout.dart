import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signature/signature.dart';

import '../models/enums.dart';
import '../models/inspection.dart';
import '../providers/providers.dart';
import '../theme/checklist_brand.dart';
import '../theme/form_paper_theme.dart';
import '../utils/photo_pair.dart';
import '../utils/signature_ink.dart';
import '../utils/storage_path_list.dart';
import 'checklist_branding_widgets.dart';
import 'checklist_signature_pad.dart';

/// Paper form matching ViewerEditV2.html + MOEHE Daily Checklist PDF.
class ChecklistFormLayout extends ConsumerWidget {
  const ChecklistFormLayout({
    super.key,
    required this.inspection,
    required this.language,
    this.readOnly = false,
    this.onResponseChanged,
    this.onActionsChanged,
    this.onInspectorChanged,
    this.onTimeChanged,
    this.onFloorChanged,
    this.onPickIssuePhoto,
    this.onPickFixPhoto,
    this.onClearIssuePhoto,
    this.onClearFixPhoto,
    this.onAddItem,
    this.onDeleteItem,
    this.onOpenPhoto,
    this.signatureController,
    this.signaturePreviewBytes,
    this.onClearSignature,
    this.trailingHeader,
    this.forceTableLayout = false,
    this.overdueItemIndexes = const {},
    this.issueOpenTooltipsByPath = const {},
    this.paperTheme,
  });

  final Inspection inspection;
  final String language;
  final bool readOnly;
  final void Function(InspectionItem item, ChecklistResponse? value)?
  onResponseChanged;
  final void Function(InspectionItem item, String value)? onActionsChanged;
  final ValueChanged<String>? onInspectorChanged;
  final ValueChanged<String>? onTimeChanged;
  final ValueChanged<String>? onFloorChanged;
  final Future<void> Function(InspectionItem item, [String? pairId])?
  onPickIssuePhoto;
  final Future<void> Function(InspectionItem item, [String? pairId])?
  onPickFixPhoto;
  final Future<void> Function(
    InspectionItem item,
    String path, [
    String? pairId,
  ])?
  onClearIssuePhoto;
  final Future<void> Function(
    InspectionItem item,
    String path, [
    String? pairId,
  ])?
  onClearFixPhoto;
  final Future<void> Function()? onAddItem;
  final Future<void> Function(InspectionItem item)? onDeleteItem;
  final void Function(String storagePath)? onOpenPhoto;
  final SignatureController? signatureController;
  final Uint8List? signaturePreviewBytes;
  final VoidCallback? onClearSignature;
  final Widget? trailingHeader;
  final bool forceTableLayout;

  /// Item indexes flagged overdue by org policy (ongoing problem streak).
  final Set<int> overdueItemIndexes;

  /// Hover text for unfixed issue photos (keyed by storage path).
  final Map<String, String> issueOpenTooltipsByPath;
  final FormPaperTheme? paperTheme;

  FormPaperTheme get _effectivePaperTheme =>
      paperTheme ?? inspection.paperTheme;
  Color get _gold => _effectivePaperTheme.accent;
  Color get _border => _effectivePaperTheme.border;
  Color get _accentText => _effectivePaperTheme.accentText;
  static const _okBlue = Color(0xFF3B82F6);
  static const _problemRed = Color(0xFFEF4444);
  static const _fixGreen = Color(0xFF28A745);
  static const _emptyGray = Color(0xFFCBD5E1);

  /// ≈ 6 mm at 96 dpi — keeps remarks text-first.
  static const _photoW = 23.0;
  static const _photoH = 36.0;

  bool get _ar => language == 'ar';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Always LTR like ViewerEditV2 `dir="ltr"` / A4 PDF — never reverse
    // Item → Description → Yes → No → NA → Remarks.
    final items = [...inspection.items]
      ..sort((a, b) => a.itemIndex.compareTo(b.itemIndex));
    for (final item in items) {
      item.defaultAnswer = item.defaultAnswer.toUpperCase();
      // Leave Yes/No/NA empty until the inspector answers.
    }

    // Paper light Theme (stable singleton) keeps form ink readable under dark
    // chrome without recreating ThemeData on every rebuild.
    return Directionality(
      textDirection: _ar ? ui.TextDirection.rtl : ui.TextDirection.ltr,
      child: Theme(
        data: ChecklistChrome.paperFormTheme,
        child: DefaultTextStyle(
          style: const TextStyle(
            color: Colors.black,
            fontSize: 12,
            height: 1.3,
            decoration: TextDecoration.none,
          ),
          child: Container(
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _headerRow(),
                const SizedBox(height: 8),
                _titleBanner(),
                const SizedBox(height: 10),
                _metaGrid(ref),
                if (trailingHeader != null) ...[
                  const SizedBox(height: 8),
                  trailingHeader!,
                ],
                const SizedBox(height: 12),
                _table(context, ref, items),
                const SizedBox(height: 14),
                Text(
                  _ar
                      ? 'توفر هذه القائمة المتطلبات الأساسية للفحوصات اليومية لخدمات البنية. عند تسجيل «لا» لأي بند أعلاه، يجب اتخاذ إجراء فوري لمعالجة المشكلة لضمان استمرار التشغيل الآمن.'
                      : 'This checklist provides the basic requirements for hard services operations daily checks. Should a "No" be recorded for any of the above checklist items, immediate action to be taken to address the issues, to have safe, continued operation.',
                  textAlign: _ar ? TextAlign.right : TextAlign.left,
                  style: const TextStyle(
                    fontSize: 10.5,
                    height: 1.4,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 14),
                _footerLogos(),
                const SizedBox(height: 8),
                Align(
                  alignment: _ar ? Alignment.centerRight : Alignment.centerLeft,
                  child: const Text(
                    'Classification - Public',
                    style: TextStyle(fontSize: 9.5, color: Colors.black54),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Org-resolved logo + titles (MOEHE assets only when that org has no custom logo).
  Widget _headerRow() {
    return ResolvedOrgHeader(
      siteId: inspection.siteId,
      language: language,
      siteNameAr: inspection.siteNameAr,
      siteNameEn: inspection.siteNameEn,
      buildingCode: inspection.buildingCode,
    );
  }

  Widget _titleBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: _gold,
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Text(
            _ar
                ? 'تقرير الفحص اليومي للمرافق'
                : 'Daily Facilities Inspection Report',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: _accentText,
            ),
          ),
          if (inspection.referenceNo.isNotEmpty ||
              inspection.templateVersionSnapshot != null) ...[
            const SizedBox(height: 2),
            Text(
              [
                if (inspection.referenceNo.isNotEmpty) inspection.referenceNo,
                if (inspection.templateVersionSnapshot != null)
                  _ar
                      ? 'إصدار القائمة ${inspection.templateVersionSnapshot}'
                      : 'Checklist v${inspection.templateVersionSnapshot}',
              ].join('  •  '),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: _accentText,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static const _inspectorLabelW = 108.0;

  Widget _metaGrid(WidgetRef ref) {
    final pin = inspection.pin.isNotEmpty ? inspection.pin : '—';
    final signed = inspection.signaturePath?.isNotEmpty == true;
    final signatureLabel = signed ? (_ar ? 'موقّع' : 'Signed') : '';

    // Name/Signature share label width. Parent RTL mirrors Rows: label at start
    // (right in Arabic), value toward the center.
    return Container(
      decoration: BoxDecoration(border: Border.all(color: _border)),
      child: Column(
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _metaLabel(_ar ? 'الموقع:' : 'Location:'),
                      Expanded(child: _metaValue(inspection.locationLabel)),
                    ],
                  ),
                ),
                _vRule(),
                Expanded(
                  flex: 5,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _metaLabel(
                        _ar ? 'اسم المفتش:' : 'Inspector Name:',
                        width: _inspectorLabelW,
                      ),
                      Expanded(
                        child: _metaValue(
                          inspection.inspectorName,
                          onChanged: onInspectorChanged,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _hRule(),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    children: [
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _metaLabel(_ar ? 'رقم القسيمة:' : 'Pin No.'),
                            Expanded(
                              child: _metaValue(
                                pin,
                                maxLines: 1,
                                fitToWidth: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _hRule(),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _metaLabel(_ar ? 'رقم المبنى:' : 'Bldg. No.'),
                            Expanded(
                              flex: 3,
                              child: _metaValue(
                                inspection.bldgNo,
                                align: TextAlign.center,
                                maxLines: 1,
                                fitToWidth: true,
                              ),
                            ),
                            _vRule(),
                            _metaLabel(
                              _ar ? 'الطابق:' : 'Floor no.',
                              width: 64,
                            ),
                            Expanded(
                              flex: 2,
                              child: _metaValue(
                                inspection.floorLabel,
                                onChanged: onFloorChanged,
                                align: TextAlign.center,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                _vRule(),
                Expanded(
                  flex: 5,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _metaLabel(
                        _ar ? 'توقيع المفتش:' : 'Inspector Signature:',
                        width: _inspectorLabelW,
                        action:
                            !readOnly &&
                                onClearSignature != null &&
                                (inspection.signaturePath == null ||
                                    inspection.signaturePath!.startsWith(
                                      'offline://',
                                    ))
                            ? IconButton(
                                key: const ValueKey(
                                  'clear-inspector-signature',
                                ),
                                tooltip: _ar
                                    ? 'مسح التوقيع'
                                    : 'Clear signature',
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                                color: _accentText,
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: onClearSignature,
                              )
                            : null,
                      ),
                      Expanded(child: _signatureCell(ref, signatureLabel)),
                      _vRule(),
                      SizedBox(
                        width: 120,
                        child: Column(
                          children: [
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _metaLabel(
                                    _ar ? 'التاريخ:' : 'Date',
                                    width: 44,
                                  ),
                                  Expanded(
                                    child: _metaValue(
                                      _formatMetaDate(
                                        inspection.inspectionDate,
                                      ),
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _hRule(),
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _metaLabel(
                                    _ar ? 'الوقت:' : 'Time:',
                                    width: 44,
                                  ),
                                  Expanded(
                                    child: _metaValue(
                                      inspection.inspectionTime,
                                      onChanged: onTimeChanged,
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _signatureCell(WidgetRef ref, String fallback) {
    // A saved signature always wins over an empty editor. Previously editable
    // Viewer records returned the drawing pad first, hiding the stored
    // signature even though signature_path and the Storage object were valid.
    if (signaturePreviewBytes != null && signaturePreviewBytes!.isNotEmpty) {
      return Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.all(2),
        alignment: Alignment.center,
        child: Image.memory(
          signaturePreviewBytes!,
          fit: BoxFit.fill,
          width: double.infinity,
          height: 40,
        ),
      );
    }

    final path = inspection.signaturePath;
    if (path == null || path.isEmpty) {
      if (!readOnly && signatureController != null) {
        return Padding(
          padding: const EdgeInsets.all(2),
          child: ChecklistSignaturePad(
            controller: signatureController!,
            height: 60,
            borderRadius: 2,
            borderColor: Colors.transparent,
            semanticLabel: _ar ? 'منطقة التوقيع' : 'Signature drawing area',
          ),
        );
      }
      return _metaValue('', align: TextAlign.center, minHeight: 44);
    }
    return FutureBuilder<Uint8List?>(
      future: ref.read(inspectionRepositoryProvider).downloadBytes(path),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final bytes = snap.data;
        if (bytes == null || bytes.isEmpty) {
          return Tooltip(
            message: _ar
                ? 'تعذر تحميل التوقيع المحفوظ'
                : 'Saved signature could not be loaded',
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              alignment: Alignment.center,
              child: const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFB91C1C),
                size: 22,
              ),
            ),
          );
        }
        final blue = recolorSignatureToBlueInk(bytes);
        return Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.all(2),
          alignment: Alignment.center,
          child: Image.memory(
            blue,
            fit: BoxFit.contain,
            width: double.infinity,
            height: 40,
            errorBuilder: (_, _, _) => Text(
              fallback,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        );
      },
    );
  }

  String _formatMetaDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yy = (d.year % 100).toString().padLeft(2, '0');
    return '$dd/$mm/$yy';
  }

  Widget _hRule() => Container(height: 1, color: _border);

  Widget _vRule() => Container(width: 1, color: _border);

  Widget _metaLabel(String text, {double width = 92, Widget? action}) {
    return Container(
      width: width,
      color: _gold,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Text(
              text,
              textAlign: TextAlign.start,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: _accentText,
              ),
            ),
          ),
          ?action,
        ],
      ),
    );
  }

  Widget _metaValue(
    String value, {
    ValueChanged<String>? onChanged,
    TextAlign? align,
    double minHeight = 26,
    int maxLines = 2,
    bool fitToWidth = false,
  }) {
    align ??= TextAlign.start;
    final style = const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      height: 1.15,
    );
    final boxAlign = align == TextAlign.center
        ? Alignment.center
        : AlignmentDirectional.centerStart;
    if (!readOnly && onChanged != null) {
      return Container(
        constraints: BoxConstraints(minHeight: minHeight),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        alignment: boxAlign,
        child: TextFormField(
          initialValue: value,
          onChanged: onChanged,
          style: style,
          textAlign: align,
          maxLines: 1,
          decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      );
    }
    Widget text = Text(
      value,
      textAlign: align,
      style: style,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      softWrap: maxLines > 1,
    );
    if (fitToWidth) {
      text = FittedBox(fit: BoxFit.scaleDown, alignment: boxAlign, child: text);
    }
    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      alignment: boxAlign,
      child: text,
    );
  }

  Widget _table(
    BuildContext context,
    WidgetRef ref,
    List<InspectionItem> items,
  ) {
    final narrow = !forceTableLayout && MediaQuery.sizeOf(context).width < 720;
    if (narrow) {
      return Container(
        decoration: BoxDecoration(border: Border.all(color: _border)),
        child: Column(
          children: [
            _tableHeader(narrow: true),
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) Container(height: 1, color: _border),
              _itemRowNarrow(context, ref, items[i]),
            ],
          ],
        ),
      );
    }

    // Table keeps header/body columns locked. Parent RTL places col 0 (م) on the right.
    final startAlign = TextAlign.start;
    return Table(
      border: TableBorder.all(color: _border, width: 1),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: const {
        0: FixedColumnWidth(40),
        1: FlexColumnWidth(5),
        2: FixedColumnWidth(36),
        3: FixedColumnWidth(36),
        4: FixedColumnWidth(36),
        5: FlexColumnWidth(4),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(color: _gold),
          children: [
            _th(_ar ? 'م' : 'Item'),
            _th(_ar ? 'الوصف' : 'Description', align: startAlign),
            _th(_ar ? 'نعم' : 'Yes'),
            _th(_ar ? 'لا' : 'No'),
            _th(_ar ? 'غ.م' : 'NA'),
            _th(
              _ar
                  ? 'إن كانت الإجابة لا، ما الإجراء؟'
                  : "If 'no', what are the actions taken?",
              align: startAlign,
              singleLine: true,
            ),
          ],
        ),
        for (var i = 0; i < items.length; i++)
          TableRow(
            children: [
              _itemIndexCell(context, items[i], isLast: i == items.length - 1),
              Padding(
                padding: const EdgeInsets.all(7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      items[i].descriptionFor(language),
                      textAlign: startAlign,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: Colors.black,
                      ),
                    ),
                    if (overdueItemIndexes.contains(items[i].itemIndex)) ...[
                      const SizedBox(height: 4),
                      _overdueChip(),
                    ],
                  ],
                ),
              ),
              _responseCell(items[i], ChecklistResponse.yes),
              _responseCell(items[i], ChecklistResponse.no),
              _responseCell(items[i], ChecklistResponse.na),
              _remarksCell(context, ref, items[i]),
            ],
          ),
      ],
    );
  }

  Widget _itemIndexCell(
    BuildContext context,
    InspectionItem item, {
    required bool isLast,
  }) {
    final label = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        '${item.itemIndex}',
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
    final canAdd = isLast && onAddItem != null;
    final canDelete = item.isCustom && onDeleteItem != null;
    if (readOnly || (!canAdd && !canDelete)) return label;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) => _showItemIndexMenu(
        context,
        details.globalPosition,
        item,
        canAdd: canAdd,
        canDelete: canDelete,
      ),
      onLongPressStart: (details) {
        Feedback.forLongPress(context);
        _showItemIndexMenu(
          context,
          details.globalPosition,
          item,
          canAdd: canAdd,
          canDelete: canDelete,
        );
      },
      child: Tooltip(
        message: _ar
            ? (canDelete
                  ? 'زر أيمن / ضغط مطول: إضافة أو حذف بند'
                  : 'زر أيمن / ضغط مطول: إضافة بند')
            : (canDelete
                  ? 'Right-click / long-press: add or delete item'
                  : 'Right-click / long-press: add item'),
        child: SizedBox(
          width: double.infinity,
          height: 44,
          child: Center(child: label),
        ),
      ),
    );
  }

  Future<void> _showItemIndexMenu(
    BuildContext context,
    Offset global,
    InspectionItem item, {
    required bool canAdd,
    required bool canDelete,
  }) async {
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        global.dx,
        global.dy,
        global.dx,
        global.dy,
      ),
      items: [
        if (canAdd)
          PopupMenuItem(
            value: 'add',
            child: Text(_ar ? 'إضافة بند جديد' : 'Add new item'),
          ),
        if (canDelete)
          PopupMenuItem(
            value: 'delete',
            child: Text(_ar ? 'حذف البند' : 'Delete item'),
          ),
      ],
    );
    if (selected == 'add') await onAddItem?.call();
    if (selected == 'delete') await onDeleteItem?.call(item);
  }

  Future<void> _showRemarksMenu(
    BuildContext context,
    Offset global,
    InspectionItem item,
  ) async {
    // Empty remarks area: add a new issue unit only.
    // Fix photos are added by tapping an existing issue thumb.
    if (onPickIssuePhoto == null) return;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        global.dx,
        global.dy,
        global.dx,
        global.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'add_issue',
          child: Text(_ar ? 'إضافة صورة مشكلة' : 'Add issue photo'),
        ),
      ],
    );
    if (selected == 'add_issue') {
      await onPickIssuePhoto?.call(item);
    }
  }

  /// Paired thumbs: tight gap inside a pair, wider gap between pairs.
  Widget _remarksPhotosStrip(
    BuildContext context,
    WidgetRef ref,
    InspectionItem item, {
    required bool hasRemark,
    required double maxWidth,
    required double maxHeight,
  }) {
    final pairs = item.photoPairs;
    if (pairs.isEmpty || maxWidth <= 0 || maxHeight <= 0) {
      return const SizedBox.shrink();
    }
    const pairGap = 1.0;
    const betweenGap = 5.0;
    const preferredW = 96.0 / 2.54; // ≥ 1 cm at ~96dpi
    var thumbCount = 0;
    for (final p in pairs) {
      if (p.hasIssue) thumbCount++;
      if (p.hasFix) thumbCount++;
    }
    if (thumbCount == 0) return const SizedBox.shrink();

    final betweenCount = (pairs.length - 1).clamp(0, 1000);
    var innerGaps = 0.0;
    for (final p in pairs) {
      final inPair = (p.hasIssue ? 1 : 0) + (p.hasFix ? 1 : 0);
      if (inPair > 1) innerGaps += pairGap;
    }
    final gapsTotal = innerGaps + betweenGap * betweenCount;
    final fitW = ((maxWidth - gapsTotal) / thumbCount).clamp(4.0, maxWidth);
    final w = fitW < preferredW ? fitW : preferredW;
    final h = hasRemark ? (maxHeight * 0.55).clamp(10.0, maxHeight) : maxHeight;

    return SizedBox(
      width: maxWidth,
      height: h,
      child: Row(
        children: [
          for (var pi = 0; pi < pairs.length; pi++) ...[
            if (pi > 0)
              Container(
                width: betweenGap,
                height: h,
                alignment: Alignment.center,
                child: Container(
                  width: 1,
                  height: h * 0.7,
                  color: Colors.black26,
                ),
              ),
            _pairThumbs(
              context,
              ref,
              item: item,
              pair: pairs[pi],
              unitIndex: pi + 1,
              thumbW: w,
              thumbH: h,
              pairGap: pairGap,
            ),
          ],
        ],
      ),
    );
  }

  Widget _pairThumbs(
    BuildContext context,
    WidgetRef ref, {
    required InspectionItem item,
    required InspectionPhotoPair pair,
    required int unitIndex,
    required double thumbW,
    required double thumbH,
    required double pairGap,
  }) {
    final children = <Widget>[];
    if (pair.hasIssue) {
      final openAge =
          issueOpenTooltipsByPath[storagePathOf(pair.issuePath!)] ?? '';
      final unit = photoPairLabel(unitIndex, arabic: _ar);
      final issueTip = openAge.isEmpty ? unit : '$unit\n$openAge';
      children.add(
        _photoThumb(
          context,
          ref,
          path: pair.issuePath!,
          border: _problemRed,
          width: thumbW,
          height: thumbH,
          tooltip: issueTip,
          preferOuterTooltip: true,
          onClear:
              !readOnly &&
                  onClearIssuePhoto != null &&
                  pair.issuePath!.startsWith('offline://')
              ? () async {
                  await onClearIssuePhoto!(item, pair.issuePath!, pair.id);
                }
              : null,
          onSecondary: !readOnly && onPickFixPhoto != null && !pair.hasFix
              ? () async {
                  await onPickFixPhoto!(item, pair.id);
                }
              : null,
        ),
      );
    }
    if (pair.hasIssue && pair.hasFix) {
      children.add(SizedBox(width: pairGap));
    }
    if (pair.hasFix) {
      children.add(
        _photoThumb(
          context,
          ref,
          path: pair.fixPath!,
          border: _fixGreen,
          width: thumbW,
          height: thumbH,
          tooltip: photoPairLabel(unitIndex, arabic: _ar),
          onClear:
              !readOnly &&
                  onClearFixPhoto != null &&
                  pair.fixPath!.startsWith('offline://')
              ? () async {
                  await onClearFixPhoto!(item, pair.fixPath!, pair.id);
                }
              : null,
        ),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }

  Widget _th(
    String text, {
    TextAlign align = TextAlign.center,
    bool singleLine = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
      child: Text(
        text,
        textAlign: align,
        maxLines: singleLine ? 1 : 3,
        softWrap: !singleLine,
        overflow: singleLine ? TextOverflow.ellipsis : TextOverflow.visible,
        style: TextStyle(
          fontSize: singleLine ? 9.5 : 11,
          fontWeight: FontWeight.w800,
          height: 1.15,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _tableHeader({required bool narrow}) {
    const style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      color: Colors.white,
    );
    return Container(
      color: _gold,
      padding: const EdgeInsets.all(8),
      child: Text(
        _ar
            ? 'البند | الوصف | نعم / لا / غ.م | الملاحظات والصور'
            : 'Item | Description | Yes / No / NA | Remarks & Photos',
        style: style,
      ),
    );
  }

  /// HTML-style ✓ — ideal answer is blue; opposite is red. Empty until chosen.
  Widget _responseCell(InspectionItem item, ChecklistResponse column) {
    final selected = item.response?.shortCode == column.shortCode;
    final color = switch (item.checkColorFor(column)) {
      ColorCode.ok => _okBlue,
      ColorCode.problem => _problemRed,
      ColorCode.na => Colors.black87,
      ColorCode.empty => _emptyGray,
    };
    return InkWell(
      onTap: readOnly
          ? null
          : () {
              if (selected) {
                onResponseChanged?.call(item, null);
              } else {
                onResponseChanged?.call(item, column);
              }
            },
      child: SizedBox(
        height: 36,
        child: Center(
          child: selected
              ? Text(
                  '✓',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1,
                    color: color,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  Widget _remarksCell(
    BuildContext context,
    WidgetRef ref,
    InspectionItem item,
  ) {
    final hasRemark = item.actionsTaken.trim().isNotEmpty;
    final hasPhotos = item.remarkPhotos.isNotEmpty;
    final canMenu =
        !readOnly && (onPickIssuePhoto != null || onPickFixPhoto != null);

    // Match empty rows: fixed remarks box; content shrinks to fit.
    const cellH = 40.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cellW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 160.0;
        final innerW = (cellW - 8).clamp(40.0, cellW);
        final innerH = cellH - 8;

        if (readOnly && !hasRemark && !hasPhotos) {
          return const SizedBox(height: cellH);
        }

        return SizedBox(
          height: cellH,
          width: cellW,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: ClipRect(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (hasPhotos)
                    _remarksPhotosStrip(
                      context,
                      ref,
                      item,
                      hasRemark: hasRemark,
                      maxWidth: innerW - (canMenu && !readOnly ? 28 : 0),
                      maxHeight: (!hasRemark && !readOnly)
                          ? (innerH - 22).clamp(12.0, innerH)
                          : innerH,
                    ),
                  if (hasPhotos && (hasRemark || !readOnly))
                    const SizedBox(height: 2),
                  if (readOnly && hasRemark)
                    Expanded(
                      child: Text(
                        item.actionsTaken,
                        style: const TextStyle(fontSize: 10),
                        maxLines: hasPhotos ? 2 : 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (!readOnly)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onLongPressStart: canMenu
                            ? (details) {
                                Feedback.forLongPress(context);
                                _showRemarksMenu(
                                  context,
                                  details.globalPosition,
                                  item,
                                );
                              }
                            : null,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _BlankRemarksField(
                                key: ValueKey(
                                  'remarks-${item.id ?? item.itemIndex}',
                                ),
                                initialValue: item.actionsTaken,
                                onChanged: (v) =>
                                    onActionsChanged?.call(item, v),
                                onLongPressMenu: canMenu
                                    ? (global) => _showRemarksMenu(
                                        context,
                                        global,
                                        item,
                                      )
                                    : null,
                              ),
                            ),
                            if (canMenu)
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                                tooltip: _ar
                                    ? 'إضافة صورة مشكلة'
                                    : 'Add issue photo',
                                icon: Icon(
                                  Icons.add_a_photo_outlined,
                                  size: 16,
                                  color: _problemRed,
                                ),
                                onPressed: () async {
                                  await onPickIssuePhoto?.call(item);
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openPhotoViewer(
    BuildContext context,
    WidgetRef ref,
    String path,
  ) async {
    onOpenPhoto?.call(path);
    final repo = ref.read(inspectionRepositoryProvider);
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.black87,
          insetPadding: const EdgeInsets.all(16),
          child: FutureBuilder<({Uint8List? bytes, String? url})>(
            future: () async {
              final bytes = await repo.downloadBytes(path);
              if (bytes != null && bytes.isNotEmpty) {
                return (bytes: bytes, url: null);
              }
              final url = await repo.signedUrl(path);
              return (bytes: null, url: url);
            }(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _ar ? 'تعذّر فتح الصورة' : 'Could not open photo',
                    style: const TextStyle(color: Colors.white),
                  ),
                );
              }
              if (snap.connectionState != ConnectionState.done) {
                return const SizedBox(
                  width: 280,
                  height: 280,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final data = snap.data;
              final bytes = data?.bytes;
              final url = data?.url;
              Widget image;
              if (bytes != null && bytes.isNotEmpty) {
                image = Image.memory(bytes, fit: BoxFit.contain);
              } else if (url != null && url.isNotEmpty) {
                image = Image.network(url, fit: BoxFit.contain);
              } else {
                image = Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _ar ? 'تعذّر فتح الصورة' : 'Could not open photo',
                    style: const TextStyle(color: Colors.white),
                  ),
                );
              }
              return Stack(
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 900,
                      maxHeight: 700,
                    ),
                    child: InteractiveViewer(child: image),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _photoThumb(
    BuildContext context,
    WidgetRef ref, {
    required String path,
    required Color border,
    Future<void> Function()? onClear,
    Future<void> Function()? onSecondary,
    String? tooltip,
    bool preferOuterTooltip = false,
    double? width,
    double? height,
  }) {
    final thumb = _OpenablePhotoThumb(
      path: path,
      border: border,
      arabic: _ar,
      width: width ?? _photoW,
      height: height ?? _photoH,
      onOpen: () => _openPhotoViewer(context, ref, path),
      onClear: onClear,
      onSecondary: onSecondary,
      signedUrlFuture: ref.read(inspectionRepositoryProvider).signedUrl(path),
      suppressInnerTooltip:
          preferOuterTooltip && tooltip != null && tooltip.trim().isNotEmpty,
    );
    if (tooltip == null || tooltip.isEmpty) return thumb;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: thumb,
    );
  }

  Widget _overdueChip() {
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFFB91C1C),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _ar ? 'متأخر' : 'Overdue',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _itemRowNarrow(
    BuildContext context,
    WidgetRef ref,
    InspectionItem item,
  ) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${item.itemIndex}. ${item.descriptionFor(language)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              if (overdueItemIndexes.contains(item.itemIndex)) _overdueChip(),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _responseCell(item, ChecklistResponse.yes),
              Text(
                _ar ? ' نعم  ' : ' Yes  ',
                style: const TextStyle(fontSize: 11),
              ),
              _responseCell(item, ChecklistResponse.no),
              Text(
                _ar ? ' لا  ' : ' No  ',
                style: const TextStyle(fontSize: 11),
              ),
              _responseCell(item, ChecklistResponse.na),
              Text(_ar ? ' غ.م' : ' NA', style: const TextStyle(fontSize: 11)),
            ],
          ),
          _remarksCell(context, ref, item),
        ],
      ),
    );
  }

  Widget _footerLogos() {
    return ResolvedFooterLogos(siteId: inspection.siteId, language: language);
  }
}

/// Completely blank until typed — no hint, border, or placeholder.
class _BlankRemarksField extends StatefulWidget {
  const _BlankRemarksField({
    super.key,
    required this.initialValue,
    required this.onChanged,
    this.onLongPressMenu,
  });

  final String initialValue;
  final ValueChanged<String> onChanged;
  final ValueChanged<Offset>? onLongPressMenu;

  @override
  State<_BlankRemarksField> createState() => _BlankRemarksFieldState();
}

class _BlankRemarksFieldState extends State<_BlankRemarksField> {
  late final TextEditingController _controller;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focus = FocusNode()..addListener(() => setState(() {}));
    _controller.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(covariant _BlankRemarksField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue &&
        widget.initialValue != _controller.text) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  bool get _active => _controller.text.trim().isNotEmpty || _focus.hasFocus;

  @override
  Widget build(BuildContext context) {
    // Disable text-selection long-press so cell/photo menus receive it on
    // phones (right-click still works on desktop via the parent detector).
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPressStart: widget.onLongPressMenu == null
          ? null
          : (details) {
              Feedback.forLongPress(context);
              widget.onLongPressMenu!(details.globalPosition);
            },
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        enableInteractiveSelection: widget.onLongPressMenu == null,
        style: TextStyle(
          fontSize: 11,
          height: 1.3,
          color: _active ? Colors.black : Colors.transparent,
        ),
        maxLines: null,
        minLines: 1,
        cursorColor: _active ? const Color(0xFF1F4E79) : Colors.transparent,
        onChanged: widget.onChanged,
        decoration: InputDecoration(
          isDense: true,
          isCollapsed: !_active,
          hintText: null,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: _active
              ? const EdgeInsets.symmetric(horizontal: 2, vertical: 4)
              : EdgeInsets.zero,
        ),
      ),
    );
  }
}

/// Desktop-safe photo thumb: mouse clicks use [Listener] (gesture-arena free).
class _OpenablePhotoThumb extends StatefulWidget {
  const _OpenablePhotoThumb({
    required this.path,
    required this.border,
    required this.arabic,
    required this.width,
    required this.height,
    required this.onOpen,
    required this.signedUrlFuture,
    this.onClear,
    this.onSecondary,
    this.suppressInnerTooltip = false,
  });

  final String path;
  final Color border;
  final bool arabic;
  final double width;
  final double height;
  final Future<void> Function() onOpen;
  final Future<String?> signedUrlFuture;
  final Future<void> Function()? onClear;

  /// e.g. add fix for this issue pair (long-press menu when present).
  final Future<void> Function()? onSecondary;
  final bool suppressInnerTooltip;

  @override
  State<_OpenablePhotoThumb> createState() => _OpenablePhotoThumbState();
}

class _OpenablePhotoThumbState extends State<_OpenablePhotoThumb> {
  int? _primaryPointer;
  bool _opening = false;
  bool _suppressOpen = false;

  Future<void> _open() async {
    if (_opening || _suppressOpen) return;
    _opening = true;
    try {
      await widget.onOpen();
    } finally {
      _opening = false;
    }
  }

  Future<void> _showActionMenu(Offset global) async {
    final onClear = widget.onClear;
    final onSecondary = widget.onSecondary;
    _suppressOpen = true;
    _primaryPointer = null;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        global.dx,
        global.dy,
        global.dx,
        global.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'open',
          child: Text(widget.arabic ? 'فتح الصورة' : 'Open photo'),
        ),
        if (onSecondary != null)
          PopupMenuItem(
            value: 'fix',
            child: Text(
              widget.arabic
                  ? 'إضافة صورة إصلاح لهذه الوحدة'
                  : 'Add fix photo for this unit',
            ),
          ),
        if (onClear != null)
          PopupMenuItem(
            value: 'del',
            child: Text(widget.arabic ? 'حذف هذه الصورة' : 'Delete this photo'),
          ),
      ],
    );
    if (action == 'open') await widget.onOpen();
    if (action == 'fix') await onSecondary?.call();
    if (action == 'del') await onClear?.call();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _suppressOpen = false;
  }

  bool get _hasActions => widget.onClear != null || widget.onSecondary != null;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: widget.signedUrlFuture,
      builder: (context, snap) {
        final url = snap.data;
        final thumb = Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            border: Border.all(color: widget.border, width: 2),
            borderRadius: BorderRadius.circular(2),
            color: Colors.white,
          ),
          clipBehavior: Clip.antiAlias,
          child: url == null
              ? Icon(Icons.image, size: 12, color: widget.border)
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      url,
                      fit: BoxFit.cover,
                      cacheWidth: 96,
                      cacheHeight: 144,
                      filterQuality: FilterQuality.low,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 7,
                        height: 7,
                        color: widget.border,
                      ),
                    ),
                  ],
                ),
        );

        // Tap (or long-press) shows actions when editable; otherwise opens photo.
        final interactive = MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) {
              final isPrimaryMouse =
                  event.kind == PointerDeviceKind.mouse &&
                  event.buttons == kPrimaryMouseButton;
              final isTouchLike =
                  event.kind == PointerDeviceKind.touch ||
                  event.kind == PointerDeviceKind.stylus ||
                  event.kind == PointerDeviceKind.trackpad ||
                  event.kind == PointerDeviceKind.unknown;
              if (!_suppressOpen && (isPrimaryMouse || isTouchLike)) {
                _primaryPointer = event.pointer;
              } else {
                _primaryPointer = null;
              }
            },
            onPointerCancel: (event) {
              if (_primaryPointer == event.pointer) _primaryPointer = null;
            },
            onPointerUp: (event) {
              if (_primaryPointer != event.pointer) return;
              _primaryPointer = null;
              if (_hasActions) {
                final box = context.findRenderObject() as RenderBox?;
                final pos =
                    box?.localToGlobal(
                      Offset(box.size.width / 2, box.size.height / 2),
                    ) ??
                    Offset.zero;
                _showActionMenu(pos);
              } else {
                _open();
              }
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onSecondaryTapDown: _hasActions
                  ? (details) => _showActionMenu(details.globalPosition)
                  : null,
              onLongPressStart: _hasActions
                  ? (details) {
                      Feedback.forLongPress(context);
                      _showActionMenu(details.globalPosition);
                    }
                  : null,
              child: thumb,
            ),
          ),
        );
        if (widget.suppressInnerTooltip) return interactive;
        return Tooltip(
          message: _hasActions
              ? (widget.arabic ? 'خيارات الصورة' : 'Photo actions')
              : (widget.arabic ? 'فتح الصورة' : 'Open photo'),
          waitDuration: const Duration(milliseconds: 600),
          child: interactive,
        );
      },
    );
  }
}
