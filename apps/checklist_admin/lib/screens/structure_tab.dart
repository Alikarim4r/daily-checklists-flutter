import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/structure_action_tile.dart';
import 'form_theme_picker_dialog.dart';
import 'policies_screen.dart';
import 'report_logos_screen.dart';
import 'users_tab.dart';

sealed class StructureSelection {}

class StructureOrgSelection extends StructureSelection {
  StructureOrgSelection(this.organizationId);
  final String organizationId;
}

class StructureZoneSelection extends StructureSelection {
  StructureZoneSelection(this.zoneId);
  final String zoneId;
}

class StructureCampusSelection extends StructureSelection {
  StructureCampusSelection(this.siteId);
  final String siteId;
}

class StructureChecklistSelection extends StructureSelection {
  StructureChecklistSelection(this.siteId);
  final String siteId;
}

/// Org → Zone → Campus → checklist units (master-detail tree).
class StructureTab extends ConsumerStatefulWidget {
  const StructureTab({
    super.key,
    required this.profile,
    required this.language,
  });

  final Profile profile;
  final String language;

  @override
  ConsumerState<StructureTab> createState() => _StructureTabState();
}

class _StructureTabState extends ConsumerState<StructureTab> {
  List<Organization> orgs = [];
  List<Zone> zones = [];
  List<ChecklistSite> sites = [];
  List<ChecklistTemplate> templates = [];
  bool loading = true;
  String? message;
  StructureSelection? selection;

  bool get canManageOrgs => widget.profile.canManageOrganizations;
  bool get canManageZones => widget.profile.canManageStructure;
  bool get canManageSites => widget.profile.canManageLocalSites;
  bool get canEditOrgLogos => widget.profile.isPlatformOwner || canManageZones;
  bool get ar => widget.language == 'ar';

