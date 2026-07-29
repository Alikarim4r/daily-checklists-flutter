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

  static const _gold = Color(0xFFE8C547);
  static const _border = Color(0xFF000000);
  static const _okBlue = Color(0xFF3B82F6);
  static const _problemRed = Color(0xFFEF4444);
  static const _emptyGray = Color(0xFFCBD5E1);

  bool get _ar => language == 'ar';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Directionality(
      textDirection: _ar ? ui.TextDirection.rtl : ui.TextDirection.ltr,
      child: Container(
        color: Colors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _headerRow(),
            const SizedBox(height: 8),
            _titleBanner(),
            const SizedBox(height: 10),
            _metaGrid(),
            if (trailingHeader != null) ...[
              const SizedBox(height: 8),
              trailingHeader!,
            ],
            const SizedBox(height: 12),
            _table(context, ref),
            const SizedBox(height: 14),
            Text(
              _ar
                  ? 'توفر هذه القائمة المتطلبات الأساسية للفحوصات اليومية لخدمات البنية. عند تسجيل «لا» لأي بند أعلاه، يجب اتخاذ إجراء فوري لمعالجة المشكلة لضمان استمرار التشغيل الآمن.'
                  : 'This checklist provides the basic requirements for hard services operations daily checks. Should a "No" be recorded for any of the above checklist items, immediate action to be taken to address the issues, to have safe, continued operation.',
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
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: _border),
          bottom: BorderSide(color: _border),
        ),
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

  Widget _metaGrid() {
    final pin = inspection.pin.isNotEmpty ? inspection.pin : '—';
    return Container(
      decoration: BoxDecoration(border: Border.all(color: _border)),
      child: Column(
        children: [
          _metaPair(
            _metaCell(_ar ? 'الموقع' : 'Location', inspection.locationLabel),
            _metaCell(_ar ? 'رقم القسيمة' : 'Pin No.', pin),
          ),
          _metaPair(
            _metaCell(_ar ? 'رقم المبنى' : 'Bldg. No.', inspection.bldgNo),
            _metaEditable(
              _ar ? 'رقم الطابق' : 'Floor no.',
              inspection.floorLabel,
              onFloorChanged,
            ),
          ),
          _metaPair(
            _metaEditable(
              _ar ? 'اسم المفتش' : 'Inspector Name',
              inspection.inspectorName,
              onInspectorChanged,
            ),
            _metaCell(
              _ar ? 'توقيع المفتش' : 'Inspector Signature',
              inspection.signaturePath?.isNotEmpty == true
                  ? (_ar ? 'موقّع' : 'Signed')
                  : '',
            ),
          ),
          _metaPair(
            _metaCell(_ar ? 'التاريخ' : 'Date', inspection.dateIso),
            _metaEditable(
              _ar ? 'الوقت' : 'Time',
              inspection.inspectionTime,
              onTimeChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaPair(Widget a, Widget b) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: a),
          Container(width: 1, color: _border),
          Expanded(child: b),
        ],
      ),
    );
  }

  Widget _metaCell(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: _gold,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ),
        Container(
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Text(
            value,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _metaEditable(
    String label,
    String value,
    ValueChanged<String>? onChanged,
  ) {
    if (readOnly || onChanged == null) return _metaCell(label, value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: _gold,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ),
        TextFormField(
          initialValue: value,
          onChanged: onChanged,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          ),
        ),
      ],
    );
  }

  Widget _table(BuildContext context, WidgetRef ref) {
    final narrow =
        !forceTableLayout && MediaQuery.sizeOf(context).width < 720;
    return Container(
      decoration: BoxDecoration(border: Border.all(color: _border)),
      child: Column(
        children: [
          _tableHeader(narrow: narrow),
          for (var i = 0; i < inspection.items.length; i++) ...[
            if (i > 0) Container(height: 1, color: _border),
            _itemRow(context, ref, inspection.items[i], narrow: narrow),
          ],
        ],
      ),
    );
  }

  Widget _tableHeader({required bool narrow}) {
    const style = TextStyle(fontSize: 11, fontWeight: FontWeight.w800);
    if (narrow) {
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
    return Container(
      color: _gold,
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
      child: Row(
        children: [
          _hCell(40, _ar ? 'م' : 'Item', style),
          Expanded(flex: 5, child: Text(_ar ? 'الوصف' : 'Description', style: style)),
          _hCell(36, _ar ? 'نعم' : 'Yes', style),
          _hCell(36, _ar ? 'لا' : 'No', style),
          _hCell(36, _ar ? 'غ.م' : 'NA', style),
          Expanded(
            flex: 3,
            child: Text(
              _ar
                  ? 'إن كانت الإجابة لا، ما الإجراء؟'
                  : "If 'no', what are the actions taken?",
              style: style,
            ),
          ),
        ],
      ),
    );
  }

  Widget _hCell(double w, String t, TextStyle style) => SizedBox(
        width: w,
        child: Text(t, textAlign: TextAlign.center, style: style),
      );

  /// HTML-style ✓ mark with getCheckColor colors.
  Widget _responseCell(InspectionItem item, ChecklistResponse column) {
    final code = item.checkColorFor(column);
    final Color color = switch (code) {
      ColorCode.ok => _okBlue,
      ColorCode.problem => _problemRed,
      ColorCode.na => Colors.black,
      ColorCode.empty => _emptyGray,
    };
    final mark = item.response == column ? '✓' : '';
    return InkWell(
      onTap: readOnly
          ? null
          : () {
              final next = item.response == column ? null : column;
              onResponseChanged?.call(item, next);
            },
      child: SizedBox(
        width: 36,
        height: 40,
        child: Center(
          child: Text(
            mark.isEmpty ? '·' : mark,
            style: TextStyle(
              fontSize: mark.isEmpty ? 14 : 18,
              fontWeight: FontWeight.w900,
              color: color,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _remarksCell(BuildContext context, WidgetRef ref, InspectionItem item) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!readOnly)
            TextFormField(
              initialValue: item.actionsTaken,
              onChanged: (v) => onActionsChanged?.call(item, v),
              style: const TextStyle(fontSize: 11),
              decoration: InputDecoration(
                isDense: true,
                hintText: _ar ? 'ملاحظات / HQHS-…' : 'Remarks / HQHS-…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(2),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              ),
            )
          else if (item.actionsTaken.isNotEmpty)
            Text(item.actionsTaken, style: const TextStyle(fontSize: 11)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
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
            ],
          ),
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

  Widget _itemRow(
    BuildContext context,
    WidgetRef ref,
    InspectionItem item, {
    required bool narrow,
  }) {
    if (narrow) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${item.itemIndex}. ${item.descriptionFor(language)}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _responseCell(item, ChecklistResponse.yes),
                const Text('Yes', style: TextStyle(fontSize: 11)),
                _responseCell(item, ChecklistResponse.no),
                const Text('No', style: TextStyle(fontSize: 11)),
                _responseCell(item, ChecklistResponse.na),
                const Text('NA', style: TextStyle(fontSize: 11)),
              ],
            ),
            _remarksCell(context, ref, item),
          ],
        ),
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 40,
            child: Center(
              child: Text(
                '${item.itemIndex}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          Container(width: 1, color: _border),
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: Text(
                item.descriptionFor(language),
                style: const TextStyle(fontSize: 12, height: 1.35),
              ),
            ),
          ),
          Container(width: 1, color: _border),
          _responseCell(item, ChecklistResponse.yes),
          Container(width: 1, color: _border),
          _responseCell(item, ChecklistResponse.no),
          Container(width: 1, color: _border),
          _responseCell(item, ChecklistResponse.na),
          Container(width: 1, color: _border),
          Expanded(flex: 3, child: _remarksCell(context, ref, item)),
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
