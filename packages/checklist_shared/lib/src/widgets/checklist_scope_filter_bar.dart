import 'package:flutter/material.dart';
import '../utils/checklist_scope_filters.dart';

/// A single horizontally scrollable top bar; all seven facets remain in their
/// requested order on narrow screens rather than clipping under the AppBar.
class ChecklistScopeFilterBar extends StatelessWidget {
  const ChecklistScopeFilterBar({
    super.key,
    required this.scope,
    required this.selection,
    required this.onChanged,
    required this.language,
    this.operationsStyle = false,
    this.showResetButton = true,
  });
  final ChecklistScopeFilters scope;
  final ChecklistFilterSelection selection;
  final ValueChanged<ChecklistFilterSelection> onChanged;
  final String language;
  final bool operationsStyle;
  final bool showResetButton;

  String _label(ChecklistFacet facet) {
    final ar = language == 'ar';
    return switch (facet) {
      ChecklistFacet.organization =>
        ar ? 'المنظمات / الشركات' : 'Organizations / Companies',
      ChecklistFacet.zone => ar ? 'المناطق' : 'Zones',
      ChecklistFacet.site => ar ? 'المواقع' : 'Sites',
      ChecklistFacet.category => ar ? 'أصناف القوائم' : 'Checklist Categories',
      ChecklistFacet.building => ar ? 'المباني' : 'Buildings',
      ChecklistFacet.floor => ar ? 'الطوابق' : 'Floors',
      ChecklistFacet.area =>
        ar ? 'الأحيزة / المناطق الداخلية' : 'Areas / Spaces',
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLowest,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.outlineVariant)),
        ),
        child: SizedBox(
          height: 76,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 8),
            children: [
              for (final facet in ChecklistFacet.values)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: SizedBox(
                    width: facet == ChecklistFacet.organization ? 196 : 156,
                    child: operationsStyle
                        ? OperationsStyleDropdown<String>(
                            key: ValueKey(
                              'scope-${facet.name}-${selection.valueFor(facet)}',
                            ),
                            label: _label(facet),
                            valueLabel: selection.valueFor(facet) == null
                                ? (language == 'ar' ? 'الكل' : 'All')
                                : scope
                                          .optionsFor(facet, selection)
                                          .where(
                                            (o) =>
                                                o.value ==
                                                selection.valueFor(facet),
                                          )
                                          .map((o) => o.nameFor(language))
                                          .firstOrNull ??
                                      (language == 'ar' ? 'الكل' : 'All'),
                            choices: [
                              OperationsFilterChoice(
                                value: '',
                                label: language == 'ar' ? 'الكل' : 'All',
                              ),
                              for (final option in scope.optionsFor(
                                facet,
                                selection,
                              ))
                                OperationsFilterChoice(
                                  value: option.value,
                                  label: option.nameFor(language),
                                ),
                            ],
                            onSelected: (value) => onChanged(
                              selection.choose(
                                facet,
                                value.isEmpty ? null : value,
                              ),
                            ),
                          )
                        : DropdownButtonFormField<String?>(
                            key: ValueKey(
                              'scope-${facet.name}-${selection.valueFor(facet)}',
                            ),
                            initialValue: selection.valueFor(facet),
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: _label(facet),
                              labelStyle: const TextStyle(fontSize: 11),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 8,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 19,
                            ),
                            items: [
                              DropdownMenuItem<String?>(
                                value: null,
                                child: Text(
                                  language == 'ar' ? 'الكل' : 'All',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              for (final option in scope.optionsFor(
                                facet,
                                selection,
                              ))
                                DropdownMenuItem<String?>(
                                  value: option.value,
                                  child: Text(
                                    option.nameFor(language),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (value) =>
                                onChanged(selection.choose(facet, value)),
                          ),
                  ),
                ),
              if (showResetButton)
                IconButton(
                  tooltip: language == 'ar'
                      ? 'إعادة ضبط كل الفلاتر'
                      : 'Reset all filters',
                  onPressed: selection.isAll
                      ? null
                      : () => onChanged(const ChecklistFilterSelection()),
                  icon: const Icon(Icons.filter_alt_off_outlined),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact two-line context cells inspired by Operations title fields.
/// Popup appears *below* the chosen filter rather than as a bottom sheet.
class OperationsFilterChoice<T> {
  const OperationsFilterChoice({required this.value, required this.label});
  final T value;
  final String label;
}

class OperationsStyleDropdown<T> extends StatelessWidget {
  const OperationsStyleDropdown({
    super.key,
    required this.label,
    required this.valueLabel,
    required this.choices,
    required this.onSelected,
  });
  final String label;
  final String valueLabel;
  final List<OperationsFilterChoice<T>> choices;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return PopupMenuButton<T>(
      tooltip: label,
      offset: const Offset(0, 4),
      position: PopupMenuPosition.under,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      constraints: const BoxConstraints(minWidth: 170, maxWidth: 330),
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final choice in choices)
          PopupMenuItem<T>(
            value: choice.value,
            child: Text(
              choice.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
      ],
      child: Container(
        height: 58,
        padding: const EdgeInsetsDirectional.fromSTEB(12, 7, 10, 7),
        decoration: BoxDecoration(
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(4),
          color: colors.surface,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    valueLabel,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 19,
              color: colors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
