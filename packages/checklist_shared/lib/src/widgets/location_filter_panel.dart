import 'package:flutter/material.dart';

import '../models/location_hierarchy.dart';

class ChecklistLocationFilterPanel extends StatelessWidget {
  const ChecklistLocationFilterPanel({
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
    this.loading = false,
    this.maxContentWidth = 1180,
    this.margin = const EdgeInsets.fromLTRB(12, 10, 12, 6),
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
  final bool loading;
  final double maxContentWidth;
  final EdgeInsets margin;

  bool get _ar => language == 'ar';

  String _dimensionLabel(LocationFilterDimension dimension) =>
      switch (dimension) {
        LocationFilterDimension.organization =>
          _ar ? 'المنظمة' : 'Organization',
        LocationFilterDimension.zone => _ar ? 'المنطقة' : 'Zone',
        LocationFilterDimension.site => _ar ? 'الموقع' : 'Site',
        LocationFilterDimension.building => _ar ? 'المبنى' : 'Building',
        LocationFilterDimension.floor => _ar ? 'الدور' : 'Floor',
        LocationFilterDimension.area => _ar ? 'المساحة' : 'Area',
        LocationFilterDimension.checklistType =>
          _ar ? 'نوع القائمة' : 'Checklist type',
      };

  String _allLabel(LocationFilterDimension dimension) {
    final label = _dimensionLabel(dimension);
    return _ar ? 'كل $label' : 'All $label';
  }

  String _dateLabel() =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  LocationFilterSelection _select(
    LocationFilterDimension dimension,
    String? value,
  ) {
    var next = selection.withValue(dimension, value);
    if (dimension != LocationFilterDimension.checklistType) {
      final index = LocationFilterScope.hierarchyDimensions.indexOf(dimension);
      for (
        var i = index + 1;
        i < LocationFilterScope.hierarchyDimensions.length;
        i++
      ) {
        next = next.withValue(LocationFilterScope.hierarchyDimensions[i], null);
      }
    }
    return scope.normalize(next);
  }

  List<LocationFilterDimension> _visibleDimensions(
    LocationFilterSelection normalized,
  ) {
    final dimensions = <LocationFilterDimension>[
      for (final dimension in LocationFilterScope.hierarchyDimensions)
        if (scope.shouldShow(dimension, normalized)) dimension,
    ];
    if (scope.shouldShow(LocationFilterDimension.checklistType, normalized)) {
      dimensions.add(LocationFilterDimension.checklistType);
    }
    return dimensions;
  }

  @override
  Widget build(BuildContext context) {
    final normalized = scope.normalize(selection);
    final dimensions = _visibleDimensions(normalized);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxContentWidth),
        child: Padding(
          padding: margin,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (details) {
              if (details.delta.dy <= -3 && expanded) {
                onExpandedChanged(false);
              } else if (details.delta.dy >= 3 && !expanded) {
                onExpandedChanged(true);
              }
            },
            onVerticalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity < -140 && expanded) {
                onExpandedChanged(false);
              } else if (velocity > 140 && !expanded) {
                onExpandedChanged(true);
              }
            },
            child: Material(
              elevation: 0,
              color: colors.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: 0.75),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () => onExpandedChanged(!expanded),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 8, 7),
                      child: Row(
                        children: [
                          Icon(
                            Icons.filter_alt_outlined,
                            size: 18,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              _ar ? 'الفلاتر' : 'Filters',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (loading)
                            const Padding(
                              padding: EdgeInsetsDirectional.only(end: 8),
                              child: SizedBox.square(
                                dimension: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          Icon(
                            expanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Divider(height: 1, color: colors.outlineVariant),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: _ar ? 'اليوم السابق' : 'Previous day',
                          onPressed: onPreviousDate,
                          icon: Icon(
                            _ar
                                ? Icons.chevron_right_rounded
                                : Icons.chevron_left_rounded,
                          ),
                        ),
                        Flexible(
                          child: TextButton.icon(
                            onPressed: onPickDate,
                            icon: const Icon(
                              Icons.calendar_month_outlined,
                              size: 18,
                            ),
                            label: Text(
                              _dateLabel(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: _ar ? 'اليوم التالي' : 'Next day',
                          onPressed: onNextDate,
                          icon: Icon(
                            _ar
                                ? Icons.chevron_left_rounded
                                : Icons.chevron_right_rounded,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: !expanded || dimensions.isEmpty
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final width = constraints.maxWidth;
                                final fieldWidth = width >= 900
                                    ? (width - 20) / 3
                                    : width >= 560
                                    ? (width - 10) / 2
                                    : width;
                                return Wrap(
                                  spacing: 10,
                                  runSpacing: 8,
                                  children: [
                                    for (final dimension in dimensions)
                                      SizedBox(
                                        width: fieldWidth,
                                        child: _FilterField(
                                          label: _dimensionLabel(dimension),
                                          allLabel: _allLabel(dimension),
                                          value: normalized.valueFor(dimension),
                                          options: scope.optionsFor(
                                            dimension,
                                            normalized,
                                          ),
                                          language: language,
                                          forceAllOption:
                                              dimension ==
                                                  LocationFilterDimension
                                                      .checklistType ||
                                              scope
                                                      .optionsFor(
                                                        dimension,
                                                        normalized,
                                                      )
                                                      .length >
                                                  1,
                                          onChanged: (value) =>
                                              onSelectionChanged(
                                                _select(dimension, value),
                                              ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterField extends StatelessWidget {
  const _FilterField({
    required this.label,
    required this.allLabel,
    required this.value,
    required this.options,
    required this.language,
    required this.forceAllOption,
    required this.onChanged,
  });

  final String label;
  final String allLabel;
  final String? value;
  final List<LocationFilterOption> options;
  final String language;
  final bool forceAllOption;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = value != null && options.any((o) => o.value == value)
        ? value
        : null;
    return DropdownButtonFormField<String?>(
      key: ValueKey(
        '$label:$current:${options.map((option) => option.value).join(',')}',
      ),
      initialValue: current,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.fromLTRB(11, 9, 9, 9),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: [
        if (forceAllOption)
          DropdownMenuItem<String?>(value: null, child: Text(allLabel)),
        for (final option in options)
          DropdownMenuItem<String?>(
            value: option.value,
            child: Text(
              option.labelFor(language),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: options.isEmpty ? null : onChanged,
    );
  }
}
