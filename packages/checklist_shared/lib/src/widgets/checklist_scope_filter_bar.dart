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
  });
  final ChecklistScopeFilters scope;
  final ChecklistFilterSelection selection;
  final ValueChanged<ChecklistFilterSelection> onChanged;
  final String language;

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
                    child: DropdownButtonFormField<String?>(
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
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        for (final option in scope.optionsFor(facet, selection))
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
