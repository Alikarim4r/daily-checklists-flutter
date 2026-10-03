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

  void _openChecklist(BuildContext context, ChecklistSite site) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EntrySiteScreen(
          profile: profile,
          site: site,
          language: language,
          onLanguageChanged: onLanguageChanged,
        ),
      ),
    );
  }

  void _openCampus(BuildContext context, CampusChecklistGroup group) {
    if (group.checklists.length == 1 && group.campus == null) {
      _openChecklist(context, group.checklists.first);
      return;
    }
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
    final L = AppLabels(language);
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
              title: L.siteChecklists,
              subtitle: L.selectChecklistHint,
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
              title: ar ? 'قوائم الفحص' : 'Checklists',
              count: group.checklists.length,
            ),
            if (group.checklists.isEmpty)
              CiEmptyState(
                title: ar ? 'لا توجد قوائم فحص' : 'No checklists available',
                message: ar
                    ? 'هذا الموقع لا يحتوي حاليًا على قائمة قابلة للإدخال.'
                    : 'This site currently has no checklist available for entry.',
                icon: Icons.playlist_remove_rounded,
              )
            else
              CiQueuePanel(
                children: [
                  for (final site in group.checklists)
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
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => EntrySiteScreen(
                              profile: profile,
                              site: site,
                              parentCampus: group.campus,
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
