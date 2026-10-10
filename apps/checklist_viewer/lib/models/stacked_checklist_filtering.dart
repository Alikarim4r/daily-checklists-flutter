import 'package:checklist_shared/checklist_shared.dart';

enum ChecklistFillFilter { all, filled, unfilled }

/// Only completed answers count as filled; a partial draft remains unfilled.
/// The database is never modified during this filtering or preview selection.
class StackedChecklistFiltering {
  const StackedChecklistFiltering._();

  static bool isFilled(Inspection inspection) =>
      inspection.isSubmitted ||
      inspection.isApproved ||
      (inspection.items.isNotEmpty &&
          inspection.items.every((item) => item.response != null));

  static Map<String, Inspection> newestPerSite(Iterable<Inspection> records) {
    final latest = <String, Inspection>{};
    for (final inspection in records) {
      final old = latest[inspection.siteId];
      if (old == null ||
          (inspection.updatedAt ??
                  inspection.createdAt ??
                  inspection.inspectionDate)
              .isAfter(old.updatedAt ?? old.createdAt ?? old.inspectionDate)) {
        latest[inspection.siteId] = inspection;
      }
    }
    return latest;
  }

  static List<ChecklistFilterRow> select({
    required ChecklistScopeFilters scope,
    required ChecklistFilterSelection selection,
    required ChecklistFillFilter fill,
    required Iterable<Inspection> records,
  }) {
    final bySite = newestPerSite(records);
    final matching = scope.rows.where((row) {
      if (!scope.matches(row, selection)) return false;
      final inspection = bySite[row.unit.id];
      final filled = inspection != null && isFilled(inspection);
      return switch (fill) {
        ChecklistFillFilter.all => true,
        ChecklistFillFilter.filled => filled,
        ChecklistFillFilter.unfilled => !filled,
      };
    }).toList();
    matching.sort((a, b) {
      for (final facet in ChecklistFacet.values) {
        final first = a.options[facet]?.nameEn.toLowerCase() ?? '';
        final second = b.options[facet]?.nameEn.toLowerCase() ?? '';
        final order = first.compareTo(second);
        if (order != 0) return order;
      }
      return a.unit.nameEn.compareTo(b.unit.nameEn);
    });
    return matching;
  }
}
