import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';

import 'checkview_tokens.dart';
import 'checkview_widgets.dart';

/// A CheckView-only filter surface. Every selectable dimension is derived from
/// the authorized location scope; it never queries or exposes other tenants.
class CvLocationFilterPanel extends StatefulWidget {
  const CvLocationFilterPanel({
    super.key,
    required this.scope,
    required this.selection,
    required this.onSelectionChanged,
    required this.date,
    required this.onPreviousDate,
    required this.onNextDate,
    required this.onPickDate,
    required this.expanded,
    required this.onExpandedChanged,
    required this.language,
    required this.search,
    required this.onSearchChanged,
    required this.onReset,
    required this.resultsCount,
    this.loading = false,
  });

  final LocationFilterScope scope;
  final LocationFilterSelection selection;
  final ValueChanged<LocationFilterSelection> onSelectionChanged;
  final DateTime date;
  final VoidCallback? onPreviousDate;
  final VoidCallback? onNextDate;
  final VoidCallback onPickDate;
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;
  final String language;
  final String search;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onReset;
  final int resultsCount;
  final bool loading;

  @override
  State<CvLocationFilterPanel> createState() => _CvLocationFilterPanelState();
}

class _CvLocationFilterPanelState extends State<CvLocationFilterPanel> {
  late final TextEditingController _search = TextEditingController(
    text: widget.search,
  );

  bool get ar => widget.language == 'ar';

  static const _dimensions = [
    LocationFilterDimension.organization,
    LocationFilterDimension.zone,
    LocationFilterDimension.site,
    LocationFilterDimension.building,
    LocationFilterDimension.floor,
    LocationFilterDimension.area,
    LocationFilterDimension.sector,
    LocationFilterDimension.serviceClass,
    LocationFilterDimension.department,
    LocationFilterDimension.coverage,
    LocationFilterDimension.documentKind,
    LocationFilterDimension.checklistType,
  ];

