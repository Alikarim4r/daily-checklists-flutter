import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/enums.dart';
import '../models/inspection.dart';
import '../providers/providers.dart';

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
    this.onOpenPhoto,
    this.trailingHeader,
    this.forceTableLayout = false,
    this.overdueItemIndexes = const {},
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
  final Future<void> Function(InspectionItem item)? onPickIssuePhoto;
  final Future<void> Function(InspectionItem item)? onPickFixPhoto;
  final void Function(String storagePath)? onOpenPhoto;
  final Widget? trailingHeader;
  final bool forceTableLayout;
  /// Item indexes flagged overdue by org policy (ongoing problem streak).
  final Set<int> overdueItemIndexes;

  static const _gold = Color(0xFFE8C547);
  static const _border = Color(0xFF000000);
  static const _okBlue = Color(0xFF3B82F6);
  static const _problemRed = Color(0xFFEF4444);
  static const _emptyGray = Color(0xFFCBD5E1);

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

    return Directionality(
      textDirection: ui.TextDirection.ltr,
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
              style: const TextStyle(fontSize: 10.5, height: 1.4),
            ),
            const SizedBox(height: 14),
            _footerLogos(),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Classification - Public',
                style: TextStyle(fontSize: 9.5, color: Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Matches ViewerEditV2: left bilingual titles, right MOEHE logo.
  Widget _headerRow() {
    return Directionality(
      textDirection: ui.TextDirection.ltr,
      child: Container(
        padding: const EdgeInsets.only(bottom: 8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _border, width: 1)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: _ar
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    _ar
                        ? 'خدمة الإدارة المتكاملة للمرافق لصالح وزارة التربية والتعليم والتعليم العالي'
                        : 'Integrated Facilities Management Service for MOEHE',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                      height: 1.25,
                    ),
                    textAlign: _ar ? TextAlign.right : TextAlign.left,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _ar
                        ? 'قائمة الفحص اليومي للمرافق - ${inspection.siteNameAr.isNotEmpty ? inspection.siteNameAr : inspection.buildingCode}'
                        : 'Facilities Daily Inspection Checklist - ${inspection.siteNameEn.isNotEmpty ? inspection.siteNameEn : inspection.buildingCode}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                      height: 1.25,
                    ),
                    textAlign: _ar ? TextAlign.right : TextAlign.left,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Image.asset(
              'assets/branding/moehe_logo.png',
              package: 'checklist_shared',
              height: 40,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox(
                height: 40,
                width: 120,
                child: Center(
                  child: Text(
                    'MOEHE',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
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
      child: Text(
        _ar ? 'تقرير الفحص اليومي للمرافق' : 'Daily Facilities Inspection Report',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  static const _inspectorLabelW = 108.0;

  Widget _metaGrid(WidgetRef ref) {
    final pin = inspection.pin.isNotEmpty ? inspection.pin : '—';
    final signed = inspection.signaturePath?.isNotEmpty == true;
    final signatureLabel = signed ? (_ar ? 'موقّع' : 'Signed') : '';

    // Compact PDF layout — Name and Signature labels share the same width
    // so their value columns line up.
    return Directionality(
      textDirection: ui.TextDirection.ltr,
      child: Container(
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
                        Expanded(
                          child: _metaValue(inspection.locationLabel),
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
                              _metaLabel(_ar ? 'رقم القسيمة' : 'Pin No.'),
                              Expanded(child: _metaValue(pin)),
                            ],
                          ),
                        ),
                        _hRule(),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _metaLabel(_ar ? 'رقم المبنى' : 'Bldg. No.'),
                              SizedBox(
                                width: 36,
                                child: _metaValue(
                                  inspection.bldgNo,
                                  align: TextAlign.center,
                                ),
                              ),
                              _vRule(),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    _ar ? 'الطابق' : 'Floor no.',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: _metaValue(
                                  inspection.floorLabel,
                                  onChanged: onFloorChanged,
                                  align: TextAlign.center,
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
                        ),
                        Expanded(
                          child: _signatureCell(ref, signatureLabel),
                        ),
                        _vRule(),
                        SizedBox(
                          width: 148,
                          child: Column(
                            children: [
                              Expanded(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _metaLabel(
                                      _ar ? 'التاريخ' : 'Date',
                                      width: 48,
                                    ),
                                    Expanded(
                                      child: _metaValue(
                                        _formatMetaDate(
                                          inspection.inspectionDate,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _hRule(),
                              Expanded(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _metaLabel(
                                      _ar ? 'الوقت:' : 'Time:',
                                      width: 48,
                                    ),
                                    Expanded(
                                      child: _metaValue(
                                        inspection.inspectionTime,
                                        onChanged: onTimeChanged,
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
      ),
    );
  }

  Widget _signatureCell(WidgetRef ref, String fallback) {
    final path = inspection.signaturePath;
    if (path == null || path.isEmpty) {
      return _metaValue('', align: TextAlign.center, minHeight: 44);
    }
    return FutureBuilder<String?>(
      future: ref.read(inspectionRepositoryProvider).signedUrl(path),
      builder: (context, snap) {
        final url = snap.data;
        if (url == null || url.isEmpty) {
          return _metaValue(fallback, align: TextAlign.center, minHeight: 44);
        }
        return Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.all(2),
          alignment: Alignment.center,
          child: Image.network(
            url,
            fit: BoxFit.contain,
            height: 40,
            errorBuilder: (_, __, ___) => Text(
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

  Widget _metaLabel(String text, {double width = 92}) {
    return Container(
      width: width,
      color: _gold,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _metaValue(
    String value, {
    ValueChanged<String>? onChanged,
    TextAlign align = TextAlign.left,
    double minHeight = 26,
  }) {
    final style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      height: 1.15,
    );
    if (!readOnly && onChanged != null) {
      return Container(
        constraints: BoxConstraints(minHeight: minHeight),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        alignment: Alignment.centerLeft,
        child: TextFormField(
          initialValue: value,
          onChanged: onChanged,
          style: style,
          textAlign: align,
          decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      );
    }
    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      alignment: align == TextAlign.center
          ? Alignment.center
          : Alignment.centerLeft,
      child: Text(value, textAlign: align, style: style),
    );
  }

  Widget _table(
    BuildContext context,
    WidgetRef ref,
    List<InspectionItem> items,
  ) {
    final narrow =
        !forceTableLayout && MediaQuery.sizeOf(context).width < 720;
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

    // Table keeps header/body columns locked together (unlike separate Rows
    // where missing vertical dividers shifted ✓ under the wrong Yes/No/NA).
    return Directionality(
      textDirection: ui.TextDirection.ltr,
      child: Table(
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
            decoration: const BoxDecoration(color: _gold),
            children: [
              _th(_ar ? 'م' : 'Item'),
              _th(_ar ? 'الوصف' : 'Description', align: TextAlign.left),
              _th(_ar ? 'نعم' : 'Yes'),
              _th(_ar ? 'لا' : 'No'),
              _th(_ar ? 'غ.م' : 'NA'),
              _th(
                _ar ? 'إن كانت الإجابة لا، ما الإجراء؟' : "If 'no', what are the actions taken?",
                align: TextAlign.left,
                singleLine: true,
              ),
            ],
          ),
          for (final item in items)
            TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '${item.itemIndex}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(7),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.descriptionFor(language),
                        style: const TextStyle(fontSize: 12, height: 1.35),
                      ),
                      if (overdueItemIndexes.contains(item.itemIndex)) ...[
                        const SizedBox(height: 4),
                        _overdueChip(),
                      ],
                    ],
                  ),
                ),
                _responseCell(item, ChecklistResponse.yes),
                _responseCell(item, ChecklistResponse.no),
                _responseCell(item, ChecklistResponse.na),
                _remarksCell(context, ref, item),
              ],
            ),
        ],
      ),
    );
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
        ),
      ),
    );
  }

  Widget _tableHeader({required bool narrow}) {
    const style = TextStyle(fontSize: 11, fontWeight: FontWeight.w800);
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
                // Clear back to empty.
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

  Widget _remarksCell(BuildContext context, WidgetRef ref, InspectionItem item) {
    final hasRemark = item.actionsTaken.trim().isNotEmpty;
    final photoWidgets = <Widget>[
      _photoThumb(
        ref,
        path: item.issueImagePath,
        border: _problemRed,
        label: _ar ? 'مشكلة' : 'Problem',
        onPick: !readOnly && item.isProblem && onPickIssuePhoto != null
            ? () => onPickIssuePhoto!(item)
            : null,
        showPickButton: !readOnly && item.isProblem,
      ),
      _photoThumb(
        ref,
        path: item.fixImagePath,
        border: const Color(0xFF28A745),
        label: _ar ? 'إصلاح' : 'Repair',
        onPick: !readOnly && item.isProblem && onPickFixPhoto != null
            ? () => onPickFixPhoto!(item)
            : null,
        showPickButton:
            !readOnly && item.isProblem && item.issueImagePath != null,
      ),
    ].where((w) => w is! SizedBox).toList();

    // Viewer: nothing in remarks unless entry wrote text (photos optional).
    if (readOnly) {
      if (!hasRemark && photoWidgets.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasRemark)
              Text(item.actionsTaken, style: const TextStyle(fontSize: 11)),
            if (photoWidgets.isNotEmpty) ...[
              if (hasRemark) const SizedBox(height: 4),
              Wrap(spacing: 4, runSpacing: 4, children: photoWidgets),
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.all(hasRemark || photoWidgets.isNotEmpty ? 4 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BlankRemarksField(
            key: ValueKey('remarks-${item.id ?? item.itemIndex}'),
            initialValue: item.actionsTaken,
            onChanged: (v) => onActionsChanged?.call(item, v),
          ),
          if (photoWidgets.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(spacing: 4, runSpacing: 4, children: photoWidgets),
          ],
        ],
      ),
    );
  }

  Widget _photoThumb(
    WidgetRef ref, {
    required String? path,
    required Color border,
    required String label,
    Future<void> Function()? onPick,
    required bool showPickButton,
  }) {
    if (path == null || path.isEmpty) {
      if (!showPickButton || onPick == null) return const SizedBox.shrink();
      return InkWell(
        onTap: () => onPick(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: border, width: 1.5),
            borderRadius: BorderRadius.circular(4),
            color: border.withValues(alpha: 0.08),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: border,
            ),
          ),
        ),
      );
    }
    return FutureBuilder<String?>(
      future: ref.read(inspectionRepositoryProvider).signedUrl(path),
      builder: (context, snap) {
        final url = snap.data;
        return InkWell(
          onTap: () {
            if (url == null) return;
            onOpenPhoto?.call(path);
            showDialog<void>(
              context: context,
              builder: (context) => Dialog(
                backgroundColor: Colors.black87,
                child: InteractiveViewer(
                  child: Image.network(url, fit: BoxFit.contain),
                ),
              ),
            );
          },
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              border: Border.all(color: border, width: 2),
              borderRadius: BorderRadius.circular(4),
              color: Colors.white,
            ),
            clipBehavior: Clip.antiAlias,
            child: url == null
                ? Icon(Icons.image, size: 18, color: border)
                : Image.network(url, fit: BoxFit.cover),
          ),
        );
      },
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
            textDirection: ui.TextDirection.ltr,
            children: [
              _responseCell(item, ChecklistResponse.yes),
              const Text(' Yes  ', style: TextStyle(fontSize: 11)),
              _responseCell(item, ChecklistResponse.no),
              const Text(' No  ', style: TextStyle(fontSize: 11)),
              _responseCell(item, ChecklistResponse.na),
              const Text(' NA', style: TextStyle(fontSize: 11)),
            ],
          ),
          _remarksCell(context, ref, item),
        ],
      ),
    );
  }

  Widget _footerLogos() {
    return Directionality(
      textDirection: ui.TextDirection.ltr,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Image.asset(
            'assets/branding/logo_waseef.png',
            package: 'checklist_shared',
            height: 28,
            errorBuilder: (_, __, ___) => const SizedBox(height: 28),
          ),
          const Text(
            '© MOEHE Facilities',
            style: TextStyle(fontSize: 9, color: Colors.black54),
          ),
          Image.asset(
            'assets/branding/logo_footer2.png',
            package: 'checklist_shared',
            height: 32,
            errorBuilder: (_, __, ___) => const SizedBox(height: 32),
          ),
        ],
      ),
    );
  }
}

/// Completely blank until typed — no hint, border, or placeholder.
class _BlankRemarksField extends StatefulWidget {
  const _BlankRemarksField({
    super.key,
    required this.initialValue,
    required this.onChanged,
  });

  final String initialValue;
  final ValueChanged<String> onChanged;

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

  bool get _active =>
      _controller.text.trim().isNotEmpty || _focus.hasFocus;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focus,
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
    );
  }
}
