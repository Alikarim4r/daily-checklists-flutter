import '../models/profile.dart';

/// Classification of checklist units, independent of the template or site.
/// Empty categories are deliberately absent from [groupAvailable].
class ChecklistCategories {
  ChecklistCategories._();

  static const ids = [
    'facilities',
    'hygiene',
    'irrigation',
    'pantry',
    'maintenance',
    'safety',
    'food',
    'stores',
    'general',
  ];

  static String normalize(String? category) {
    final value = category?.trim().toLowerCase() ?? '';
    if (ids.contains(value)) return value;
    return 'general';
  }

  static String title(String category, String language) {
    final ar = language == 'ar';
    return switch (normalize(category)) {
      'facilities' => ar ? 'إدارة المرافق' : 'Facilities Management',
      'hygiene' => ar ? 'النظافة' : 'Cleaning',
      'irrigation' => ar ? 'الري' : 'Irrigation',
      'pantry' => ar ? 'البانتري' : 'Pantry',
      'maintenance' => ar ? 'الصيانة' : 'Maintenance',
      'safety' => ar ? 'السلامة' : 'Safety',
      'food' => ar ? 'الأغذية' : 'Food',
      'stores' => ar ? 'المخازن' : 'Stores',
      _ => ar ? 'عام / غير مصنف' : 'General / Unclassified',
    };
  }

  /// Groups only accessible/assigned checklist units; it never creates an
  /// empty category and never hides previously unclassified units.
  static Map<String, List<ChecklistSite>> groupAvailable(
    Iterable<ChecklistSite> sites, {
    bool includeInactive = false,
  }) {
    final buckets = <String, List<ChecklistSite>>{};
    for (final site in sites) {
      if ((!includeInactive && !site.isActive) || !site.isChecklistUnit) {
        continue;
      }
      final id = normalize(site.checklistCategory);
      buckets.putIfAbsent(id, () => []).add(site);
    }
    return {
      for (final id in ids)
        if (buckets[id]?.isNotEmpty == true) id: buckets[id]!,
    };
  }
}