  @override
  void didUpdateWidget(CvLocationFilterPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.search != widget.search && _search.text != widget.search) {
      _search.value = TextEditingValue(
        text: widget.search,
        selection: TextSelection.collapsed(offset: widget.search.length),
      );
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String label(LocationFilterDimension dimension) => switch (dimension) {
    LocationFilterDimension.organization => ar ? 'المنظمة' : 'Organization',
    LocationFilterDimension.zone => ar ? 'المنطقة' : 'Zone',
    LocationFilterDimension.site => ar ? 'الموقع' : 'Site',
    LocationFilterDimension.building => ar ? 'المبنى' : 'Building',
    LocationFilterDimension.floor => ar ? 'الدور' : 'Floor',
    LocationFilterDimension.area => ar ? 'المساحة' : 'Area',
    LocationFilterDimension.checklistType =>
      ar ? 'نوع القائمة' : 'Checklist type',
    LocationFilterDimension.sector => ar ? 'المجال' : 'Sector',
    LocationFilterDimension.serviceClass => ar ? 'صنف الخدمة' : 'Service class',
    LocationFilterDimension.department => ar ? 'القسم' : 'Department',
    LocationFilterDimension.coverage =>
      ar ? 'نوع المنطقة / التغطية' : 'Area type / Coverage',
    LocationFilterDimension.documentKind =>
      ar ? 'نوع القائمة / العمل' : 'Checklist / Work type',
  };

  /// Visibility is calculated from the entire accessible scope, independent
  /// of every transient selection. A choice must not remove a filter control.
  bool _visibleForAccess(LocationFilterDimension dimension) {
    const all = LocationFilterSelection();
    final choices = widget.scope.optionsFor(dimension, all);
    if (choices.isEmpty) return false;
    if (choices.length > 1) return true;
    // Service taxonomy always retains its place for a permitted branch,
    // including the sole General department of Hard Services.
    return switch (dimension) {
      LocationFilterDimension.sector ||
      LocationFilterDimension.serviceClass ||
      LocationFilterDimension.department ||
      LocationFilterDimension.coverage ||
      LocationFilterDimension.documentKind => true,
      _ => false,
    };
  }

  /// Choices depend only on ancestors, never on the currently selected
  /// siblings or descendants. This keeps each selector useful and avoids
  /// forced disappearance/reflow as the user navigates the hierarchy.
  List<LocationFilterOption> _choicesFor(
    LocationFilterDimension dimension,
    LocationFilterSelection current,
  ) {
    var context = const LocationFilterSelection();
    if (dimension == LocationFilterDimension.documentKind ||
        dimension == LocationFilterDimension.checklistType) {
      for (final ancestor in LocationFilterScope.hierarchyDimensions) {
        context = context.withValue(ancestor, current.valueFor(ancestor));
      }
    } else {
      for (final ancestor in LocationFilterScope.hierarchyDimensions) {
        if (ancestor == dimension) break;
        context = context.withValue(ancestor, current.valueFor(ancestor));
      }
    }
    return widget.scope.optionsFor(dimension, context);
  }

  String _currentLabel(
    LocationFilterDimension dimension,
    LocationFilterSelection selected,
    List<LocationFilterOption> options,
  ) {
    final value = selected.valueFor(dimension);
    for (final option in options) {
      if (option.value == value) return option.labelFor(widget.language);
    }
    if (options.length == 1) {
      return options.single.labelFor(widget.language);
    }
    return ar ? 'الكل' : 'All';
  }

  Future<void> _showChoices(
    LocationFilterDimension dimension,
    LocationFilterSelection selected,
    List<LocationFilterOption> options,
  ) async {
    if (options.isEmpty) return;
    final picked = await showCvChoiceSheet<String>(
      context: context,
      title: label(dimension),
      selected: selected.valueFor(dimension) ?? '',
      choices: [
        CvChoice(value: '', label: ar ? 'الكل' : 'All'),
        for (final option in options)
          CvChoice(
            value: option.value,
            label: option.labelFor(widget.language),
          ),
      ],
    );
    if (picked == null || !mounted) return;
    final value = picked.isEmpty ? null : picked;
    if (value == selected.valueFor(dimension)) return;
    widget.onSelectionChanged(_select(dimension, value));
  }

  String get dateLabel =>
      '${widget.date.year.toString().padLeft(4, '0')}-'
      '${widget.date.month.toString().padLeft(2, '0')}-'
      '${widget.date.day.toString().padLeft(2, '0')}';

  LocationFilterSelection _select(
    LocationFilterDimension dimension,
    String? value,
  ) {
    var selection = widget.selection.withValue(dimension, value);
    if (dimension != LocationFilterDimension.checklistType &&
        dimension != LocationFilterDimension.documentKind) {
      final index = LocationFilterScope.hierarchyDimensions.indexOf(dimension);
      for (
        var i = index + 1;
        i < LocationFilterScope.hierarchyDimensions.length;
        i++
      ) {
        selection = selection.withValue(
          LocationFilterScope.hierarchyDimensions[i],
          null,
        );
      }
    }
    return widget.scope.normalize(selection);
  }

  @override
  Widget build(BuildContext context) {
    final colors = CheckViewColors.of(context);
    final normalized = widget.scope.normalize(widget.selection);
    // Permission-scoped controls remain mounted throughout all selections.
    final dimensions = [
      for (final dimension in _dimensions)
        if (_visibleForAccess(dimension)) dimension,
    ];
    final fields = [
      for (final dimension in dimensions)
        (dimension, _choicesFor(dimension, normalized)),
    ];
    final leaves = widget.scope.filteredLeaves(normalized);
    final areas = leaves.map((e) => e.areaId).toSet().length;
    final checked = leaves.map((e) => e.assignmentId).toSet().length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Material(
        color: colors.surface,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: colors.hairline),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => widget.onExpandedChanged(!widget.expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                child: Row(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.accentSoft,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(9),
                        child: Icon(
                          Icons.tune_rounded,
                          color: colors.accent,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ar
                                ? 'البحث والفلاتر المتقدمة'
                                : 'Search & advanced filters',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            ar
                                ? '${fields.length} فلاتر • $areas مساحات • $checked قوائم • ${widget.resultsCount} سجل'
                                : '${dimensions.length} filters • $areas areas • $checked checklists • ${widget.resultsCount} records',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (widget.loading)
                      const Padding(
                        padding: EdgeInsets.only(right: 9),
                        child: SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    AnimatedRotation(
                      turns: widget.expanded ? .5 : 0,
                      duration: CvMotion.of(context, CvMotion.standard),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: colors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: colors.hairline),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: ar ? 'السابق' : 'Previous date',
                    onPressed: widget.onPreviousDate,
                    icon: Icon(ar ? Icons.chevron_right : Icons.chevron_left),
                  ),
                  Flexible(
                    child: TextButton(
                      onPressed: widget.onPickDate,
                      child: Text(
                        dateLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: ar ? 'التالي' : 'Next date',
                    onPressed: widget.onNextDate,
                    icon: Icon(ar ? Icons.chevron_left : Icons.chevron_right),
                  ),
                ],
              ),
            ),
            AnimatedSize(
              alignment: Alignment.topCenter,
              curve: CvMotion.glide,
              duration: CvMotion.of(context, CvMotion.spatial),
              child: widget.expanded
                  ? ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * 0.40,
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(13, 4, 13, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _search,
                              onChanged: widget.onSearchChanged,
                              decoration: InputDecoration(
                                isDense: true,
                                prefixIcon: const Icon(Icons.search_rounded),
                                hintText: ar
                                    ? 'ابحث باسم القائمة أو الموقع أو المبنى أو المساحة...'
                                    : 'Search checklist, site, building or area...',
                                suffixIcon: _search.text.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: ar
                                            ? 'مسح البحث'
                                            : 'Clear search',
                                        icon: const Icon(Icons.close_rounded),
                                        onPressed: () {
                                          _search.clear();
                                          widget.onSearchChanged('');
                                        },
                                      ),
                              ),
                            ),
                            const SizedBox(height: 13),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                // The same title-cell dropdown appearance as
                                // Operations (the second CheckView tab).
                                // Every row consumes the full available width.
                                final available = constraints.maxWidth;
                                final maxPerRow = available < 400
                                    ? 1
                                    : (available / 210).floor().clamp(1, 5);
                                final rowCount = fields.isEmpty
                                    ? 0
                                    : (fields.length / maxPerRow).ceil();
                                final perRow = rowCount == 0
                                    ? 0
                                    : fields.length ~/ rowCount;
                                final overflowRows = rowCount == 0
                                    ? 0
                                    : fields.length % rowCount;
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (
                                      var row = 0;
                                      row < rowCount;
                                      row++
                                    ) ...[
                                      if (row > 0) const SizedBox(height: 8),
                                      Builder(
                                        builder: (context) {
                                          final count =
                                              perRow +
                                              (row < overflowRows ? 1 : 0);
                                          final startIndex =
                                              row * perRow +
                                              (row < overflowRows
                                                  ? row
                                                  : overflowRows);
                                          final rowFields = fields.sublist(
                                            startIndex,
                                            startIndex + count,
                                          );
                                          return CvTitleBlock(
                                            fields: [
                                              for (final (dimension, options)
                                                  in rowFields)
                                                CvTitleField(
                                                  label: label(dimension),
                                                  value: _currentLabel(
                                                    dimension,
                                                    normalized,
                                                    options,
                                                  ),
                                                  maxLines: 2,
                                                  onTap: options.isEmpty
                                                      ? null
                                                      : () => _showChoices(
                                                          dimension,
                                                          normalized,
                                                          options,
                                                        ),
                                                ),
                                            ],
                                          );
                                        },
                                      ),
                                    ],
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    ar
                                        ? 'المواقع المصرح بها فقط'
                                        : 'Authorized locations only',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: widget.onReset,
                                  icon: const Icon(
                                    Icons.restart_alt_rounded,
                                    size: 17,
                                  ),
                                  label: Text(ar ? 'إعادة ضبط' : 'Reset'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
