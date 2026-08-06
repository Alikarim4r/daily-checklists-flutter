import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChecklistsTab extends ConsumerStatefulWidget {
  const ChecklistsTab({super.key, required this.profile});
  final Profile profile;

  @override
  ConsumerState<ChecklistsTab> createState() => _ChecklistsTabState();
}

class _ChecklistsTabState extends ConsumerState<ChecklistsTab> {
  int mode = 0; // 0 templates, 1 site binding
  List<ChecklistTemplate> templates = [];
  ChecklistTemplate? selected;
  List<CatalogItem> items = [];
  List<ChecklistSite> sites = [];
  List<CampusChecklistGroup> campusGroups = [];
  ChecklistSite? selectedSite;
  List<CatalogItem> siteExtras = [];
  bool loading = true;
  String? message;

  bool get canEditTemplates =>
      widget.profile.isPlatformOwner ||
      widget.profile.role == UserRole.superAdmin;

  bool get canEditSites =>
      widget.profile.isPlatformOwner || widget.profile.role.isElevatedAdmin;

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
      final list = await ref
          .read(catalogRepositoryProvider)
          .listTemplates(activeOnly: false);
      final groups = await ref
          .read(siteRepositoryProvider)
          .listAccessibleCampusGroups(profile: widget.profile);
      final siteList = [for (final g in groups) ...g.checklists];
      setState(() {
        templates = list;
        campusGroups = groups;
        sites = siteList;
        selectedSite ??= siteList.isNotEmpty ? siteList.first : null;
      });
      if (selected != null) {
        await _selectTemplate(selected!.id);
      } else if (list.isNotEmpty) {
        await _selectTemplate(list.first.id);
      }
      if (selectedSite != null) await _loadSiteExtras();
    } catch (e) {
      setState(() => message = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _selectTemplate(String id) async {
    final full = await ref.read(catalogRepositoryProvider).getTemplateById(id);
    setState(() {
      selected = full;
      items = full?.items ?? [];
    });
  }

  Future<void> _loadSiteExtras() async {
    final site = selectedSite;
    if (site == null) return;
    final extras =
        await ref.read(catalogRepositoryProvider).listSiteExtraItems(site.id);
    if (mounted) setState(() => siteExtras = extras);
  }

  Future<void> _bindTemplateToSite(String code) async {
    final site = selectedSite;
    if (site == null || !canEditSites) return;
    await ref.read(siteRepositoryProvider).updateChecklistType(
          site: site,
          checklistType: code,
        );
    final refreshed = await ref.read(siteRepositoryProvider).listAccessibleSites(
          profile: widget.profile,
        );
    final match = refreshed.where((s) => s.id == site.id);
    setState(() {
      sites = refreshed;
      if (match.isNotEmpty) selectedSite = match.first;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم ربط ${site.buildingCode} بـ $code')),
      );
    }
  }

  Future<void> _editItem([CatalogItem? existing]) async {
    if (selected == null || !canEditTemplates) return;
    final en = TextEditingController(text: existing?.descriptionEn ?? '');
    final ar = TextEditingController(text: existing?.descriptionAr ?? '');
    var def = existing?.defaultAnswer ?? 'Y';
    var overdueDays = existing?.overdueAfterDays ?? 3;
    final indexCtrl = TextEditingController(
      text:
          '${existing?.itemIndex ?? ((items.isEmpty ? 0 : items.map((e) => e.itemIndex).reduce((a, b) => a > b ? a : b)) + 1)}',
    );
    final overdueCtrl = TextEditingController(text: '$overdueDays');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(existing == null ? 'بند جديد' : 'تعديل بند'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: indexCtrl,
                  decoration: const InputDecoration(labelText: 'رقم البند'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: en,
                  decoration:
                      const InputDecoration(labelText: 'Description EN'),
                  maxLines: 2,
                ),
                TextField(
                  controller: ar,
                  decoration: const InputDecoration(labelText: 'الوصف عربي'),
                  maxLines: 2,
                ),
                DropdownButtonFormField<String>(
                  initialValue: def,
                  decoration: const InputDecoration(
                    labelText: 'الجواب الافتراضي (الحالة المثالية)',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Y', child: Text('Yes / نعم')),
                    DropdownMenuItem(value: 'N', child: Text('No / لا')),
                    DropdownMenuItem(value: 'NA', child: Text('NA / غ.م')),
                  ],
                  onChanged: (v) {
                    if (v != null) setLocal(() => def = v);
                  },
                ),
                TextField(
                  controller: overdueCtrl,
                  decoration: const InputDecoration(
                    labelText: 'أيام الأوفرديو لهذا البند',
                    helperText: 'بعد كم يوم متتالي كمشكلة يُعلَّم Overdue',
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
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
    final idx = int.tryParse(indexCtrl.text.trim()) ?? 1;
    overdueDays = int.tryParse(overdueCtrl.text.trim()) ?? 3;
    await ref.read(catalogRepositoryProvider).upsertTemplateItem(
          templateId: selected!.id,
          item: CatalogItem(
            id: existing?.id,
            itemIndex: idx,
            defaultAnswer: def,
            descriptionEn: en.text.trim(),
            descriptionAr: ar.text.trim().isEmpty ? null : ar.text.trim(),
            sortOrder: idx,
            overdueAfterDays: overdueDays.clamp(0, 365),
          ),
        );
    await _selectTemplate(selected!.id);
  }

  Future<void> _editSiteExtra([CatalogItem? existing]) async {
    final site = selectedSite;
    if (site == null || !canEditSites) return;
    final en = TextEditingController(text: existing?.descriptionEn ?? '');
    final ar = TextEditingController(text: existing?.descriptionAr ?? '');
    var def = existing?.defaultAnswer ?? 'Y';
    var overdueDays = existing?.overdueAfterDays ?? 3;
    final indexCtrl = TextEditingController(
      text:
          '${existing?.itemIndex ?? (900 + siteExtras.length + 1)}',
    );
    final overdueCtrl = TextEditingController(text: '$overdueDays');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(existing == null ? 'بند خاص بالموقع' : 'تعديل بند الموقع'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: indexCtrl,
                  decoration: const InputDecoration(labelText: 'رقم البند'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: en,
                  decoration:
                      const InputDecoration(labelText: 'Description EN'),
                  maxLines: 2,
                ),
                TextField(
                  controller: ar,
                  decoration: const InputDecoration(labelText: 'الوصف عربي'),
                  maxLines: 2,
                ),
                DropdownButtonFormField<String>(
                  initialValue: def,
                  decoration: const InputDecoration(
                    labelText: 'الجواب الافتراضي',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Y', child: Text('Yes / نعم')),
                    DropdownMenuItem(value: 'N', child: Text('No / لا')),
                    DropdownMenuItem(value: 'NA', child: Text('NA / غ.م')),
                  ],
                  onChanged: (v) {
                    if (v != null) setLocal(() => def = v);
                  },
                ),
                TextField(
                  controller: overdueCtrl,
                  decoration: const InputDecoration(
                    labelText: 'أيام الأوفرديو لهذا البند',
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
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
    final idx = int.tryParse(indexCtrl.text.trim()) ?? 901;
    overdueDays = int.tryParse(overdueCtrl.text.trim()) ?? 3;
    await ref.read(catalogRepositoryProvider).upsertSiteExtraItem(
          siteId: site.id,
          item: CatalogItem(
            id: existing?.id,
            itemIndex: idx,
            defaultAnswer: def,
            descriptionEn: en.text.trim(),
            descriptionAr: ar.text.trim().isEmpty ? null : ar.text.trim(),
            sortOrder: idx,
            isCustom: true,
            overdueAfterDays: overdueDays.clamp(0, 365),
          ),
        );
    await _loadSiteExtras();
  }

  Future<void> _createTemplate() async {
    if (!canEditTemplates) return;
    final code = TextEditingController();
    final en = TextEditingController();
    final ar = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('قالب جديد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: code,
              decoration: const InputDecoration(
                labelText: 'Code',
                hintText: 'B8_CUSTOM',
              ),
            ),
            TextField(
              controller: en,
              decoration: const InputDecoration(labelText: 'Name EN'),
            ),
            TextField(
              controller: ar,
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
            child: const Text('إنشاء'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final t = await ref.read(catalogRepositoryProvider).createTemplate(
          code: code.text.trim().toUpperCase(),
          nameEn: en.text.trim(),
          nameAr: ar.text.trim(),
        );
    await _load();
    await _selectTemplate(t.id);
  }

  Widget _templatesPane() {
    return Row(
      children: [
        SizedBox(
          width: 260,
          child: Column(
            children: [
              ListTile(
                title: const Text(
                  'القوالب',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                trailing: canEditTemplates
                    ? IconButton(
                        onPressed: _createTemplate,
                        icon: const Icon(Icons.add),
                      )
                    : null,
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final t in templates)
                      ListTile(
                        selected: selected?.id == t.id,
                        title: Text(t.code),
                        subtitle: Text(t.nameAr),
                        onTap: () => _selectTemplate(t.id),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: selected == null
              ? const Center(child: Text('اختر قالباً'))
              : Column(
                  children: [
                    ListTile(
                      title: Text('${selected!.code} — ${selected!.nameAr}'),
                      subtitle: Text('${items.length} بند'),
                      trailing: canEditTemplates
                          ? IconButton(
                              onPressed: () => _editItem(),
                              icon: const Icon(Icons.add),
                            )
                          : null,
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final item = items[i];
                          return ListTile(
                            leading: CircleAvatar(
                              radius: 14,
                              child: Text(
                                '${item.itemIndex}',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                            title: Text(item.descriptionEn),
                            subtitle: Text(
                              'افتراضي: ${item.defaultAnswer} • أوفرديو: ${item.overdueAfterDays}ي'
                              '${(item.descriptionAr ?? '').isNotEmpty ? '\n${item.descriptionAr}' : ''}',
                            ),
                            isThreeLine:
                                (item.descriptionAr ?? '').isNotEmpty,
                            trailing: canEditTemplates
                                ? IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () => _editItem(item),
                                  )
                                : null,
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _sitesPane() {
    final codes = templates.map((t) => t.code).toList();
    return Row(
      children: [
        SizedBox(
          width: 300,
          child: ListView(
            children: [
              const ListTile(
                title: Text(
                  'قوائم الفحص حسب الموقع',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              for (final g in campusGroups) ...[
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.account_balance_outlined, size: 18),
                  title: Text(
                    g.titleFor('ar'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                for (final s in g.checklists)
                  ListTile(
                    contentPadding: const EdgeInsets.only(left: 28, right: 8),
                    selected: selectedSite?.id == s.id,
                    title: Text(s.buildingCode),
                    subtitle: Text(s.nameAr, maxLines: 1),
                    onTap: () async {
                      setState(() => selectedSite = s);
                      await _loadSiteExtras();
                    },
                  ),
              ],
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: selectedSite == null
              ? const Center(child: Text('اختر قائمة فحص'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      '${selectedSite!.buildingCode} — ${selectedSite!.nameAr}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: codes.contains(selectedSite!.checklistType)
                          ? selectedSite!.checklistType
                          : (codes.isNotEmpty ? codes.first : null),
                      decoration: const InputDecoration(
                        labelText: 'ربط قالب الفحص',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final c in codes)
                          DropdownMenuItem(value: c, child: Text(c)),
                      ],
                      onChanged: canEditSites
                          ? (v) {
                              if (v != null) _bindTemplateToSite(v);
                            }
                          : null,
                    ),
                    const SizedBox(height: 24),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'بنود إضافية خاصة بقائمة الفحص',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      trailing: canEditSites
                          ? IconButton(
                              onPressed: () => _editSiteExtra(),
                              icon: const Icon(Icons.add),
                            )
                          : null,
                    ),
                    if (siteExtras.isEmpty)
                      const Text('لا توجد بنود إضافية'),
                    for (final item in siteExtras)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(item.descriptionEn),
                        subtitle: Text(
                          '#${item.itemIndex} • افتراضي: ${item.defaultAnswer}',
                        ),
                        trailing: canEditSites
                            ? IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _editSiteExtra(item),
                              )
                            : null,
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        if (message != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(message!, style: const TextStyle(color: Colors.red)),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('القوالب'), icon: Icon(Icons.list_alt)),
              ButtonSegment(
                value: 1,
                label: Text('ربط المواقع'),
                icon: Icon(Icons.link),
              ),
            ],
            selected: {mode},
            onSelectionChanged: (s) => setState(() => mode = s.first),
          ),
        ),
        Expanded(child: mode == 0 ? _templatesPane() : _sitesPane()),
      ],
    );
  }
}
