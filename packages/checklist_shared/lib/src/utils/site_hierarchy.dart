import '../models/profile.dart';

/// Groups checklist units under their parent campus site.
List<CampusChecklistGroup> groupChecklistsByCampus({
  required List<ChecklistSite> checklists,
  required List<ChecklistSite> allSites,
}) {
  final byId = {for (final s in allSites) s.id: s};
  final buckets = <String?, List<ChecklistSite>>{};
  for (final c in checklists.where((s) => s.isChecklistUnit)) {
    buckets.putIfAbsent(c.parentSiteId, () => []).add(c);
  }
  for (final list in buckets.values) {
    list.sort((a, b) => a.buildingCode.compareTo(b.buildingCode));
  }
  final keys = buckets.keys.toList()
    ..sort((a, b) {
      if (a == null) return 1;
      if (b == null) return -1;
      final an = byId[a]?.nameEn ?? a;
      final bn = byId[b]?.nameEn ?? b;
      return an.compareTo(bn);
    });
  return [
    for (final key in keys)
      CampusChecklistGroup(
        campus: key == null ? null : byId[key],
        checklists: buckets[key]!,
      ),
  ];
}
