import 'dart:math' as math;
import 'package:checklist_shared/checklist_shared.dart';

/// A user only sees facets with two or more authorized options, or a selected
/// facet (which must remain visible so its All setting can be restored).
class ViewerFilterDistribution {
  const ViewerFilterDistribution._();

  static List<ChecklistFacet> visibleFacets(
    ChecklistScopeFilters scope,
    ChecklistFilterSelection selection,
  ) => [
    for (final facet in ChecklistFacet.values)
      if (selection.valueFor(facet) != null ||
          scope.optionsFor(facet, selection).length > 1)
        facet,
  ];

  /// Completion is always one of the equally-sized fields on this row.
  /// Narrow screens scroll horizontally, but each usable row is fully filled.
  static double fieldWidth(
    double viewport,
    int totalFields, {
    double minimum = 142,
    double margin = 8,
    double gap = 8,
  }) {
    if (totalFields <= 0 || !viewport.isFinite) return minimum;
    return math.max(
      minimum,
      (viewport - margin * 2 - gap * (totalFields - 1)) / totalFields,
    );
  }
}
