import '../models/inspection.dart';
import 'storage_path_list.dart';

/// Copies still-open work orders onto a new/draft checklist.
///
/// For each catalog item present in [sourceByIndex]:
/// - problem answer is copied when the draft answer is empty
/// - every issue photo that has **no** fix yet is added (by storage path)
///   if the draft does not already reference that path
///
/// Returns `true` when [current] mutated.
bool applyOpenProblemCarryForward({
  required Inspection current,
  required Map<int, InspectionItem> sourceByIndex,
}) {
  var changed = false;
  for (final item in current.items) {
    final prev = sourceByIndex[item.itemIndex];
    if (prev == null) continue;

    final openPairs = [
      for (final p in prev.photoPairs)
        if (p.hasIssue && !p.hasFix) p,
    ];
    final openByPath = {
      for (final p in openPairs) storagePathOf(p.issuePath!): p,
    }..removeWhere((k, _) => k.isEmpty);

    final hasOpenWo = prev.isProblem || openByPath.isNotEmpty;
    if (!hasOpenWo) continue;

    if (item.response == null) {
      if (prev.isProblem && prev.response != null) {
        item.response = prev.response;
        changed = true;
      } else if (openByPath.isNotEmpty) {
        final problem = prev.problemResponse ?? prev.response;
        if (problem != null) {
          item.response = problem;
          changed = true;
        }
      }
    }

    final existing = {
      for (final path in item.issueImagePaths) storagePathOf(path),
    }..removeWhere((p) => p.isEmpty);

    for (final entry in openByPath.entries) {
      if (existing.contains(entry.key)) continue;
      item.addPairWithIssue(entry.key);
      existing.add(entry.key);
      changed = true;
    }
  }
  return changed;
}