  String _t(String en, String arText) => ar ? arText : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      message = null;
    });
    try {
      final orgRepo = ref.read(organizationRepositoryProvider);
      final siteRepo = ref.read(siteRepositoryProvider);
      final o = await orgRepo.listOrganizations();
      final z = await orgRepo.listAllZones();
      final s = await siteRepo.listAllSites();
      final t = await ref
          .read(catalogRepositoryProvider)
          .listTemplates(activeOnly: false);
      final activeOrgs = o.where((x) => x.isActive).toList();
      setState(() {
        orgs = activeOrgs;
        zones = z;
        sites = s;
        templates = t;
        selection =
            _sanitizeSelection(selection) ??
            (activeOrgs.isNotEmpty
                ? StructureOrgSelection(activeOrgs.first.id)
                : null);
      });
    } catch (e) {
      setState(() => message = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  StructureSelection? _sanitizeSelection(StructureSelection? current) {
    if (current == null) return null;
    return switch (current) {
      StructureOrgSelection(:final organizationId) =>
        orgs.any((o) => o.id == organizationId) ? current : null,
      StructureZoneSelection(:final zoneId) =>
        zones.any((z) => z.id == zoneId) ? current : null,
      StructureCampusSelection(:final siteId) =>
        sites.any((s) => s.id == siteId && s.isCampus) ? current : null,
      StructureChecklistSelection(:final siteId) =>
        sites.any((s) => s.id == siteId && s.isChecklistUnit) ? current : null,
    };
  }

  void _select(StructureSelection value, {required bool wide}) {
    setState(() => selection = value);
    if (!wide) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(_t('Details', 'التفاصيل'))),
            body: _DetailPane(
              selection: value,
              orgs: orgs,
              zones: zones,
              sites: sites,
              templates: templates,
              language: widget.language,
              profile: widget.profile,
              canManageOrgs: canManageOrgs,
              canManageZones: canManageZones,
              canManageSites: canManageSites,
              canEditOrgLogos: canEditOrgLogos,
              onReload: _load,
              onEditOrg: _editOrg,
              onEditZone: _editZone,
              onEditSite: _editSite,
              onDeleteSite: _deleteSite,
              onArchiveOrg: _archiveOrg,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _editOrg([Organization? existing]) async {
    if (!canManageOrgs) return;
    final nameEn = TextEditingController(text: existing?.nameEn ?? '');
    final nameAr = TextEditingController(text: existing?.nameAr ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          existing == null
              ? _t('New organization', 'جهة جديدة')
              : _t('Edit organization', 'تعديل جهة'),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameEn,
              decoration: InputDecoration(
                labelText: _t('Name EN', 'الاسم إنجليزي'),
              ),
            ),
            TextField(
              controller: nameAr,
              decoration: InputDecoration(
                labelText: _t('Name AR', 'الاسم عربي'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_t('Cancel', 'إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_t('Save', 'حفظ')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final repo = ref.read(organizationRepositoryProvider);
    if (existing == null) {
      final created = await repo.create(
        Organization(
          id: '',
          nameEn: nameEn.text.trim(),
          nameAr: nameAr.text.trim(),
        ),
      );
      await _load();
      if (mounted) {
        setState(() => selection = StructureOrgSelection(created.id));
      }
    } else {
      await repo.update(
        Organization(
          id: existing.id,
          nameEn: nameEn.text.trim(),
          nameAr: nameAr.text.trim(),
          isActive: existing.isActive,
          logoEnPath: existing.logoEnPath,
          logoArPath: existing.logoArPath,
          formTheme: existing.formTheme,
          formThemeAccent: existing.formThemeAccent,
        ),
      );
      await _load();
    }
  }

  Future<void> _editZone([Zone? existing, String? orgIdHint]) async {
    if (!canManageZones) return;
    final orgId =
        existing?.organizationId ??
        orgIdHint ??
        (selection is StructureOrgSelection
            ? (selection! as StructureOrgSelection).organizationId
            : null);
    if (orgId == null) return;
    final code = TextEditingController(text: existing?.code ?? '');
    final nameEn = TextEditingController(text: existing?.nameEn ?? '');
    final nameAr = TextEditingController(text: existing?.nameAr ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          existing == null
              ? _t('New zone', 'منطقة جديدة')
              : _t('Edit zone', 'تعديل منطقة'),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: code,
              decoration: InputDecoration(
                labelText: _t('Code (latin)', 'الرمز (لاتيني)'),
                hintText: 'doha_center',
              ),
            ),
            TextField(
              controller: nameEn,
              decoration: InputDecoration(
                labelText: _t('Name EN', 'الاسم إنجليزي'),
              ),
            ),
            TextField(
              controller: nameAr,
              decoration: InputDecoration(
                labelText: _t('Name AR', 'الاسم عربي'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_t('Cancel', 'إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_t('Save', 'حفظ')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final repo = ref.read(organizationRepositoryProvider);
    if (existing == null) {
      final created = await repo.createZone(
        Zone(
          id: '',
          organizationId: orgId,
          code: code.text.trim().toLowerCase(),
          nameEn: nameEn.text.trim(),
          nameAr: nameAr.text.trim(),
        ),
      );
      await _load();
      if (mounted) {
        setState(() => selection = StructureZoneSelection(created.id));
      }
    } else {
      await repo.updateZone(
        Zone(
          id: existing.id,
          organizationId: existing.organizationId,
          code: code.text.trim().toLowerCase(),
          nameEn: nameEn.text.trim(),
          nameAr: nameAr.text.trim(),
          isActive: existing.isActive,
          sortOrder: existing.sortOrder,
          reportLogoPath: existing.reportLogoPath,
          formTheme: existing.formTheme,
          formThemeAccent: existing.formThemeAccent,
        ),
      );
      await _load();
    }
  }

  Future<void> _editSite(
    ChecklistSite? existing, {
    bool asCampus = false,
    String? defaultParent,
    String? defaultZoneId,
    String? orgIdHint,
  }) async {
    if (!canManageSites) return;
    final orgId =
        existing?.organizationId ??
        orgIdHint ??
        () {
          final sel = selection;
          if (sel is StructureOrgSelection) return sel.organizationId;
          if (sel is StructureZoneSelection) {
            return zones
                .where((z) => z.id == sel.zoneId)
                .map((z) => z.organizationId)
                .firstOrNull;
          }
          if (sel is StructureCampusSelection) {
            return sites
                .where((s) => s.id == sel.siteId)
                .map((s) => s.organizationId)
                .firstOrNull;
          }
          return orgs.isNotEmpty ? orgs.first.id : null;
        }();
    if (orgId == null) return;

    final templates = await ref.read(catalogRepositoryProvider).listTemplates();
    if (!mounted) return;
    final nameEn = TextEditingController(text: existing?.nameEn ?? '');
    final nameAr = TextEditingController(text: existing?.nameAr ?? '');
    final code = TextEditingController(text: existing?.buildingCode ?? '');
    final pin = TextEditingController(text: existing?.pin ?? '');
    final location = TextEditingController(text: existing?.location ?? '');
    var checklistType = existing?.checklistType ?? 'DEFAULT';
    String? zoneId = existing?.zoneId ?? defaultZoneId;
    final isCampus =
        existing?.isCampus == true || (existing == null && asCampus);
    String? parentSiteId =
        existing?.parentSiteId ?? (isCampus ? null : defaultParent);
    final orgZones = zones.where((z) => z.organizationId == orgId).toList();
    final campusChoices = sites
        .where(
          (s) =>
              s.organizationId == orgId && s.isCampus && s.id != existing?.id,
        )
        .toList();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(
            existing == null
                ? (isCampus
                      ? _t('New campus / site', 'موقع جديد (حرم)')
                      : _t('New checklist unit', 'قائمة فحص جديدة'))
                : (isCampus
                      ? _t('Edit campus', 'تعديل موقع')
                      : _t('Edit checklist unit', 'تعديل قائمة فحص')),
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameEn,
                    decoration: InputDecoration(
                      labelText: _t('Name EN', 'الاسم إنجليزي'),
                    ),
                  ),
                  TextField(
                    controller: nameAr,
                    decoration: InputDecoration(
                      labelText: _t('Name AR', 'الاسم عربي'),
                    ),
                  ),
                  if (!isCampus) ...[
                    TextField(
                      controller: code,
                      decoration: InputDecoration(
                        labelText: _t(
                          'Building / list code',
                          'رمز المبنى / القائمة',
                        ),
                      ),
                    ),
                    TextField(
                      controller: pin,
                      decoration: const InputDecoration(labelText: 'PIN'),
                    ),
                    DropdownButtonFormField<String?>(
                      // ignore: deprecated_member_use
                      value: parentSiteId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: _t('Parent campus', 'الموقع الأب (الحرم)'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text(
                            _t('— Standalone —', '— بدون (مستقلة) —'),
                          ),
                        ),
                        for (final c in campusChoices)
                          DropdownMenuItem(
                            value: c.id,
                            child: Text(c.nameFor(widget.language)),
                          ),
                      ],
                      onChanged: (v) => setLocal(() => parentSiteId = v),
                    ),
                    DropdownButtonFormField<String>(
                      // ignore: deprecated_member_use
                      value: templates.any((t) => t.code == checklistType)
                          ? checklistType
                          : (templates.isNotEmpty
                                ? templates.first.code
                                : checklistType),
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: _t(
                          'Default checklist template',
                          'قالب قائمة الفحص الافتراضي',
                        ),
                      ),
                      items: [
                        for (final t in templates)
                          DropdownMenuItem(
                            value: t.code,
                            child: Text(
                              '${t.code} — ${ar ? t.nameAr : t.nameEn}',
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) setLocal(() => checklistType = v);
                      },
                    ),
                  ],
                  TextField(
                    controller: location,
                    decoration: InputDecoration(
                      labelText: _t('Location', 'الموقع / العنوان'),
                    ),
                  ),
                  DropdownButtonFormField<String?>(
                    // ignore: deprecated_member_use
                    value: zoneId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: _t('Zone', 'المنطقة'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: null,
                        child: Text(_t('— None —', '— بدون —')),
                      ),
                      for (final z in orgZones)
                        DropdownMenuItem(
                          value: z.id,
                          child: Text(z.nameFor(widget.language)),
                        ),
                    ],
                    onChanged: (v) => setLocal(() => zoneId = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_t('Cancel', 'إلغاء')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_t('Save', 'حفظ')),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final repo = ref.read(siteRepositoryProvider);
    final buildingCode = isCampus ? null : code.text.trim();
    if (existing == null) {
      final created = await repo.createSite(
        organizationId: orgId,
        zoneId: zoneId,
        parentSiteId: isCampus ? null : parentSiteId,
        nameEn: nameEn.text.trim(),
        nameAr: nameAr.text.trim(),
        buildingCode: buildingCode,
        pin: pin.text.trim(),
        checklistType: checklistType,
        location: location.text.trim().isEmpty ? '—' : location.text.trim(),
        siteType: isCampus ? 'headquarters' : 'other',
      );
      await _load();
      if (mounted) {
        setState(() {
          selection = isCampus
              ? StructureCampusSelection(created.id)
              : StructureChecklistSelection(created.id);
        });
      }
    } else {
      await repo.updateSite(
        id: existing.id,
        zoneId: zoneId,
        parentSiteId: isCampus ? null : parentSiteId,
        nameEn: nameEn.text.trim(),
        nameAr: nameAr.text.trim(),
        buildingCode: buildingCode,
        pin: pin.text.trim(),
        checklistType: checklistType,
        location: location.text.trim(),
        isActive: existing.isActive,
      );
      await _load();
    }
  }

  Future<void> _deleteSite(ChecklistSite site) async {
    if (!canManageSites) return;
    final label = site.isCampus
        ? site.nameFor(widget.language)
        : '${site.buildingCode} — ${site.nameFor(widget.language)}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          site.isCampus
              ? _t('Delete campus', 'حذف موقع')
              : _t('Delete checklist unit', 'حذف قائمة فحص'),
        ),
        content: Text(_t('Delete $label?', 'حذف $label؟')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_t('Cancel', 'إلغاء')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(_t('Delete', 'حذف')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(siteRepositoryProvider).deleteSite(site.id);
    await _load();
  }

  Future<void> _archiveOrg(Organization org) async {
    if (!canManageOrgs) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('Archive organization', 'أرشفة الجهة')),
        content: Text(
          _t(
            'Deactivate ${org.nameEn}? It will be hidden from active lists.',
            'تعطيل ${org.nameAr}؟ ستُخفى من القوائم النشطة.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_t('Cancel', 'إلغاء')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(_t('Archive', 'أرشفة')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref
        .read(organizationRepositoryProvider)
        .update(org.copyWith(isActive: false));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (message != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message!),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: Text(_t('Retry', 'إعادة'))),
          ],
        ),
      );
    }

    final wide = MediaQuery.sizeOf(context).width >= 900;
    final tree = _TreePane(
      orgs: orgs,
      zones: zones,
      sites: sites,
      selection: selection,
      language: widget.language,
      canEdit: canManageOrgs,
      onSelect: (v) => _select(v, wide: wide),
      onRefresh: _load,
      onAddOrg: canManageOrgs ? () => _editOrg() : null,
    );

    if (!wide) return tree;

    return Row(
      children: [
        SizedBox(
          width: 360,
          child: Material(
            color: Theme.of(context).colorScheme.surface.withValues(
              alpha: ChecklistChrome.listSurfaceOpacity,
            ),
            elevation: 1,
            child: tree,
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: selection == null
              ? Center(
                  child: Text(
                    _t(
                      'Select an organization, zone, or site',
                      'اختر جهة أو منطقة أو موقعاً',
                    ),
                  ),
                )
              : _DetailPane(
                  selection: selection!,
                  orgs: orgs,
                  zones: zones,
                  sites: sites,
                  templates: templates,
                  language: widget.language,
                  profile: widget.profile,
                  canManageOrgs: canManageOrgs,
                  canManageZones: canManageZones,
                  canManageSites: canManageSites,
                  canEditOrgLogos: canEditOrgLogos,
                  onReload: _load,
                  onEditOrg: _editOrg,
                  onEditZone: _editZone,
                  onEditSite: _editSite,
                  onDeleteSite: _deleteSite,
                  onArchiveOrg: _archiveOrg,
                ),
        ),
      ],
    );
  }
}

class _TreePane extends StatelessWidget {
  const _TreePane({
    required this.orgs,
    required this.zones,
    required this.sites,
    required this.selection,
    required this.language,
    required this.canEdit,
    required this.onSelect,
    required this.onRefresh,
    this.onAddOrg,
  });

  final List<Organization> orgs;
  final List<Zone> zones;
  final List<ChecklistSite> sites;
  final StructureSelection? selection;
  final String language;
  final bool canEdit;
  final ValueChanged<StructureSelection> onSelect;
  final VoidCallback onRefresh;
  final VoidCallback? onAddOrg;

  bool get ar => language == 'ar';
  String _t(String en, String arText) => ar ? arText : en;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _t('Structure', 'الهيكل'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: _t('Refresh', 'تحديث'),
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
              ),
              if (onAddOrg != null)
                FilledButton.tonalIcon(
                  onPressed: onAddOrg,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(_t('Add organization', 'إضافة جهة')),
                ),
            ],
          ),
        ),
        Expanded(
          child: orgs.isEmpty
              ? Center(child: Text(_t('No organizations', 'لا جهات')))
              : ListView(
                  padding: const EdgeInsets.only(bottom: 88),
                  children: [
                    for (final org in orgs)
                      _OrgNode(
                        org: org,
                        zones: zones
                            .where((z) => z.organizationId == org.id)
                            .toList(),
                        sites: sites
                            .where((s) => s.organizationId == org.id)
                            .toList(),
                        selection: selection,
                        language: language,
                        onSelect: onSelect,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _OrgNode extends StatelessWidget {
  const _OrgNode({
    required this.org,
    required this.zones,
    required this.sites,
    required this.selection,
    required this.language,
    required this.onSelect,
  });

  final Organization org;
  final List<Zone> zones;
  final List<ChecklistSite> sites;
  final StructureSelection? selection;
  final String language;
  final ValueChanged<StructureSelection> onSelect;

  @override
  Widget build(BuildContext context) {
    final selected =
        selection is StructureOrgSelection &&
        (selection! as StructureOrgSelection).organizationId == org.id;
    final theme = Theme.of(context);
    final sortedZones = [...zones]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Card(
        elevation: selected ? 2 : 0,
        color: selected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
            : null,
        child: Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: PageStorageKey<String>('organization-${org.id}'),
            initiallyExpanded: false,
            tilePadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: const Icon(Icons.account_balance_rounded),
            title: InkWell(
              onTap: () => onSelect(StructureOrgSelection(org.id)),
              child: Text(
                org.nameFor(language),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            children: [
              for (final zone in sortedZones)
                _ZoneNode(
                  zone: zone,
                  sites: sites,
                  selection: selection,
                  language: language,
                  onSelect: onSelect,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZoneNode extends StatelessWidget {
  const _ZoneNode({
    required this.zone,
    required this.sites,
    required this.selection,
    required this.language,
    required this.onSelect,
  });

  final Zone zone;
  final List<ChecklistSite> sites;
  final StructureSelection? selection;
  final String language;
  final ValueChanged<StructureSelection> onSelect;

  @override
  Widget build(BuildContext context) {
    final selected =
        selection is StructureZoneSelection &&
        (selection! as StructureZoneSelection).zoneId == zone.id;
    final theme = Theme.of(context);
    final inZone = sites.where((s) {
      if (s.zoneId == zone.id) return true;
      if (s.parentSiteId == null) return false;
      final parent = sites.where((p) => p.id == s.parentSiteId).firstOrNull;
      return parent?.zoneId == zone.id && s.zoneId == null;
    }).toList();
    final campuses = inZone.where((s) => s.isCampus).toList()
      ..sort((a, b) => a.nameEn.compareTo(b.nameEn));
    final units = inZone.where((s) => s.isChecklistUnit).toList();

    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: selected,
        tilePadding: const EdgeInsetsDirectional.only(start: 16, end: 8),
        leading: Icon(
          Icons.map_outlined,
          color: selected ? theme.colorScheme.primary : null,
        ),
        title: InkWell(
          onTap: () => onSelect(StructureZoneSelection(zone.id)),
          child: Text(
            zone.nameFor(language),
            style: TextStyle(
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
        children: [
          for (final campus in campuses)
            _CampusNode(
              campus: campus,
              checklists:
                  units.where((u) => u.parentSiteId == campus.id).toList()
                    ..sort((a, b) => a.buildingCode.compareTo(b.buildingCode)),
              selection: selection,
              language: language,
              onSelect: onSelect,
            ),
          for (final unit in units.where((u) => u.parentSiteId == null))
            _ChecklistLeaf(
              site: unit,
              selection: selection,
              language: language,
              onSelect: onSelect,
              indent: 32,
            ),
        ],
      ),
    );
  }
}

class _CampusNode extends StatelessWidget {
  const _CampusNode({
    required this.campus,
    required this.checklists,
    required this.selection,
    required this.language,
    required this.onSelect,
  });

  final ChecklistSite campus;
  final List<ChecklistSite> checklists;
  final StructureSelection? selection;
  final String language;
  final ValueChanged<StructureSelection> onSelect;

  @override
  Widget build(BuildContext context) {
    final selected =
        selection is StructureCampusSelection &&
        (selection! as StructureCampusSelection).siteId == campus.id;
    final theme = Theme.of(context);

    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded:
            selected ||
            (selection is StructureChecklistSelection &&
                checklists.any(
                  (c) =>
                      c.id ==
                      (selection! as StructureChecklistSelection).siteId,
                )),
        tilePadding: const EdgeInsetsDirectional.only(start: 28, end: 8),
        leading: _ThemeMarker(
          paperTheme: campus.paperTheme,
          icon: Icons.place_outlined,
          selected: selected,
        ),
        title: InkWell(
          onTap: () => onSelect(StructureCampusSelection(campus.id)),
          child: Text(
            campus.nameFor(language),
            style: TextStyle(
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
        children: [
          for (final unit in checklists)
            _ChecklistLeaf(
              site: unit,
              selection: selection,
              language: language,
              onSelect: onSelect,
              indent: 44,
            ),
        ],
      ),
    );
  }
}

class _ChecklistLeaf extends StatelessWidget {
  const _ChecklistLeaf({
    required this.site,
    required this.selection,
    required this.language,
    required this.onSelect,
    required this.indent,
  });

  final ChecklistSite site;
  final StructureSelection? selection;
  final String language;
  final ValueChanged<StructureSelection> onSelect;
  final double indent;

  @override
  Widget build(BuildContext context) {
    final selected =
        selection is StructureChecklistSelection &&
        (selection! as StructureChecklistSelection).siteId == site.id;
    return ListTile(
      selected: selected,
      contentPadding: EdgeInsetsDirectional.only(start: indent, end: 8),
      leading: _ThemeMarker(
        paperTheme: site.paperTheme,
        icon: Icons.checklist_rtl,
        selected: selected,
        size: 28,
      ),
      title: Text(
        '${site.buildingCode} — ${site.nameFor(language)}',
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
      subtitle: Text(site.checklistType),
      onTap: () => onSelect(StructureChecklistSelection(site.id)),
    );
  }
}

class _ThemeMarker extends StatelessWidget {
  const _ThemeMarker({
    required this.paperTheme,
    required this.icon,
    required this.selected,
    this.size = 32,
  });

  final FormPaperTheme paperTheme;
  final IconData icon;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: paperTheme.accent,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : paperTheme.border,
          width: selected ? 2 : 1,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.56, color: paperTheme.accentText),
    );
  }
}

class _DetailPane extends ConsumerWidget {
  const _DetailPane({
    required this.selection,
    required this.orgs,
    required this.zones,
    required this.sites,
    required this.templates,
    required this.language,
    required this.profile,
    required this.canManageOrgs,
    required this.canManageZones,
    required this.canManageSites,
    required this.canEditOrgLogos,
    required this.onReload,
    required this.onEditOrg,
    required this.onEditZone,
    required this.onEditSite,
    required this.onDeleteSite,
    required this.onArchiveOrg,
  });

  final StructureSelection selection;
  final List<Organization> orgs;
  final List<Zone> zones;
  final List<ChecklistSite> sites;
  final List<ChecklistTemplate> templates;
  final String language;
  final Profile profile;
  final bool canManageOrgs;
  final bool canManageZones;
  final bool canManageSites;
  final bool canEditOrgLogos;
  final Future<void> Function() onReload;
  final Future<void> Function([Organization?]) onEditOrg;
  final Future<void> Function([Zone?, String?]) onEditZone;
  final Future<void> Function(
    ChecklistSite?, {
    bool asCampus,
    String? defaultParent,
    String? defaultZoneId,
    String? orgIdHint,
  })
  onEditSite;
  final Future<void> Function(ChecklistSite) onDeleteSite;
  final Future<void> Function(Organization) onArchiveOrg;

  bool get ar => language == 'ar';
  String _t(String en, String arText) => ar ? arText : en;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (selection) {
      StructureOrgSelection(:final organizationId) => _orgDetail(
        context,
        ref,
        orgs.firstWhere((o) => o.id == organizationId),
      ),
      StructureZoneSelection(:final zoneId) => _zoneDetail(
        context,
        ref,
        zones.firstWhere((z) => z.id == zoneId),
      ),
      StructureCampusSelection(:final siteId) => _siteDetail(
        context,
        ref,
        sites.firstWhere((s) => s.id == siteId),
        isCampus: true,
      ),
      StructureChecklistSelection(:final siteId) => _siteDetail(
        context,
        ref,
        sites.firstWhere((s) => s.id == siteId),
        isCampus: false,
      ),
    };
  }

  Widget _headerBlock(
    BuildContext context, {
    required String title,
    String? subtitle,
    required List<Widget> chips,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (subtitle != null && subtitle.trim().isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
        ],
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: chips),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _statusChip({required bool active}) {
    return Chip(
      avatar: Icon(
        active ? Icons.check_circle : Icons.pause_circle_filled,
        size: 16,
        color: active ? Colors.green.shade700 : Colors.orange.shade800,
      ),
      label: Text(active ? _t('Active', 'مفعل') : _t('Inactive', 'معطل')),
      visualDensity: VisualDensity.compact,
      backgroundColor: active ? Colors.green.shade50 : Colors.orange.shade50,
    );
  }

  Widget _countChip(String label, IconData icon) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }

  FormPaperTheme _organizationTheme(String organizationId) {
    final org = orgs.where((item) => item.id == organizationId).firstOrNull;
    return org?.paperTheme ?? FormPaperTheme.classicGold;
  }

  FormPaperTheme _zoneTheme(Zone zone) {
    if (FormThemeKey.fromDb(zone.formTheme) == FormThemeKey.inherit) {
      return _organizationTheme(zone.organizationId);
    }
    return FormPaperTheme.resolve(
      themeDb: zone.formTheme,
      accentHex: zone.formThemeAccent,
    );
  }

  FormPaperTheme _inheritedSiteTheme(ChecklistSite site) {
    final parentId = site.parentSiteId;
    ChecklistSite? parent;
    if (parentId != null) {
      parent = sites.where((item) => item.id == parentId).firstOrNull;
      if (parent != null &&
          FormThemeKey.fromDb(parent.formTheme) != FormThemeKey.inherit) {
        return FormPaperTheme.resolve(
          themeDb: parent.formTheme,
          accentHex: parent.formThemeAccent,
        );
      }
    }
    final zoneId = site.zoneId ?? parent?.zoneId;
    if (zoneId != null) {
      final zone = zones.where((item) => item.id == zoneId).firstOrNull;
      if (zone != null &&
          FormThemeKey.fromDb(zone.formTheme) != FormThemeKey.inherit) {
        return FormPaperTheme.resolve(
          themeDb: zone.formTheme,
          accentHex: zone.formThemeAccent,
        );
      }
    }
    final template = templates
        .where((item) => item.code == site.checklistType)
        .firstOrNull;
    if (template != null &&
        FormThemeKey.fromDb(template.formTheme) != FormThemeKey.inherit) {
      return template.paperTheme;
    }
    return _organizationTheme(site.organizationId);
  }

  String _themeSubtitle({
    required String rawTheme,
    required FormPaperTheme effective,
    String? source,
  }) {
    final rawLabel = FormThemeKey.fromDb(rawTheme).labelFor(language);
    final color = FormPaperTheme.hexOf(effective.accent);
    final sourceText = switch (source) {
      'site' => _t('this checklist/site', 'هذه القائمة/الموقع'),
      'campus' => _t('parent site', 'الموقع الأب'),
      'zone' => _t('zone', 'المنطقة'),
      'organization' => _t('organization', 'الجهة'),
      'template' => _t('list type', 'نوع القائمة'),
      'default' => _t('default', 'الافتراضي'),
      _ => null,
    };
    return sourceText == null
        ? '$rawLabel · $color'
        : '$rawLabel · $color · ${_t('from', 'من')} $sourceText';
  }

  Future<void> _showThemePicker(
    BuildContext context, {
    required String scopeName,
    required String currentTheme,
    required String? currentAccent,
    required bool allowInherit,
    required FormPaperTheme inheritedTheme,
    required Future<void> Function(String theme, String? accent) onSave,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => FormThemePickerDialog(
        language: language,
        scopeName: scopeName,
        currentTheme: currentTheme,
        currentAccent: currentAccent,
        allowInherit: allowInherit,
        inheritedTheme: inheritedTheme,
        onSave: onSave,
      ),
    );
    if (ok == true) await onReload();
  }

  Widget _orgDetail(BuildContext context, WidgetRef ref, Organization org) {
    final orgZones = zones.where((z) => z.organizationId == org.id).length;
    final orgSites = sites
        .where((s) => s.organizationId == org.id && s.isCampus)
        .length;
    final orgUnits = sites
        .where((s) => s.organizationId == org.id && s.isChecklistUnit)
        .length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _headerBlock(
          context,
          title: org.nameFor(language),
          subtitle: language == 'ar' ? org.nameEn : org.nameAr,
          chips: [
            _statusChip(active: org.isActive),
            _countChip(
              _t('$orgSites sites', '$orgSites مواقع'),
              Icons.location_city_outlined,
            ),
            _countChip(
              _t('$orgZones zones', '$orgZones مناطق'),
              Icons.map_outlined,
            ),
            _countChip(
              _t('$orgUnits lists', '$orgUnits قوائم'),
              Icons.checklist_rtl,
            ),
          ],
        ),
        StructureActionTile(
          icon: Icons.palette_outlined,
          label: _t('Organization checklist theme', 'ثيم قوائم الجهة'),
          subtitle: _themeSubtitle(
            rawTheme: org.formTheme,
            effective: org.paperTheme,
            source: 'organization',
          ),
          enabled: profile.isPlatformOwner,
          onTap: () => _showThemePicker(
            context,
            scopeName: org.nameFor(language),
            currentTheme: org.formTheme,
            currentAccent: org.formThemeAccent,
            allowInherit: false,
            inheritedTheme: FormPaperTheme.classicGold,
            onSave: (theme, accent) => ref
                .read(organizationRepositoryProvider)
                .updateOrganizationFormTheme(
                  id: org.id,
                  formTheme: theme,
                  formThemeAccent: accent,
                ),
          ),
        ),
        StructureActionTile(
          icon: Icons.map_outlined,
          label: _t('Add zone', 'إضافة منطقة'),
          enabled: canManageZones,
          onTap: () => onEditZone(null, org.id),
        ),
        StructureActionTile(
          icon: Icons.account_balance_outlined,
          label: _t('Add campus / site', 'إضافة موقع'),
          enabled: canManageZones || canManageSites,
          onTap: () => onEditSite(null, asCampus: true, orgIdHint: org.id),
        ),
        StructureActionTile(
          icon: Icons.image_outlined,
          label: _t('Report logos', 'شعارات التقرير'),
          subtitle: _t(
            'Organization Arabic / English header logos',
            'شعار الجهة بالعربي والإنجليزي أعلى الورقة',
          ),
          enabled: canEditOrgLogos,
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ReportLogosScreen.org(
                  organization: org,
                  language: language,
                  canEdit: canEditOrgLogos,
                ),
              ),
            );
            await onReload();
          },
        ),
        StructureActionTile(
          icon: Icons.admin_panel_settings_outlined,
          label: _t('Organization users & access', 'صلاحية التحكم بالجهة'),
          enabled: profile.canUseAdminApp,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: Text(_t('Users', 'المستخدمون'))),
                  body: UsersTab(profile: profile),
                ),
              ),
            );
          },
        ),
        StructureActionTile(
          icon: Icons.policy_outlined,
          label: _t('Policy settings', 'إعدادات السياسات'),
          enabled: profile.canManagePolicies,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PoliciesScreen(
                  profile: profile,
                  initialOrganizationId: org.id,
                ),
              ),
            );
          },
        ),
        StructureActionTile(
          icon: Icons.edit_outlined,
          label: _t('Edit organization', 'تعديل الجهة'),
          enabled: canManageOrgs,
          onTap: () => onEditOrg(org),
        ),
        if (canManageOrgs)
          StructureActionTile(
            icon: Icons.archive_outlined,
            label: _t('Archive', 'أرشفة'),
            enabled: org.isActive,
            destructive: true,
            onTap: () => onArchiveOrg(org),
          ),
      ],
    );
  }

  Widget _zoneDetail(BuildContext context, WidgetRef ref, Zone zone) {
    final campuses = sites
        .where((s) => s.zoneId == zone.id && s.isCampus)
        .length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _headerBlock(
          context,
          title: zone.nameFor(language),
          subtitle: zone.code,
          chips: [
            _statusChip(active: zone.isActive),
            _countChip(
              _t('$campuses sites', '$campuses مواقع'),
              Icons.location_city_outlined,
            ),
          ],
        ),
        StructureActionTile(
          icon: Icons.palette_outlined,
          label: _t('Zone checklist theme', 'ثيم قوائم المنطقة'),
          subtitle: _themeSubtitle(
            rawTheme: zone.formTheme,
            effective: _zoneTheme(zone),
            source: FormThemeKey.fromDb(zone.formTheme) == FormThemeKey.inherit
                ? 'organization'
                : 'zone',
          ),
          enabled: profile.canManageFormThemes,
          onTap: () => _showThemePicker(
            context,
            scopeName: zone.nameFor(language),
            currentTheme: zone.formTheme,
            currentAccent: zone.formThemeAccent,
            allowInherit: true,
            inheritedTheme: _organizationTheme(zone.organizationId),
            onSave: (theme, accent) => ref
                .read(organizationRepositoryProvider)
                .updateZoneFormTheme(
                  id: zone.id,
                  formTheme: theme,
                  formThemeAccent: accent,
                ),
          ),
        ),
        StructureActionTile(
          icon: Icons.account_balance_outlined,
          label: _t('Add campus / site', 'إضافة موقع'),
          enabled: canManageZones || canManageSites,
          onTap: () => onEditSite(
            null,
            asCampus: true,
            defaultZoneId: zone.id,
            orgIdHint: zone.organizationId,
          ),
        ),
        StructureActionTile(
          icon: Icons.image_outlined,
          label: _t('Zone report logo', 'شعار المنطقة في التقرير'),
          subtitle: _t(
            'Footer: bottom-right EN · bottom-left AR',
            'أسفل الورقة: يمين EN · يسار AR',
          ),
          enabled: canManageZones,
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ReportLogosScreen.zone(
                  zone: zone,
                  language: language,
                  canEdit: canManageZones,
                ),
              ),
            );
            await onReload();
          },
        ),
        StructureActionTile(
          icon: Icons.admin_panel_settings_outlined,
          label: _t('Zone users & access', 'صلاحيات المنطقة'),
          enabled: profile.canUseAdminApp,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: Text(_t('Users', 'المستخدمون'))),
                  body: UsersTab(profile: profile),
                ),
              ),
            );
          },
        ),
        StructureActionTile(
          icon: Icons.edit_outlined,
          label: _t('Edit zone', 'تعديل المنطقة'),
          enabled: canManageZones,
          onTap: () => onEditZone(zone),
        ),
      ],
    );
  }

  Widget _siteDetail(
    BuildContext context,
    WidgetRef ref,
    ChecklistSite site, {
    required bool isCampus,
  }) {
    final childCount = isCampus
        ? sites.where((s) => s.parentSiteId == site.id).length
        : 0;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _headerBlock(
          context,
          title: isCampus
              ? site.nameFor(language)
              : '${site.buildingCode} — ${site.nameFor(language)}',
          subtitle: isCampus
              ? _t('Campus / site', 'موقع / حرم')
              : _t(
                  'Template ${site.checklistType} · PIN ${site.pin}',
                  'قالب ${site.checklistType} · رقم ${site.pin}',
                ),
          chips: [
            _statusChip(active: site.isActive),
            if (isCampus)
              _countChip(
                _t('$childCount checklists', '$childCount قوائم'),
                Icons.checklist_rtl,
              ),
          ],
        ),
        if (isCampus)
          StructureActionTile(
            icon: Icons.playlist_add_check,
            label: _t('Add checklist unit', 'إضافة قائمة فحص'),
            enabled: canManageSites,
            onTap: () => onEditSite(
              null,
              asCampus: false,
              defaultParent: site.id,
              defaultZoneId: site.zoneId,
              orgIdHint: site.organizationId,
            ),
          ),
        StructureActionTile(
          icon: Icons.image_outlined,
          label: isCampus
              ? _t('Site report logo', 'شعار الموقع في التقرير')
              : _t('Checklist report logo', 'شعار القائمة في التقرير'),
          subtitle: _t(
            'Footer: bottom-left EN · bottom-right AR',
            'أسفل الورقة: يسار EN · يمين AR',
          ),
          enabled: canManageSites,
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ReportLogosScreen.site(
                  site: site,
                  language: language,
                  canEdit: canManageSites,
                  isCampus: isCampus,
                ),
              ),
            );
            await onReload();
          },
        ),
        StructureActionTile(
          icon: Icons.palette_outlined,
          label: isCampus
              ? _t('Site checklist theme', 'ثيم قوائم الموقع')
              : _t('Checklist theme', 'ثيم القائمة'),
          subtitle: _themeSubtitle(
            rawTheme: site.formTheme,
            effective: site.paperTheme,
            source: site.formThemeSource,
          ),
          enabled: profile.canManageFormThemes,
          onTap: () => _showThemePicker(
            context,
            scopeName: site.nameFor(language),
            currentTheme: site.formTheme,
            currentAccent: site.formThemeAccent,
            allowInherit: true,
            inheritedTheme: _inheritedSiteTheme(site),
            onSave: (theme, accent) => ref
                .read(siteRepositoryProvider)
                .updateFormTheme(
                  id: site.id,
                  formTheme: theme,
                  formThemeAccent: accent,
                ),
          ),
        ),
        StructureActionTile(
          icon: Icons.admin_panel_settings_outlined,
          label: _t('Access & users', 'الصلاحيات والمستخدمون'),
          enabled: profile.canUseAdminApp,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: Text(_t('Users', 'المستخدمون'))),
                  body: UsersTab(profile: profile),
                ),
              ),
            );
          },
        ),
        StructureActionTile(
          icon: Icons.edit_outlined,
          label: isCampus
              ? _t('Edit site', 'تعديل الموقع')
              : _t('Edit checklist', 'تعديل القائمة'),
          enabled: canManageSites,
          onTap: () => onEditSite(site, asCampus: isCampus),
        ),
        if (canManageSites)
          StructureActionTile(
            icon: Icons.delete_forever_outlined,
            label: _t('Delete', 'حذف'),
            enabled: true,
            destructive: true,
            onTap: () => onDeleteSite(site),
          ),
      ],
    );
  }
}
