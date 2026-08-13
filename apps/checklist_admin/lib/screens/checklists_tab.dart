import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'form_theme_picker_dialog.dart';

/// Default templates + site effective lists (template inherited + custom extras).
class ChecklistsTab extends ConsumerStatefulWidget {
  const ChecklistsTab({
    super.key,
    required this.profile,
    required this.language,
  });

  final Profile profile;
  final String language;

  @override
  ConsumerState<ChecklistsTab> createState() => _ChecklistsTabState();
}

class _ChecklistsTabState extends ConsumerState<ChecklistsTab> {
  /// 0 = default templates, 1 = site effective / modified lists.
  int mode = 0;
  List<ChecklistTemplate> templates = [];
  ChecklistTemplate? selected;
  List<CatalogItem> items = [];
  List<ChecklistSite> sites = [];
  List<CampusChecklistGroup> campusGroups = [];
  ChecklistSite? selectedSite;
  List<CatalogItem> siteExtras = [];
  List<CatalogItem> effectiveItems = [];
  bool loading = true;
  String? message;

  bool get canEditTemplates => widget.profile.isPlatformOwner;

  bool get canEditSelectedVersion =>
      canEditTemplates && selected?.isDraftVersion == true;

  bool get canEditSites => widget.profile.canManageLocalSites;

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
      final list = await ref
          .read(catalogRepositoryProvider)
          .listTemplates(activeOnly: false);
      final groups = await ref
          .read(siteRepositoryProvider)
          .listAccessibleCampusGroups(profile: widget.profile);
      final siteList = [for (final g in groups) ...g.checklists];
      final currentSiteId = selectedSite?.id;
      setState(() {
        templates = list;
        campusGroups = groups;
        sites = siteList;
        selectedSite = siteList
            .where((site) => site.id == currentSiteId)
            .firstOrNull;
        selectedSite ??= siteList.firstOrNull;
      });
      if (selected != null) {
        await _selectTemplate(selected!.id);
      } else if (list.isNotEmpty) {
        await _selectTemplate(list.first.id);
      }
      if (selectedSite != null) await _loadSiteDetail();
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

