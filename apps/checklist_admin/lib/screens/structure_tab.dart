import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Org → Zone → Site (campus) → checklist units tree.
class StructureTab extends ConsumerStatefulWidget {
  const StructureTab({super.key, required this.profile});
  final Profile profile;

  @override
  ConsumerState<StructureTab> createState() => _StructureTabState();
}

class _StructureTabState extends ConsumerState<StructureTab> {
  List<Organization> orgs = [];
  List<Zone> zones = [];
  List<ChecklistSite> sites = [];
  bool loading = true;
  String? message;
  String? selectedOrgId;

  bool get canEdit => widget.profile.canManageStructure;

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
      setState(() {
        orgs = o;
        zones = z;
        sites = s;
        selectedOrgId ??= o.isNotEmpty ? o.first.id : null;
      });
    } catch (e) {
      setState(() => message = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _editOrg([Organization? existing]) async {
    final nameEn = TextEditingController(text: existing?.nameEn ?? '');
    final nameAr = TextEditingController(text: existing?.nameAr ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'جهة جديدة' : 'تعديل جهة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameEn,
              decoration: const InputDecoration(labelText: 'Name EN'),
            ),
            TextField(
              controller: nameAr,
              decoration: const InputDecoration(labelText: 'الاسم عربي'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final repo = ref.read(organizationRepositoryProvider);
    if (existing == null) {
      await repo.create(Organization(
        id: '',
        nameEn: nameEn.text.trim(),
        nameAr: nameAr.text.trim(),
      ));
    } else {
      await repo.update(Organization(
        id: existing.id,
        nameEn: nameEn.text.trim(),
        nameAr: nameAr.text.trim(),
        isActive: existing.isActive,
      ));
    }
    await _load();
  }

  Future<void> _editZone([Zone? existing]) async {
    final orgId = existing?.organizationId ?? selectedOrgId;
    if (orgId == null) return;
    final code = TextEditingController(text: existing?.code ?? '');
    final nameEn = TextEditingController(text: existing?.nameEn ?? '');
    final nameAr = TextEditingController(text: existing?.nameAr ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'منطقة جديدة' : 'تعديل منطقة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: code,
              decoration: const InputDecoration(
                labelText: 'Code (latin)',
                hintText: 'moehe_hq',
              ),
            ),
            TextField(
              controller: nameEn,
              decoration: const InputDecoration(labelText: 'Name EN'),
            ),
            TextField(
              controller: nameAr,
              decoration: const InputDecoration(labelText: 'الاسم عربي'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final repo = ref.read(organizationRepositoryProvider);
    if (existing == null) {
      await repo.createZone(Zone(
        id: '',
        organizationId: orgId,
        code: code.text.trim().toLowerCase(),
        nameEn: nameEn.text.trim(),
        nameAr: nameAr.text.trim(),
      ));
    } else {
      await repo.updateZone(Zone(
        id: existing.id,
        organizationId: existing.organizationId,
        code: code.text.trim().toLowerCase(),
        nameEn: nameEn.text.trim(),
        nameAr: nameAr.text.trim(),
        isActive: existing.isActive,
        sortOrder: existing.sortOrder,
      ));
    }
    await _load();
  }

  /// [asCampus]=true creates/edits a container site (no building_code).
  /// [defaultParent] pre-selects parent when adding a checklist under a campus.
  Future<void> _editSite(
    ChecklistSite? existing, {
    bool asCampus = false,
    String? defaultParent,
  }) async {
    final orgId = existing?.organizationId ?? selectedOrgId;
    if (orgId == null) return;
    final templates =
        await ref.read(catalogRepositoryProvider).listTemplates();
    final nameEn = TextEditingController(text: existing?.nameEn ?? '');
    final nameAr = TextEditingController(text: existing?.nameAr ?? '');
    final code = TextEditingController(text: existing?.buildingCode ?? '');
    final pin = TextEditingController(text: existing?.pin ?? '');
    final location = TextEditingController(
      text: existing?.location ?? 'MOEHE Permanent Headquarters',
    );
    var checklistType = existing?.checklistType ?? 'DEFAULT';
    String? zoneId = existing?.zoneId;
    final isCampus =
        existing?.isCampus == true || (existing == null && asCampus);
    String? parentSiteId =
        existing?.parentSiteId ?? (isCampus ? null : defaultParent);
    final orgZones = zones.where((z) => z.organizationId == orgId).toList();
    final campusChoices = sites
        .where((s) =>
            s.organizationId == orgId &&
            s.isCampus &&
            s.id != existing?.id)
        .toList();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(
            existing == null
                ? (isCampus ? 'موقع جديد (حرم)' : 'قائمة فحص جديدة')
                : (isCampus ? 'تعديل موقع' : 'تعديل قائمة فحص'),
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameEn,
                    decoration: const InputDecoration(labelText: 'Name EN'),
                  ),
                  TextField(
                    controller: nameAr,
                    decoration:
                        const InputDecoration(labelText: 'الاسم عربي'),
                  ),
                  if (!isCampus) ...[
                    TextField(
                      controller: code,
                      decoration: const InputDecoration(
                        labelText: 'رمز المبنى / القائمة',
                        hintText: 'B1',
                      ),
                    ),
                    TextField(
                      controller: pin,
                      decoration: const InputDecoration(labelText: 'PIN'),
                    ),
                    DropdownButtonFormField<String?>(
                      // ignore: deprecated_member_use
                      value: parentSiteId,
                      decoration: const InputDecoration(
                        labelText: 'الموقع الأب (الحرم)',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('— بدون (مستقلة) —'),
                        ),
                        for (final c in campusChoices)
                          DropdownMenuItem(
                            value: c.id,
                            child: Text(c.nameAr),
                          ),
                      ],
                      onChanged: (v) => setLocal(() => parentSiteId = v),
                    ),
                    DropdownButtonFormField<String>(
                      // ignore: deprecated_member_use
                      value: checklistType,
                      decoration: const InputDecoration(
                        labelText: 'قالب قائمة الفحص',
                      ),
                      items: [
                        for (final t in templates)
                          DropdownMenuItem(
                            value: t.code,
                            child: Text('${t.code} — ${t.nameAr}'),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) setLocal(() => checklistType = v);
                      },
                    ),
                  ],
                  TextField(
                    controller: location,
                    decoration: const InputDecoration(labelText: 'Location'),
                  ),
                  DropdownButtonFormField<String?>(
                    // ignore: deprecated_member_use
                    value: zoneId,
                    decoration: const InputDecoration(labelText: 'المنطقة'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('— بدون —'),
                      ),
                      for (final z in orgZones)
                        DropdownMenuItem(
                          value: z.id,
                          child: Text(z.nameAr ?? z.nameEn),
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
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final repo = ref.read(siteRepositoryProvider);
    final buildingCode = isCampus ? null : code.text.trim();
    if (existing == null) {
      await repo.createSite(
        organizationId: orgId,
        zoneId: zoneId,
        parentSiteId: isCampus ? null : parentSiteId,
        nameEn: nameEn.text.trim(),
        nameAr: nameAr.text.trim(),
        buildingCode: buildingCode,
        pin: pin.text.trim(),
        checklistType: checklistType,
        location: location.text.trim().isEmpty
            ? 'MOEHE Permanent Headquarters'
            : location.text.trim(),
        siteType: isCampus ? 'headquarters' : 'other',
      );
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
    }
    await _load();
  }

  Future<void> _deleteSite(ChecklistSite site) async {
    final label =
        site.isCampus ? site.nameAr : '${site.buildingCode} — ${site.nameAr}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(site.isCampus ? 'حذف موقع' : 'حذف قائمة فحص'),
        content: Text('حذف $label؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(siteRepositoryProvider).deleteSite(site.id);
    await _load();
  }

  List<Widget> _siteTreeTiles(List<ChecklistSite> orgSites) {
    final groups = groupChecklistsByCampus(
      checklists: orgSites.where((s) => s.isChecklistUnit).toList(),
      allSites: orgSites,
    );
    final tiles = <Widget>[];
    final shownCampusIds = <String>{};

    for (final g in groups) {
      final campus = g.campus;
      if (campus != null) {
        shownCampusIds.add(campus.id);
        tiles.add(
          ExpansionTile(
            initiallyExpanded: true,
            leading: const Icon(Icons.account_balance_outlined),
            title: Text(
              campus.nameAr,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              'موقع · ${g.checklists.length} قوائم فحص',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: canEdit
                ? Wrap(
                    children: [
                      IconButton(
                        tooltip: 'قائمة فحص داخل الموقع',
                        icon: const Icon(Icons.playlist_add),
                        onPressed: () => _editSite(
                          null,
                          defaultParent: campus.id,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () =>
                            _editSite(campus, asCampus: true),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.red),
                        onPressed: () => _deleteSite(campus),
                      ),
                    ],
                  )
                : null,
            children: [
              for (final s in g.checklists)
                ListTile(
                  contentPadding: const EdgeInsets.only(left: 40, right: 8),
                  leading: const Icon(Icons.checklist_rtl, size: 20),
                  title: Text('${s.buildingCode} — ${s.nameAr}'),
                  subtitle: Text('${s.checklistType} • ${s.pin}'),
                  trailing: canEdit
                      ? Wrap(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _editSite(s),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.red),
                              onPressed: () => _deleteSite(s),
                            ),
                          ],
                        )
                      : Text(s.isActive ? 'نشط' : 'موقوف'),
                ),
            ],
          ),
        );
      } else {
        for (final s in g.checklists) {
          tiles.add(
            ListTile(
              leading: const Icon(Icons.checklist_rtl),
              title: Text('${s.buildingCode} — ${s.nameAr}'),
              subtitle: Text('قائمة مستقلة · ${s.checklistType}'),
              trailing: canEdit
                  ? Wrap(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _editSite(s),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red),
                          onPressed: () => _deleteSite(s),
                        ),
                      ],
                    )
                  : null,
            ),
          );
        }
      }
    }

    // Campus sites with no checklists yet
    for (final c in orgSites.where((s) => s.isCampus)) {
      if (shownCampusIds.contains(c.id)) continue;
      tiles.add(
        ListTile(
          leading: const Icon(Icons.account_balance_outlined),
          title: Text(c.nameAr),
          subtitle: const Text('موقع · بدون قوائم بعد'),
          trailing: canEdit
              ? Wrap(
                  children: [
                    IconButton(
                      tooltip: 'قائمة فحص داخل الموقع',
                      icon: const Icon(Icons.playlist_add),
                      onPressed: () =>
                          _editSite(null, defaultParent: c.id),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _editSite(c, asCampus: true),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.red),
                      onPressed: () => _deleteSite(c),
                    ),
                  ],
                )
              : null,
        ),
      );
    }
    return tiles;
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    final orgZones =
        zones.where((z) => z.organizationId == selectedOrgId).toList();
    final orgSites =
        sites.where((s) => s.organizationId == selectedOrgId).toList();

    return Column(
      children: [
        if (message != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(message!, style: const TextStyle(color: Colors.red)),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: selectedOrgId,
                  decoration: const InputDecoration(
                    labelText: 'الجهة',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final o in orgs)
                      DropdownMenuItem(
                        value: o.id,
                        child: Text(o.nameAr),
                      ),
                  ],
                  onChanged: (v) => setState(() => selectedOrgId = v),
                ),
              ),
              if (canEdit) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'جهة جديدة',
                  onPressed: () => _editOrg(),
                  icon: const Icon(Icons.domain_add),
                ),
                if (selectedOrgId != null)
                  IconButton(
                    tooltip: 'تعديل الجهة',
                    onPressed: () {
                      final o = orgs.cast<Organization?>().firstWhere(
                            (e) => e?.id == selectedOrgId,
                            orElse: () => null,
                          );
                      if (o != null) _editOrg(o);
                    },
                    icon: const Icon(Icons.edit),
                  ),
              ],
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              ListTile(
                title: const Text(
                  'المناطق',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                trailing: canEdit
                    ? IconButton(
                        onPressed: () => _editZone(),
                        icon: const Icon(Icons.add),
                      )
                    : null,
              ),
              for (final z in orgZones)
                ListTile(
                  leading: const Icon(Icons.map_outlined),
                  title: Text(z.nameAr ?? z.nameEn),
                  subtitle: Text(z.code),
                  trailing: canEdit
                      ? IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _editZone(z),
                        )
                      : null,
                ),
              const Divider(),
              ListTile(
                title: const Text(
                  'المواقع وقوائم الفحص',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                trailing: canEdit
                    ? PopupMenuButton<String>(
                        tooltip: 'إضافة',
                        onSelected: (v) {
                          if (v == 'campus') {
                            _editSite(null, asCampus: true);
                          } else {
                            _editSite(null);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'campus',
                            child: Text('موقع (حرم) جديد'),
                          ),
                          PopupMenuItem(
                            value: 'checklist',
                            child: Text('قائمة فحص جديدة'),
                          ),
                        ],
                        icon: const Icon(Icons.add),
                      )
                    : null,
              ),
              ..._siteTreeTiles(orgSites),
            ],
          ),
        ),
      ],
    );
  }
}
