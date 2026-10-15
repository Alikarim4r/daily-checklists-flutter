import 'package:checklist_shared/checklist_shared.dart';

/// Matches the authorized hierarchy AND the actual inspection location IDs.
/// Older inspections sometimes have no floor/area IDs; do not attribute those
/// records to one of several possible locations by guessing.
bool cvMatchesAuthorizedLocation({
  required Inspection inspection,
  required LocationFilterScope scope,
  required LocationFilterSelection selection,
}) {
  if (scope.leaves.isEmpty) return true; // Existing legacy read-only flow.
  final candidates = scope.leaves
      .where(
        (leaf) =>
            leaf.legacySiteId == inspection.siteId ||
            leaf.siteId == inspection.siteId,
      )
      .toList(growable: false);
  if (candidates.isEmpty) return false;

  // Explicit IDs on newer inspections take precedence over site-level guesses.
  final physicallyMatching = candidates
      .where((leaf) {
        if (inspection.organizationId.isNotEmpty &&
            inspection.organizationId != leaf.organizationId) {
          return false;
        }
        if (!leaf.assignmentId.startsWith('legacy-authorized:') &&
            inspection.buildingId != null &&
            inspection.buildingId != leaf.buildingId) {
          return false;
        }
        if (!leaf.assignmentId.startsWith('legacy-authorized:') &&
            inspection.floorId != null &&
            inspection.floorId != leaf.floorId) {
          return false;
        }
        if (!leaf.assignmentId.startsWith('legacy-authorized:') &&
            inspection.areaId != null &&
            inspection.areaId != leaf.areaId) {
          return false;
        }
        return true;
      })
      .toList(growable: false);
  if (physicallyMatching.isEmpty) return false;

  final normalized = scope.normalize(selection);
  final filtered = scope.filteredLeaves(normalized).toSet();

  // If an old record lacks a precise location ID, we can use the legacy site
  // only if its full authorized scope uniquely resolves that dimension.
  // Otherwise a floor/area filter must not misleadingly claim a match.
  if (inspection.buildingId == null &&
      normalized.buildingId != null &&
      physicallyMatching.map((l) => l.buildingId).toSet().length > 1) {
    return false;
  }
  if (inspection.floorId == null &&
      normalized.floorId != null &&
      physicallyMatching.map((l) => l.floorId).toSet().length > 1) {
    return false;
  }
  if (inspection.areaId == null &&
      normalized.areaId != null &&
      physicallyMatching.map((l) => l.areaId).toSet().length > 1) {
    return false;
  }
  return physicallyMatching.any(filtered.contains);
}
