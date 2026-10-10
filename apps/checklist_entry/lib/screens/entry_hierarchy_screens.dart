part of '../main.dart';

class EntryZonesScreen extends ConsumerWidget {
  const EntryZonesScreen({
    super.key,
    required this.profile,
    required this.section,
    required this.language,
    required this.onLanguageChanged,
  });

  final Profile profile;
  final OrgBrowseSection section;
  final String language;
  final ValueChanged<String> onLanguageChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ar = language == 'ar';
    return Scaffold(
      appBar: AppBar(title: Text(section.organization.nameFor(language))),
      body: CiPageWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            CiBreadcrumbs(
              items: [
                CiCrumb(
                  ar ? 'العمل' : 'Work',
                  onTap: () => Navigator.pop(context),
                ),
                CiCrumb(section.organization.nameFor(language)),
              ],
            ),
            const SizedBox(height: 10),
            CiWorkHeader(
              title: ar ? 'اختر المنطقة' : 'Select a zone',
              subtitle: section.organization.nameFor(language),
              meta: [
                CiMeta(
                  ar
                      ? '${section.zones.length} مناطق متاحة'
                      : '${section.zones.length} available zones',
                  icon: Icons.map_outlined,
                ),
              ],
            ),
            CiSectionLabel(
              title: ar ? 'المناطق' : 'Zones',
              count: section.zones.length,
            ),
            if (section.zones.isEmpty)
              CiEmptyState(
                title: ar ? 'لا توجد مناطق متاحة' : 'No available zones',
                message: ar
                    ? 'اطلب من المشرف مراجعة صلاحيات المواقع.'
                    : 'Ask an administrator to review your site access.',
                icon: Icons.map_outlined,
              )
            else
              CiQueuePanel(
                children: [
                  for (final zone in section.zones)
                    CiQueueRow(
                      title: zone.titleFor(language),
                      subtitle: ar
                          ? '${zone.groups.length} مواقع'
                          : '${zone.groups.length} sites',
                      icon: Icons.map_outlined,
                      meta: [
                        CiMeta(
                          ar
                              ? '${zone.groups.fold<int>(0, (count, group) => count + group.checklists.length)} قوائم'
                              : '${zone.groups.fold<int>(0, (count, group) => count + group.checklists.length)} checklists',
                          icon: Icons.checklist_rounded,
                        ),
                      ],
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => EntryCampusesScreen(
                              profile: profile,
                              organizationName: section.organization.nameFor(
                                language,
                              ),
                              zoneSection: zone,
                              language: language,
                              onLanguageChanged: onLanguageChanged,
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class EntryCampusesScreen extends ConsumerWidget {
  const EntryCampusesScreen({
    super.key,
    required this.profile,
    required this.organizationName,
    required this.zoneSection,
    required this.language,
    required this.onLanguageChanged,
  });

  final Profile profile;
  final String organizationName;
  final ZoneBrowseSection zoneSection;
  final String language;
  final ValueChanged<String> onLanguageChanged;

  void _openCampus(BuildContext context, CampusChecklistGroup group) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EntryCampusScreen(
          profile: profile,
          group: group,
          language: language,
          onLanguageChanged: onLanguageChanged,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ar = language == 'ar';
    return Scaffold(
      appBar: AppBar(title: Text(zoneSection.titleFor(language))),
      body: CiPageWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            CiBreadcrumbs(
              items: [
                CiCrumb(ar ? 'الجهات' : 'Organizations'),
                CiCrumb(organizationName, onTap: () => Navigator.pop(context)),
                CiCrumb(zoneSection.titleFor(language)),
              ],
            ),
            const SizedBox(height: 10),
            CiWorkHeader(
              title: ar ? 'اختر الموقع' : 'Select a site',
              subtitle: zoneSection.titleFor(language),
              meta: [
                CiMeta(
                  ar
                      ? '${zoneSection.groups.length} مواقع متاحة'
                      : '${zoneSection.groups.length} available sites',
                  icon: Icons.location_on_outlined,
                ),
              ],
            ),
            CiSectionLabel(
              title: ar ? 'المواقع' : 'Sites',
              count: zoneSection.groups.length,
            ),
            if (zoneSection.groups.isEmpty)
              CiEmptyState(
                title: ar ? 'لا توجد مواقع' : 'No sites here',
                message: ar
                    ? 'اختر منطقة أخرى أو اطلب مراجعة صلاحياتك.'
                    : 'Choose another zone or ask for an access review.',
                icon: Icons.location_off_outlined,
              )
            else
              CiQueuePanel(
                children: [
                  for (final group in zoneSection.groups)
                    CiQueueRow(
                      title: group.titleFor(language),
                      subtitle: group.campus?.location,
                      icon: group.campus != null
                          ? Icons.location_city_outlined
                          : Icons.apartment_outlined,
                      meta: [
                        CiMeta(
                          ar
                              ? '${group.checklists.length} قوائم فحص'
                              : '${group.checklists.length} checklists',
                          icon: Icons.checklist_rounded,
                        ),
                      ],
                      onTap: () => _openCampus(context, group),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class EntryCampusScreen extends ConsumerWidget {
  const EntryCampusScreen({
    super.key,
    required this.profile,
    required this.group,
    required this.language,
    required this.onLanguageChanged,
  });

  final Profile profile;
  final CampusChecklistGroup group;
  final String language;
  final ValueChanged<String> onLanguageChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ar = language == 'ar';
    return Scaffold(
      appBar: AppBar(title: Text(group.titleFor(language))),
      body: CiPageWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            CiBreadcrumbs(
              items: [
                CiCrumb(
                  ar ? 'المواقع' : 'Sites',
                  onTap: () => Navigator.pop(context),
                ),
                CiCrumb(group.titleFor(language)),
              ],
            ),
            const SizedBox(height: 10),
            CiWorkHeader(
              title: ar ? 'اختر صنف قوائم الفحص' : 'Select checklist category',
              subtitle: group.titleFor(language),
              meta: [
                CiMeta(
                  ar
                      ? '${group.checklists.length} قوائم متاحة'
                      : '${group.checklists.length} available checklists',
                  icon: Icons.checklist_rounded,
                ),
              ],
            ),
            CiSectionLabel(
              title: ar ? 'أصناف قوائم الفحص' : 'Checklist categories',
              count: ChecklistCategories.groupAvailable(
                group.checklists,
              ).length,
            ),
            if (ChecklistCategories.groupAvailable(group.checklists).isEmpty)
              CiEmptyState(
                title: ar ? 'لا توجد قوائم فحص' : 'No checklists available',
                message: ar
                    ? 'لم تُنشأ أي قائمة لهذا الموقع بعد.'
                    : 'No checklists are assigned to this site yet.',
                icon: Icons.playlist_remove_rounded,
              )
            else
              CiQueuePanel(
                children: [
                  for (final entry in ChecklistCategories.groupAvailable(
                    group.checklists,
                  ).entries)
                    CiQueueRow(
                      title: ChecklistCategories.title(entry.key, language),
                      subtitle: ar
                          ? '${entry.value.length} قوائم'
                          : '${entry.value.length} checklists',
                      icon: Icons.folder_outlined,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => EntryCategoryScreen(
                            profile: profile,
                            group: group,
                            category: entry.key,
                            language: language,
                            onLanguageChanged: onLanguageChanged,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Only lists belonging to the selected, nonempty category are rendered.
class EntryCategoryScreen extends ConsumerWidget {
  const EntryCategoryScreen({
    super.key,
    required this.profile,
    required this.group,
    required this.category,
    required this.language,
    required this.onLanguageChanged,
  });

  final Profile profile;
  final CampusChecklistGroup group;
  final String category;
  final String language;
  final ValueChanged<String> onLanguageChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ar = language == 'ar';
    final units =
        ChecklistCategories.groupAvailable(group.checklists)[category] ??
        const <ChecklistSite>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(ChecklistCategories.title(category, language)),
      ),
      body: CiPageWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            CiBreadcrumbs(
              items: [
                CiCrumb(
                  group.titleFor(language),
                  onTap: () => Navigator.pop(context),
                ),
                CiCrumb(ChecklistCategories.title(category, language)),
              ],
            ),
            const SizedBox(height: 10),
            CiWorkHeader(
              title: ChecklistCategories.title(category, language),
              subtitle: ar
                  ? 'اختر قائمة الفحص للإدخال'
                  : 'Select a checklist to enter',
              meta: [
                CiMeta(
                  ar ? '${units.length} قوائم' : '${units.length} checklists',
                  icon: Icons.checklist_rounded,
                ),
              ],
            ),
            CiSectionLabel(
              title: ar ? 'قوائم الفحص' : 'Checklists',
              count: units.length,
            ),
            if (category == 'facilities')
              CiQueuePanel(
                children: [
                  for (final subgroup in ChecklistSubcategories.available(
                    units,
                  ).entries)
                    if (subgroup.key.isNotEmpty)
                      CiQueueRow(
                        title: ChecklistSubcategories.title(
                          subgroup.key,
                          language,
                        ),
                        subtitle: ar
                            ? '${subgroup.value.length} قوائم'
                            : '${subgroup.value.length} checklists',
                        icon: Icons.folder_outlined,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => EntrySubcategoryScreen(
                              profile: profile,
                              group: group,
                              subcategory: subgroup.key,
                              language: language,
                              onLanguageChanged: onLanguageChanged,
                            ),
                          ),
                        ),
                      )
                    else
                      for (final site in subgroup.value)
                        _DirectChecklistRow(
                          site: site,
                          profile: profile,
                          group: group,
                          language: language,
                          onLanguageChanged: onLanguageChanged,
                        ),
                ],
              )
            else
              CiQueuePanel(
                children: [
                  for (final site in units)
                    CiQueueRow(
                      title: site.nameFor(language),
                      subtitle: site.location,
                      icon: Icons.fact_check_outlined,
                      meta: [
                        CiMeta(site.buildingCode, icon: Icons.tag_rounded),
                        CiMeta(
                          site.checklistType,
                          icon: Icons.description_outlined,
                        ),
                      ],
                      trailing: Container(
                        width: 12,
                        height: 32,
                        decoration: BoxDecoration(
                          color: site.paperTheme.accent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => EntrySiteScreen(
                            profile: profile,
                            site: site,
                            parentCampus: group.campus,
                            language: language,
                            onLanguageChanged: onLanguageChanged,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// A facilities subfolder; cleaning is intentionally not nested.
class EntrySubcategoryScreen extends ConsumerWidget {
  const EntrySubcategoryScreen({
    super.key,
    required this.profile,
    required this.group,
    required this.subcategory,
    required this.language,
    required this.onLanguageChanged,
  });
  final Profile profile;
  final CampusChecklistGroup group;
  final String subcategory;
  final String language;
  final ValueChanged<String> onLanguageChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ar = language == 'ar';
    final units =
        ChecklistSubcategories.available(
          ChecklistCategories.groupAvailable(group.checklists)['facilities'] ??
              const <ChecklistSite>[],
        )[subcategory] ??
        const <ChecklistSite>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(ChecklistSubcategories.title(subcategory, language)),
      ),
      body: CiPageWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            CiBreadcrumbs(
              items: [
                CiCrumb(
                  group.titleFor(language),
                  onTap: () => Navigator.pop(context),
                ),
                CiCrumb(ChecklistSubcategories.title(subcategory, language)),
              ],
            ),
            const SizedBox(height: 10),
            CiWorkHeader(
              title: ChecklistSubcategories.title(subcategory, language),
              subtitle: ar ? 'اختر الحمام' : 'Select washroom',
              meta: [CiMeta('${units.length}', icon: Icons.checklist_rounded)],
            ),
            CiSectionLabel(
              title: ar ? 'قوائم الحمامات' : 'Washroom checklists',
              count: units.length,
            ),
            CiQueuePanel(
              children: [
                for (final site in units)
                  _DirectChecklistRow(
                    site: site,
                    profile: profile,
                    group: group,
                    language: language,
                    onLanguageChanged: onLanguageChanged,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Single checklist entry point shared by facilities child folders.
class _DirectChecklistRow extends StatelessWidget {
  const _DirectChecklistRow({
    required this.site,
    required this.profile,
    required this.group,
    required this.language,
    required this.onLanguageChanged,
  });
  final ChecklistSite site;
  final Profile profile;
  final CampusChecklistGroup group;
  final String language;
  final ValueChanged<String> onLanguageChanged;

  @override
  Widget build(BuildContext context) => CiQueueRow(
    title: site.nameFor(language),
    subtitle: site.location,
    icon: Icons.fact_check_outlined,
    meta: [
      CiMeta(site.buildingCode, icon: Icons.tag_rounded),
      CiMeta(site.checklistType, icon: Icons.description_outlined),
    ],
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EntrySiteScreen(
          profile: profile,
          site: site,
          parentCampus: group.campus,
          language: language,
          onLanguageChanged: onLanguageChanged,
        ),
      ),
    ),
  );
}
