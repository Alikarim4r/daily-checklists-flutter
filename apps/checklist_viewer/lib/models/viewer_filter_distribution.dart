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

  /// Fit every authorized facet and Completion into the available screen.
  /// Desktop uses one row, regardless of how many facets the user can see;
  /// smaller screens add rows rather than hiding Completion offscreen.
  static int columnsFor(
    double viewport,
    int totalFields, {
    double margin = 8,
    double gap = 8,
    double mobileMinimum = 142,
    double desktopBreakpoint = 1000,
  }) {
    if (totalFields <= 0) return 0;
    if (!viewport.isFinite || viewport <= 0) return 1;
    if (viewport >= desktopBreakpoint) return totalFields;
    final usable = math.max(0, viewport - 2 * margin);
    final fit = ((usable + gap) / (mobileMinimum + gap)).floor();
    return math.min(totalFields, math.max(1, fit));
  }

  static double fieldWidth(
    double viewport,
    int fieldsInRow, {
    double margin = 8,
    double gap = 8,
  }) {
    if (!viewport.isFinite || fieldsInRow <= 0) return 0;
    return math.max(
      0,
      (viewport - margin * 2 - gap * (fieldsInRow - 1)) / fieldsInRow,
    );
  }
}