  Future<void> _editSelectedTemplateTheme() async {
    final template = selected;
    if (template == null || !canEditSelectedVersion) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => FormThemePickerDialog(
        language: widget.language,
        scopeName: _t(
          '${template.code} list type',
          'نوع القائمة ${template.code}',
        ),
        currentTheme: template.formTheme,
        currentAccent: template.formThemeAccent,
        allowInherit: true,
        inheritedTheme: FormPaperTheme.classicGold,
        onSave: (theme, accent) async {
          await ref
              .read(catalogRepositoryProvider)
              .updateTemplateFormTheme(
                id: template.id,
                formTheme: theme,
                formThemeAccent: accent,
              );
        },
      ),
    );
    if (ok == true) {
      await _selectTemplate(template.id);
      if (!mounted || selected == null) return;
      setState(() {
        templates = [
          for (final item in templates)
            if (item.id == selected!.id) selected! else item,
        ];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'Theme saved. Viewer and Entry will use it after refresh.',
              'تم حفظ الثيم، وسيظهر في العرض والإدخال بعد التحديث.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _loadSiteDetail() async {
    final site = selectedSite;
    if (site == null) return;
    final catalog = ref.read(catalogRepositoryProvider);
    final extras = await catalog.listSiteExtraItems(site.id);
    final effective = await catalog.listEffectiveCatalogForSite(
      checklistType: site.checklistType,
      siteId: site.id,
    );
    if (mounted) {
      setState(() {
        siteExtras = extras;
        effectiveItems = effective;
      });
    }
  }

  Future<void> _bindTemplateToSite(String code) async {
    final site = selectedSite;
    if (site == null || !canEditSites) return;
    await ref
        .read(siteRepositoryProvider)
        .updateChecklistType(site: site, checklistType: code);
    final refreshed = await ref
        .read(siteRepositoryProvider)
        .listAccessibleSites(profile: widget.profile);
    final match = refreshed.where((s) => s.id == site.id);
    setState(() {
      sites = refreshed;
      if (match.isNotEmpty) selectedSite = match.first;
    });
    await _loadSiteDetail();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'Bound ${site.buildingCode} → $code',
              'تم ربط ${site.buildingCode} بـ $code',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _editItem([CatalogItem? existing]) async {
    if (selected == null || !canEditSelectedVersion) return;
    final en = TextEditingController(text: existing?.descriptionEn ?? '');
    final arCtrl = TextEditingController(text: existing?.descriptionAr ?? '');
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
          title: Text(
            existing == null
                ? _t('New template item', 'بند جديد في القالب')
                : _t('Edit template item', 'تعديل بند القالب'),
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: indexCtrl,
                  decoration: InputDecoration(
                    labelText: _t('Item #', 'رقم البند'),
                  ),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: en,
                  decoration: InputDecoration(
                    labelText: _t('Description EN', 'الوصف إنجليزي'),
                  ),
                  maxLines: 2,
                ),
                TextField(
                  controller: arCtrl,
                  decoration: InputDecoration(
                    labelText: _t('Description AR', 'الوصف عربي'),
                  ),
                  maxLines: 2,
                ),
                DropdownButtonFormField<String>(
                  initialValue: def,
                  decoration: InputDecoration(
                    labelText: _t(
                      'Ideal answer (healthy state)',
                      'الجواب المثالي (الحالة السليمة)',
                    ),
                    helperText: _t(
                      'Opposite = problem; closing needs a fix photo in Entry/Viewer.',
                      'العكس = مشكلة؛ الإغلاق يتطلب صورة إصلاح في الإدخال/العرض.',
                    ),
                  ),
                  items: [
                    DropdownMenuItem(value: 'Y', child: Text(_t('Yes', 'نعم'))),
                    DropdownMenuItem(value: 'N', child: Text(_t('No', 'لا'))),
                    DropdownMenuItem(
                      value: 'NA',
                      child: Text(_t('N/A', 'غ.م')),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setLocal(() => def = v);
                  },
                ),
                TextField(
                  controller: overdueCtrl,
                  decoration: InputDecoration(
                    labelText: _t(
                      'Overdue after (days)',
                      'أيام الأوفر ديو لهذا البند',
                    ),
                    helperText: _t(
                      'Consecutive problem days before Overdue in Viewer ops. 0 = disabled.',
                      'أيام مشكلة متتالية قبل متأخر في متابعة العرض. 0 = معطّل.',
                    ),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
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
    final idx = int.tryParse(indexCtrl.text.trim()) ?? 1;
    overdueDays = int.tryParse(overdueCtrl.text.trim()) ?? 3;
    await ref
        .read(catalogRepositoryProvider)
        .upsertTemplateItem(
          templateId: selected!.id,
          item: CatalogItem(
            id: existing?.id,
            itemIndex: idx,
            defaultAnswer: def,
            descriptionEn: en.text.trim(),
            descriptionAr: arCtrl.text.trim().isEmpty
                ? null
                : arCtrl.text.trim(),
            localizedDescriptions: existing?.localizedDescriptions ?? const {},
            sortOrder: idx,
            overdueAfterDays: overdueDays.clamp(0, 365),
          ),
        );
    await _selectTemplate(selected!.id);
    if (selectedSite != null) await _loadSiteDetail();
  }

  Future<void> _deleteTemplateItem(CatalogItem item) async {
    if (!canEditSelectedVersion || item.id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('Delete item', 'حذف بند')),
        content: Text(
          _t(
            'Remove item #${item.itemIndex} from this default list?',
            'حذف البند #${item.itemIndex} من القائمة الافتراضية؟',
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
            child: Text(_t('Delete', 'حذف')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(catalogRepositoryProvider).deleteTemplateItem(item.id!);
    await _selectTemplate(selected!.id);
    if (selectedSite != null) await _loadSiteDetail();
  }

  Future<void> _editSiteExtra([CatalogItem? existing]) async {
    final site = selectedSite;
    if (site == null || !canEditSites) return;
    final en = TextEditingController(text: existing?.descriptionEn ?? '');
    final arCtrl = TextEditingController(text: existing?.descriptionAr ?? '');
    var def = existing?.defaultAnswer ?? 'Y';
    var overdueDays = existing?.overdueAfterDays ?? 3;
    final indexCtrl = TextEditingController(
      text: '${existing?.itemIndex ?? (900 + siteExtras.length + 1)}',
    );
    final overdueCtrl = TextEditingController(text: '$overdueDays');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(
            existing == null
                ? _t('Site-specific item', 'بند خاص بقائمة الفحص')
                : _t('Edit site item', 'تعديل بند الموقع'),
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: indexCtrl,
                  decoration: InputDecoration(
                    labelText: _t('Item #', 'رقم البند'),
                  ),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: en,
                  decoration: InputDecoration(
                    labelText: _t('Description EN', 'الوصف إنجليزي'),
                  ),
                  maxLines: 2,
                ),
                TextField(
                  controller: arCtrl,
                  decoration: InputDecoration(
                    labelText: _t('Description AR', 'الوصف عربي'),
                  ),
                  maxLines: 2,
                ),
                DropdownButtonFormField<String>(
                  initialValue: def,
                  decoration: InputDecoration(
                    labelText: _t('Ideal answer', 'الجواب المثالي'),
                  ),
                  items: [
                    DropdownMenuItem(value: 'Y', child: Text(_t('Yes', 'نعم'))),
                    DropdownMenuItem(value: 'N', child: Text(_t('No', 'لا'))),
                    DropdownMenuItem(
                      value: 'NA',
                      child: Text(_t('N/A', 'غ.م')),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setLocal(() => def = v);
                  },
                ),
                TextField(
                  controller: overdueCtrl,
                  decoration: InputDecoration(
                    labelText: _t('Overdue after (days)', 'أيام الأوفر ديو'),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
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
    final idx = int.tryParse(indexCtrl.text.trim()) ?? 901;
    overdueDays = int.tryParse(overdueCtrl.text.trim()) ?? 3;
    await ref
        .read(catalogRepositoryProvider)
        .upsertSiteExtraItem(
          siteId: site.id,
          item: CatalogItem(
            id: existing?.id,
            itemIndex: idx,
            defaultAnswer: def,
            descriptionEn: en.text.trim(),
            descriptionAr: arCtrl.text.trim().isEmpty
                ? null
                : arCtrl.text.trim(),
            localizedDescriptions: existing?.localizedDescriptions ?? const {},
            sortOrder: idx,
            isCustom: true,
            overdueAfterDays: overdueDays.clamp(0, 365),
          ),
        );
    await _loadSiteDetail();
  }

  Future<void> _deleteSiteExtra(CatalogItem item) async {
    if (!canEditSites || item.id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('Delete custom item', 'حذف بند مخصّص')),
        content: Text(
          _t(
            'Remove custom item #${item.itemIndex}?',
            'حذف البند المخصّص #${item.itemIndex}؟',
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
            child: Text(_t('Delete', 'حذف')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(catalogRepositoryProvider).deleteSiteExtraItem(item.id!);
    await _loadSiteDetail();
  }

  Future<void> _createTemplate() async {
    if (!canEditTemplates) return;
    final code = TextEditingController();
    final en = TextEditingController();
    final arCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('New default list', 'قائمة افتراضية جديدة')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: code,
              decoration: InputDecoration(
                labelText: _t('Code', 'الرمز'),
                hintText: 'B8_CUSTOM',
              ),
            ),
            TextField(
              controller: en,
              decoration: InputDecoration(
                labelText: _t('Name EN', 'الاسم إنجليزي'),
              ),
            ),
            TextField(
              controller: arCtrl,
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
            child: Text(_t('Create', 'إنشاء')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final t = await ref
        .read(catalogRepositoryProvider)
        .createTemplate(
          code: code.text.trim().toUpperCase(),
          nameEn: en.text.trim(),
          nameAr: arCtrl.text.trim(),
        );
    await _load();
    await _selectTemplate(t.id);
  }

  Future<String?> _askVersionReason(String title) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: _t('Required reason', 'السبب الإلزامي'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_t('Cancel', 'إلغاء')),
          ),
          FilledButton(
            onPressed: () {
              final reason = controller.text.trim();
              if (reason.isNotEmpty) Navigator.pop(context, reason);
            },
            child: Text(_t('Continue', 'متابعة')),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _cloneSelectedVersion() async {
    final template = selected;
    if (template == null || !canEditTemplates) return;
    final reason = await _askVersionReason(
      _t('Create a new checklist version', 'إنشاء إصدار جديد للقائمة'),
    );
    if (reason == null) return;
    try {
      final id = await ref
          .read(catalogRepositoryProvider)
          .cloneTemplateVersion(sourceTemplateId: template.id, reason: reason);
      await _load();
      await _selectTemplate(id);
    } catch (exception) {
      if (mounted) setState(() => message = '$exception');
    }
  }

  Future<void> _publishSelectedVersion() async {
    final template = selected;
    if (template == null || !canEditSelectedVersion) return;
    final reason = await _askVersionReason(
      _t('Publish checklist version', 'نشر إصدار القائمة'),
    );
    if (reason == null) return;
    try {
      await ref
          .read(catalogRepositoryProvider)
          .publishTemplateVersion(templateId: template.id, reason: reason);
      await _load();
    } catch (exception) {
      if (mounted) setState(() => message = '$exception');
    }
  }

  Widget _sourceChip(bool custom) {
    final color = custom ? const Color(0xFFEA580C) : const Color(0xFF2563EB);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        custom ? _t('Custom', 'مخصّص') : _t('Default', 'افتراضي'),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _itemTile({
    required CatalogItem item,
    required bool editable,
    VoidCallback? onEdit,
    VoidCallback? onDelete,
    bool showSource = false,
  }) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final desc = ar && (item.descriptionAr ?? '').isNotEmpty
        ? item.descriptionAr!
        : item.descriptionEn;
    final secondary = ar && desc == item.descriptionAr
        ? item.descriptionEn
        : (item.descriptionAr ?? '');
    return ListTile(
      leading: CircleAvatar(
        radius: 15,
        backgroundColor: ChecklistChrome.accentSoft,
        child: Text(
          '${item.itemIndex}',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        ),
      ),
      title: Text(desc, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        [
          _t(
            'Ideal ${item.defaultAnswer} · Overdue ${item.overdueAfterDays}d',
            'مثالي ${item.defaultAnswer} · أوفر ديو ${item.overdueAfterDays}ي',
          ),
          if (showSource && compact)
            item.isCustom
                ? _t('Source: site custom item', 'المصدر: بند مخصّص للموقع')
                : _t('Source: default list', 'المصدر: القائمة الافتراضية'),
          if (secondary.isNotEmpty) secondary,
        ].join('\n'),
      ),
      isThreeLine: secondary.isNotEmpty || (showSource && compact),
      trailing: compact && editable
          ? PopupMenuButton<String>(
              tooltip: _t('Item actions', 'إجراءات البند'),
              onSelected: (value) {
                if (value == 'edit') onEdit?.call();
                if (value == 'delete') onDelete?.call();
              },
              itemBuilder: (_) => [
                if (onEdit != null)
                  PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      leading: const Icon(Icons.edit_outlined),
                      title: Text(_t('Edit', 'تعديل')),
                    ),
                  ),
                if (onDelete != null)
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: const Icon(
                        Icons.delete_outline,
                        color: Colors.red,
                      ),
                      title: Text(_t('Delete', 'حذف')),
                    ),
                  ),
              ],
            )
          : (!editable && (!showSource || compact))
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showSource) ...[
                  _sourceChip(item.isCustom),
                  const SizedBox(width: 4),
                ],
                if (editable && onEdit != null)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: onEdit,
                  ),
                if (editable && onDelete != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: onDelete,
                  ),
              ],
            ),
    );
  }

  Widget _compactTemplatePicker() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: selected?.id,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: _t('Default list', 'القائمة الافتراضية'),
                prefixIcon: const Icon(Icons.list_alt_outlined),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final t in templates)
                  DropdownMenuItem(
                    value: t.id,
                    child: Text(
                      '${t.familyCode} · v${t.versionNumber} · ${t.lifecycleStatus} — ${t.nameFor(widget.language)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (id) {
                if (id != null) _selectTemplate(id);
              },
            ),
          ),
          if (canEditTemplates) ...[
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: _t('New list', 'قائمة جديدة'),
              onPressed: _createTemplate,
              icon: const Icon(Icons.add),
            ),
          ],
        ],
      ),
    );
  }

  String _sitePickerLabel(ChecklistSite site) {
    final group = campusGroups
        .where((g) => g.checklists.any((s) => s.id == site.id))
        .firstOrNull;
    final parent = group?.titleFor(widget.language);
    return parent == null || parent.isEmpty
        ? '${site.buildingCode} — ${site.nameFor(widget.language)}'
        : '$parent › ${site.buildingCode}';
  }

  Widget _compactSitePicker() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: DropdownButtonFormField<String>(
        initialValue: selectedSite?.id,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: _t('Checklist unit', 'وحدة قائمة الفحص'),
          prefixIcon: const Icon(Icons.account_tree_outlined),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: [
          for (final site in sites)
            DropdownMenuItem(
              value: site.id,
              child: Text(
                _sitePickerLabel(site),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (id) async {
          final match = sites.where((site) => site.id == id).firstOrNull;
          if (match == null) return;
          setState(() => selectedSite = match);
          await _loadSiteDetail();
        },
      ),
    );
  }

  Widget _templatesPane() {
    final narrow = MediaQuery.sizeOf(context).width < 720;
    final list = Column(
      children: [
        ListTile(
          title: Text(
            _t('Default lists', 'القوائم الافتراضية'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            _t(
              'Shared templates used by Entry & Viewer',
              'قوالب مشتركة يستخدمها الإدخال والعرض',
            ),
          ),
          trailing: canEditTemplates
              ? IconButton(
                  tooltip: _t('New list', 'قائمة جديدة'),
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
                  leading: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: t.paperTheme.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: t.paperTheme.border),
                    ),
                    child: Icon(
                      Icons.list_alt,
                      size: 16,
                      color: t.paperTheme.accentText,
                    ),
                  ),
                  title: Text(
                    '${t.familyCode.isEmpty ? t.code : t.familyCode} · v${t.versionNumber}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${ar ? t.nameAr : t.nameEn} · ${t.lifecycleStatus}',
                  ),
                  onTap: () => _selectTemplate(t.id),
                ),
            ],
          ),
        ),
      ],
    );

    final detail = selected == null
        ? Center(
            child: Text(_t('Select a default list', 'اختر قائمة افتراضية')),
          )
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
                child: ChecklistBrandCard(
                  borderColor: selected!.paperTheme.accent.withValues(
                    alpha: 0.55,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: selected!.paperTheme.accent,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selected!.paperTheme.border,
                              ),
                            ),
                            child: Icon(
                              Icons.list_alt_rounded,
                              color: selected!.paperTheme.accentText,
                              size: 19,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${selected!.familyCode} · v${selected!.versionNumber} — ${selected!.nameFor(widget.language)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _t(
                          '${items.length} items · ${sites.where((s) => s.checklistType == selected!.code).length} linked units',
                          '${items.length} بند · ${sites.where((s) => s.checklistType == selected!.code).length} وحدات مرتبطة',
                        ),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: canEditSelectedVersion
                                ? _editSelectedTemplateTheme
                                : null,
                            icon: Icon(
                              Icons.palette_outlined,
                              color: selected!.paperTheme.accent,
                            ),
                            label: Text(
                              selected!.formTheme == 'inherit'
                                  ? _t('Inherited theme', 'ثيم موروث')
                                  : selected!.paperTheme.key.labelFor(
                                      widget.language,
                                    ),
                            ),
                          ),
                          if (canEditTemplates)
                            FilledButton.tonalIcon(
                              onPressed: canEditSelectedVersion
                                  ? () => _editItem()
                                  : _cloneSelectedVersion,
                              icon: const Icon(Icons.add),
                              label: Text(
                                canEditSelectedVersion
                                    ? _t('Add item', 'إضافة بند')
                                    : _t(
                                        'Create new version',
                                        'إنشاء إصدار جديد',
                                      ),
                              ),
                            ),
                          if (canEditSelectedVersion)
                            FilledButton.icon(
                              onPressed: _publishSelectedVersion,
                              icon: const Icon(Icons.publish_outlined),
                              label: Text(_t('Publish version', 'نشر الإصدار')),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.playlist_add_rounded,
                                size: 44,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _t(
                                  'This list has no items yet.',
                                  'لا تحتوي هذه القائمة على بنود بعد.',
                                ),
                                textAlign: TextAlign.center,
                              ),
                              if (canEditSelectedVersion) ...[
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: () => _editItem(),
                                  icon: const Icon(Icons.add),
                                  label: Text(
                                    _t('Add first item', 'إضافة أول بند'),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final item = items[i];
                          return _itemTile(
                            item: item,
                            editable: canEditSelectedVersion,
                            onEdit: () => _editItem(item),
                            onDelete: item.id == null
                                ? null
                                : () => _deleteTemplateItem(item),
                          );
                        },
                      ),
              ),
            ],
          );

    if (narrow) {
      return Column(
        children: [
          _compactTemplatePicker(),
          const Divider(height: 1),
          Expanded(child: detail),
        ],
      );
    }
    return Row(
      children: [
        SizedBox(width: 280, child: list),
        const VerticalDivider(width: 1),
        Expanded(child: detail),
      ],
    );
  }

  Widget _sitesPane() {
    final codes = templates
        .where((template) => template.isPublishedVersion)
        .map((template) => template.code)
        .toList();
    final narrow = MediaQuery.sizeOf(context).width < 720;
    final picker = ListView(
      children: [
        ListTile(
          title: Text(
            _t('Checklist units', 'قوائم الفحص بالمواقع'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            _t(
              'Bind template + site-only extras',
              'ربط القالب + بنود خاصة بالموقع',
            ),
          ),
        ),
        for (final g in campusGroups) ...[
          ListTile(
            dense: true,
            leading: const Icon(Icons.account_balance_outlined, size: 18),
            title: Text(
              g.titleFor(widget.language),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
          for (final s in g.checklists)
            ListTile(
              contentPadding: const EdgeInsetsDirectional.only(
                start: 28,
                end: 8,
              ),
              selected: selectedSite?.id == s.id,
              title: Text(
                s.buildingCode,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(s.nameFor(widget.language), maxLines: 1),
              trailing: Text(
                s.checklistType,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              onTap: () async {
                setState(() => selectedSite = s);
                await _loadSiteDetail();
              },
            ),
        ],
      ],
    );

    final detail = selectedSite == null
        ? Center(child: Text(_t('Select a checklist unit', 'اختر قائمة فحص')))
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${selectedSite!.buildingCode} — ${selectedSite!.nameFor(widget.language)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _t(
                  'Effective list = default template items + custom site items (same merge Entry/Viewer use).',
                  'القائمة الفعلية = بنود القالب الافتراضي + بنود مخصّصة (نفس دمج الإدخال/العرض).',
                ),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: codes.contains(selectedSite!.checklistType)
                    ? selectedSite!.checklistType
                    : (codes.isNotEmpty ? codes.first : null),
                decoration: InputDecoration(
                  labelText: _t(
                    'Bound default list (template)',
                    'ربط القائمة الافتراضية (القالب)',
                  ),
                  border: const OutlineInputBorder(),
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
              const SizedBox(height: 18),
              ChecklistBrandCard(
                borderColor: const Color(0xFF2563EB).withValues(alpha: 0.3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _t(
                              'Effective checklist (${effectiveItems.length})',
                              'القائمة الفعلية (${effectiveItems.length})',
                            ),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        _sourceChip(false),
                        const SizedBox(width: 6),
                        _sourceChip(true),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (effectiveItems.isEmpty)
                      Text(
                        _t('No items resolved', 'لا بنود محلولة'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      )
                    else
                      for (final item in effectiveItems)
                        _itemTile(
                          item: item,
                          showSource: true,
                          editable: canEditSites && item.isCustom,
                          onEdit: item.isCustom
                              ? () {
                                  final match = siteExtras
                                      .where((e) => e.id == item.id)
                                      .toList();
                                  _editSiteExtra(
                                    match.isNotEmpty ? match.first : item,
                                  );
                                }
                              : null,
                          onDelete: item.isCustom && item.id != null
                              ? () => _deleteSiteExtra(item)
                              : null,
                        ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _t('Custom site items only', 'البنود المخصّصة فقط'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  _t(
                    'Extra questions for this unit; open problems carry into new lists until a fix photo is added.',
                    'أسئلة إضافية لهذه الوحدة؛ المشاكل المفتوحة تُنقل للقوائم الجديدة حتى تُرفق صورة إصلاح.',
                  ),
                ),
                trailing: canEditSites
                    ? IconButton(
                        onPressed: () => _editSiteExtra(),
                        icon: const Icon(Icons.add),
                      )
                    : null,
              ),
              if (siteExtras.isEmpty)
                Text(
                  _t('No custom items', 'لا بنود مخصّصة'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              for (final item in siteExtras)
                _itemTile(
                  item: item,
                  showSource: true,
                  editable: canEditSites,
                  onEdit: () => _editSiteExtra(item),
                  onDelete: item.id == null
                      ? null
                      : () => _deleteSiteExtra(item),
                ),
            ],
          );

    if (narrow) {
      return Column(
        children: [
          _compactSitePicker(),
          const Divider(height: 1),
          Expanded(child: detail),
        ],
      );
    }
    return Row(
      children: [
        SizedBox(width: 300, child: picker),
        const VerticalDivider(width: 1),
        Expanded(child: detail),
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
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: SegmentedButton<int>(
            expandedInsets: EdgeInsets.zero,
            segments: [
              ButtonSegment(
                value: 0,
                label: Text(_t('Default lists', 'القوائم الافتراضية')),
                icon: const Icon(Icons.list_alt),
              ),
              ButtonSegment(
                value: 1,
                label: Text(_t('Site lists', 'قوائم المواقع')),
                icon: const Icon(Icons.account_tree_outlined),
              ),
            ],
            selected: {mode},
            onSelectionChanged: (s) => setState(() => mode = s.first),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              mode == 0
                  ? _t(
                      'Edit shared defaults: ideal answer + overdue SLA used by Entry/Viewer.',
                      'تحرير الافتراضي: الجواب المثالي ومهلة الأوفر ديو المستخدمة في الإدخال/العرض.',
                    )
                  : _t(
                      'Preview what technicians see: inherited defaults + site custom items.',
                      'معاينة ما يراه الفني: بنود موروثة من الافتراضي + بنود مخصّصة للموقع.',
                    ),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(child: mode == 0 ? _templatesPane() : _sitesPane()),
      ],
    );
  }
}
