import '../models/profile.dart';

/// A second navigation level within a checklist category. Unassigned lists
/// stay directly inside their category; no empty subgroup is displayed.
class ChecklistSubcategories {
  ChecklistSubcategories._();

  static String title(String id, String language) => switch (id) {
    'washrooms' =>
      language == 'ar' ? 'قوائم فحص الحمامات' : 'Toilet Checklists',
    _ => id,
  };

  static Map<String, List<ChecklistSite>> available(
    Iterable<ChecklistSite> sites,
  ) {
    final groups = <String, List<ChecklistSite>>{};
    for (final site in sites) {
      if (!site.isActive || !site.isChecklistUnit) continue;
      final key = site.checklistSubcategory.trim();
      groups.putIfAbsent(key, () => []).add(site);
    }
    return groups;
  }
}
