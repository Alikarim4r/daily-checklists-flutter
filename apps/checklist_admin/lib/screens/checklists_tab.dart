import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/checkadmin_errors.dart';
import '../design/checkadmin_tokens.dart';
import '../design/checkadmin_widgets.dart';

import 'form_theme_picker_dialog.dart';
import 'checklist_library_pane.dart';
import 'checklist_filter_workbench.dart';

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
  /// 0 = online library, 1 = organization templates.
  int mode = 0;
  List<ChecklistTemplate> templates = [];
  List<Organization> organizations = [];
  ChecklistTemplate? selected;
  List<CatalogItem> items = [];
  List<ChecklistSite> sites = [];
  List<CampusChecklistGroup> campusGroups = [];
  ChecklistSite? selectedSite;
  List<CatalogItem> siteExtras = [];
  List<CatalogItem> effectiveItems = [];
  bool loading = true;
  String? message;

  bool get canCreateGlobalTemplates =>
      widget.profile.isPlatformOwner ||
      widget.profile.role == UserRole.superAdmin;

  bool get canManageSelectedTemplate {
    final t = selected;
    if (t == null) return false;
    if (widget.profile.isPlatformOwner) return true;
    return t.organizationId != null &&
        widget.profile.role == UserRole.superAdmin &&
        widget.profile.homeOrganizationId == t.organizationId;
  }

  bool get canEditSelectedVersion =>
      canManageSelectedTemplate && selected?.isDraftVersion == true;

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
      final orgs = widget.profile.isPlatformOwner
          ? await ref.read(organizationRepositoryProvider).listOrganizations()
          : const <Organization>[];
      final groups = await ref
          .read(siteRepositoryProvider)
          .listAccessibleCampusGroups(profile: widget.profile);
      final siteList = [for (final g in groups) ...g.checklists];
      final currentSiteId = selectedSite?.id;
      final visibleTemplates = widget.profile.isPlatformOwner
          ? list.where((template) => template.organizationId != null).toList()
          : list
                .where(
                  (template) =>
                      template.organizationId ==
                      widget.profile.homeOrganizationId,
                )
                .toList();
      setState(() {
        organizations = orgs;
        templates = visibleTemplates;
        campusGroups = groups;
        sites = siteList;
        selectedSite = siteList
            .where((site) => site.id == currentSiteId)
            .firstOrNull;
        selectedSite ??= siteList.firstOrNull;
      });
      final selectedId = selected?.id;
      if (selectedId != null &&
          visibleTemplates.any((template) => template.id == selectedId)) {
        await _selectTemplate(selectedId);
      } else {
        setState(() {
          selected = null;
          items = [];
        });
      }
      if (selectedSite != null) await _loadSiteDetail();
    } catch (e) {
      setState(() => message = checkAdminUserMessage(e, widget.language));
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
    try {
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
    } catch (e) {
      _showWriteError(e);
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
          scrollable: true,
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
    try {
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
              localizedDescriptions:
                  existing?.localizedDescriptions ?? const {},
              sortOrder: idx,
              overdueAfterDays: overdueDays.clamp(0, 365),
            ),
          );
      await _selectTemplate(selected!.id);
      if (selectedSite != null) await _loadSiteDetail();
    } catch (e) {
      _showWriteError(e);
    }
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
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(_t('Delete', 'حذف')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(catalogRepositoryProvider).deleteTemplateItem(item.id!);
      await _selectTemplate(selected!.id);
      if (selectedSite != null) await _loadSiteDetail();
    } catch (e) {
      _showWriteError(e);
    }
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
          scrollable: true,
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
    try {
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
              localizedDescriptions:
                  existing?.localizedDescriptions ?? const {},
              sortOrder: idx,
              isCustom: true,
              overdueAfterDays: overdueDays.clamp(0, 365),
            ),
          );
      await _loadSiteDetail();
    } catch (e) {
      _showWriteError(e);
    }
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
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(_t('Delete', 'حذف')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(catalogRepositoryProvider).deleteSiteExtraItem(item.id!);
      await _loadSiteDetail();
    } catch (e) {
      _showWriteError(e);
    }
  }

  Future<void> _createTemplate() async {
    if (!canCreateGlobalTemplates) return;

    final en = TextEditingController();
    final arCtrl = TextEditingController();
    String? targetOrganizationId = widget.profile.homeOrganizationId;
    if (widget.profile.isPlatformOwner) {
      targetOrganizationId = organizations.firstOrNull?.id;
    }

    final result = await showDialog<_NewTemplateResult>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          scrollable: true,
          title: Text(_t('New template', 'قالب جديد')),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.profile.isPlatformOwner) ...[
                  DropdownButtonFormField<String>(
                    initialValue: targetOrganizationId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: _t('Company', 'الشركة'),
                      prefixIcon: const Icon(Icons.business_outlined),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      for (final organization in organizations)
                        DropdownMenuItem(
                          value: organization.id,
                          child: Text(
                            organization.nameFor(widget.language),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      setLocal(() => targetOrganizationId = value);
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: en,
                  decoration: InputDecoration(
                    labelText: _t('Template name EN', 'اسم القالب بالإنجليزية'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: arCtrl,
                  decoration: InputDecoration(
                    labelText: _t('Template name AR', 'اسم القالب بالعربية'),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_t('Cancel', 'إلغاء')),
            ),
            FilledButton(
              onPressed: () {
                final nameEn = en.text.trim();
                final organizationId = targetOrganizationId;
                if (nameEn.length < 2 || organizationId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        _t(
                          'Choose a company and enter a template name.',
                          'اختر الشركة وأدخل اسم القالب.',
                        ),
                      ),
                    ),
                  );
                  return;
                }
                Navigator.pop(
                  context,
                  _NewTemplateResult(
                    organizationId: organizationId,
                    nameEn: nameEn,
                    nameAr: arCtrl.text.trim(),
                  ),
                );
              },
              child: Text(_t('Create', 'إنشاء')),
            ),
          ],
        ),
      ),
    );

    en.dispose();
    arCtrl.dispose();
    if (result == null) return;

    try {
      final catalog = ref.read(catalogRepositoryProvider);
      final template = widget.profile.isPlatformOwner
          ? await catalog.createOrganizationTemplateFor(
              organizationId: result.organizationId,
              nameEn: result.nameEn,
              nameAr: result.nameAr,
            )
          : await catalog.createOrganizationCustomTemplate(
              nameEn: result.nameEn,
              nameAr: result.nameAr,
            );
      await _load();
      await _selectTemplate(template.id);
    } catch (error) {
      _showWriteError(error);
    }
  }

  void _showWriteError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(checkAdminUserMessage(error, widget.language))),
    );
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
    if (template == null || !canManageSelectedTemplate) return;
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
      if (mounted) {
        setState(
          () => message = checkAdminUserMessage(exception, widget.language),
        );
      }
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
      if (mounted) {
        setState(
          () => message = checkAdminUserMessage(exception, widget.language),
        );
      }
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
      leading: CaCodeBadge(
        code: '${item.itemIndex}',
        width: 36,
        tone: CaTone.accent,
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
                      leading: Icon(
                        Icons.delete_outline,
                        color: Theme.of(context).colorScheme.error,
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
                    tooltip: _t('Edit', 'تعديل'),
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: onEdit,
                  ),
                if (editable && onDelete != null)
                  IconButton(
                    tooltip: _t('Delete', 'حذف'),
                    icon: Icon(
                      Icons.delete_outline,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: onDelete,
                  ),
              ],
            ),
    );
  }

  Future<void> _showTemplateSelector() async {
    if (templates.isEmpty) return;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final c = CheckAdminColors.of(sheetContext);
        return FractionallySizedBox(
          heightFactor: .72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _t('Select a default list', 'اختر قائمة افتراضية'),
                        style: Theme.of(sheetContext).textTheme.titleLarge,
                      ),
                    ),
                    if (canCreateGlobalTemplates)
                      TextButton.icon(
                        onPressed: () => Navigator.pop(sheetContext, '__new__'),
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(_t('New list', 'قائمة جديدة')),
                      ),
                  ],
                ),
              ),
              Divider(height: 1, color: c.rule),
              Expanded(
                child: ListView.separated(
                  itemCount: templates.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: c.rule, indent: CaSpace.gutter),
                  itemBuilder: (context, i) {
                    final t = templates[i];
                    final active = t.id == selected?.id;
                    return ListTile(
                      minTileHeight: 56,
                      selected: active,
                      selectedTileColor: c.primarySoft.withValues(alpha: .55),
                      leading: CaCodeBadge(
                        code:
                            '${t.familyCode.isEmpty ? t.code : t.familyCode} · v${t.versionNumber}',
                        width: 82,
                        tone: active ? CaTone.accent : CaTone.neutral,
                      ),
                      title: Text(t.nameFor(widget.language)),
                      subtitle: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: t.isPublishedVersion ? c.good : c.warning,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            t.lifecycleStatus,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      trailing: active
                          ? Icon(Icons.check_rounded, color: c.primaryStrong)
                          : null,
                      onTap: () => Navigator.pop(context, t.id),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || chosen == null) return;
    if (chosen == '__new__') {
      await _createTemplate();
      return;
    }
    await _selectTemplate(chosen);
  }

  Widget _compactTemplatePicker() {
    final template = selected;
    if (template == null) {
      return CaSelectorRow(
        title: _t('Select a default list', 'اختر قائمة افتراضية'),
        subtitle: _t('No list selected', 'لم يتم اختيار قائمة'),
        onTap: templates.isEmpty ? null : _showTemplateSelector,
      );
    }
    final c = CheckAdminColors.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        CaSpace.gutter,
        CaSpace.md,
        CaSpace.gutter,
        0,
      ),
      child: Material(
        color: CheckAdminColors.of(context).surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CaRadius.panel),
        ),
        child: CaSelectorRow(
          title: template.nameFor(widget.language),
          subtitle:
              '${template.familyCode.isEmpty ? template.code : template.familyCode} · v${template.versionNumber}',
          status: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: template.isPublishedVersion ? c.good : c.warning,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                template.lifecycleStatus,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: template.isPublishedVersion ? c.good : c.warning,
                ),
              ),
            ],
          ),
          onTap: _showTemplateSelector,
        ),
      ),
    );
  }

  Future<void> _showSiteSelector() async {
    if (sites.isEmpty) return;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final c = CheckAdminColors.of(sheetContext);
        return FractionallySizedBox(
          heightFactor: .72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 8, 8),
                child: Text(
                  _t('Select a checklist unit', 'اختر وحدة قائمة الفحص'),
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
              ),
              Divider(height: 1, color: c.rule),
              Expanded(
                child: ListView.separated(
                  itemCount: sites.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: c.rule, indent: CaSpace.gutter),
                  itemBuilder: (context, i) {
                    final site = sites[i];
                    final active = site.id == selectedSite?.id;
                    return ListTile(
                      minTileHeight: 56,
                      selected: active,
                      selectedTileColor: c.primarySoft.withValues(alpha: .55),
                      leading: CaCodeBadge(
                        code: site.buildingCode,
                        width: 72,
                        tone: active ? CaTone.accent : CaTone.neutral,
                      ),
                      title: Text(site.nameFor(widget.language)),
                      subtitle: Text(site.checklistType),
                      trailing: active
                          ? Icon(Icons.check_rounded, color: c.primaryStrong)
                          : null,
                      onTap: () => Navigator.pop(context, site.id),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || chosen == null) return;
    final match = sites.where((site) => site.id == chosen).firstOrNull;
    if (match == null) return;
    setState(() => selectedSite = match);
    await _loadSiteDetail();
  }

  Widget _compactSitePicker() {
    final site = selectedSite;
    if (site == null) {
      return CaSelectorRow(
        title: _t('Select a checklist unit', 'اختر وحدة قائمة الفحص'),
        subtitle: _t('No unit selected', 'لم يتم اختيار وحدة'),
        onTap: sites.isEmpty ? null : _showSiteSelector,
      );
    }
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        CaSpace.gutter,
        CaSpace.md,
        CaSpace.gutter,
        0,
      ),
      child: Material(
        color: CheckAdminColors.of(context).surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CaRadius.panel),
        ),
        child: CaSelectorRow(
          title: site.nameFor(widget.language),
          subtitle: '${site.buildingCode} · ${site.checklistType}',
          onTap: _showSiteSelector,
        ),
      ),
    );
  }

  Widget _templateGalleryPane() {
    final c = CheckAdminColors.of(context);
    if (templates.isEmpty) {
      return CaEmptyState(
        icon: Icons.library_books_outlined,
        title: _t('No templates yet', 'لا توجد قوالب بعد'),
        message: _t(
          'Installed library copies and templates created by the company will appear here.',
          'ستظهر هنا القوالب المثبتة من المكتبة والقوالب التي أنشأتها الشركة.',
        ),
        action: canCreateGlobalTemplates
            ? CaCreateButton(
                onPressed: _createTemplate,
                icon: Icons.add,
                label: _t('New template', 'قالب جديد'),
              )
            : null,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CaSectionLabel(
          title: _t('Templates', 'القوالب'),
          count: templates.length,
          trailing: canCreateGlobalTemplates
              ? CaCreateButton(
                  onPressed: _createTemplate,
                  icon: Icons.add,
                  label: _t('New template', 'قالب جديد'),
                  compactLabel: _t('New', 'جديد'),
                )
              : null,
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1100
                  ? 3
                  : constraints.maxWidth >= 720
                  ? 2
                  : 1;
              return GridView.builder(
                padding: EdgeInsetsDirectional.fromSTEB(
                  CaSpace.gutter,
                  0,
                  CaSpace.gutter,
                  MediaQuery.viewPaddingOf(context).bottom + CaSpace.lg,
                ),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  mainAxisExtent: 142,
                ),
                itemCount: templates.length,
                itemBuilder: (context, index) {
                  final template = templates[index];
                  final fromLibrary = template.libraryTemplateId != null;
                  final code = template.familyCode.isEmpty
                      ? template.code
                      : template.familyCode;
                  return Material(
                    color: c.surface,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(CaRadius.panel),
                      side: BorderSide(color: c.rule),
                    ),
                    child: InkWell(
                      onTap: () => _selectTemplate(template.id),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: template.paperTheme.accent,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: template.paperTheme.border,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.list_alt_rounded,
                                    size: 18,
                                    color: template.paperTheme.accentText,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    template.nameFor(widget.language),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  size: 20,
                                ),
                              ],
                            ),
                            const Spacer(),
                            Text(
                              '$code · v${template.versionNumber}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: c.surfaceRaised,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    fromLibrary
                                        ? _t('Library copy', 'من المكتبة')
                                        : _t('Custom', 'مخصص'),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    template.lifecycleStatus,
                                    textAlign: TextAlign.end,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: template.isPublishedVersion
                                              ? c.good
                                              : c.warning,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _closeTemplateDetail() {
    setState(() {
      selected = null;
      items = [];
    });
  }

  Widget _mobileTemplatesPane() {
    final template = selected;
    final c = CheckAdminColors.of(context);
    final linkedCount = template == null
        ? 0
        : sites.where((s) => s.checklistType == template.code).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            CaSpace.gutter,
            4,
            CaSpace.gutter,
            4,
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: _t('Back to templates', 'العودة إلى القوالب'),
                onPressed: _closeTemplateDetail,
                icon: Icon(
                  Directionality.of(context) == TextDirection.rtl
                      ? Icons.arrow_forward_rounded
                      : Icons.arrow_back_rounded,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(child: _compactTemplatePicker()),
            ],
          ),
        ),
        Divider(height: 1, color: c.rule),
        CaSectionLabel(
          title: _t('Items', 'البنود'),
          count: items.length,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (template != null)
                Tooltip(
                  message: template.paperTheme.key.labelFor(widget.language),
                  child: IconButton(
                    onPressed: canEditSelectedVersion
                        ? _editSelectedTemplateTheme
                        : null,
                    icon: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        const Icon(Icons.palette_outlined, size: 21),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: template.paperTheme.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (template != null && canManageSelectedTemplate)
                if (canEditSelectedVersion)
                  IconButton(
                    tooltip: _t('Add item', 'إضافة بند'),
                    onPressed: () => _editItem(),
                    icon: const Icon(Icons.add_rounded),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: _cloneSelectedVersion,
                    icon: const Icon(Icons.add, size: 17),
                    label: Text(_t('New version', 'إصدار جديد')),
                  ),
            ],
          ),
        ),
        if (template != null && canEditSelectedVersion)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              CaSpace.gutter,
              0,
              CaSpace.gutter,
              CaSpace.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _t(
                      '$linkedCount linked units · draft version',
                      '$linkedCount وحدات مرتبطة · إصدار مسودة',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                FilledButton.icon(
                  onPressed: _publishSelectedVersion,
                  icon: const Icon(Icons.publish_outlined, size: 17),
                  label: Text(_t('Publish', 'نشر')),
                ),
              ],
            ),
          ),
        Expanded(
          child: template == null
              ? CaEmptyState(
                  icon: Icons.list_alt_outlined,
                  title: _t('Select a default list', 'اختر قائمة افتراضية'),
                )
              : items.isEmpty
              ? CaEmptyState(
                  icon: Icons.playlist_add_outlined,
                  title: _t('No items yet', 'لا توجد بنود بعد'),
                  message: _t(
                    'Add the first item to this version.',
                    'أضف أول بند إلى هذا الإصدار.',
                  ),
                  action: canEditSelectedVersion
                      ? CaCreateButton(
                          onPressed: () => _editItem(),
                          icon: Icons.add,
                          label: _t('Add item', 'إضافة بند'),
                        )
                      : null,
                )
              : ListView(
                  padding: EdgeInsetsDirectional.fromSTEB(
                    CaSpace.gutter,
                    0,
                    CaSpace.gutter,
                    MediaQuery.viewPaddingOf(context).bottom + CaSpace.lg,
                  ),
                  children: [
                    CaLedger(
                      children: [
                        for (final item in items)
                          _itemTile(
                            item: item,
                            editable: canEditSelectedVersion,
                            onEdit: () => _editItem(item),
                            onDelete: item.id == null
                                ? null
                                : () => _deleteTemplateItem(item),
                          ),
                      ],
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _showBindingSelector() async {
    final site = selectedSite;
    if (site == null || !canEditSites) return;
    final published = templates.where((t) => t.isPublishedVersion).toList();
    if (published.isEmpty) return;
    final code = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) {
        final c = CheckAdminColors.of(sheetContext);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 10),
              child: Text(
                _t('Bind default list', 'ربط القائمة الافتراضية'),
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
            ),
            Divider(height: 1, color: c.rule),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: published.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: c.rule, indent: CaSpace.gutter),
                itemBuilder: (context, i) {
                  final t = published[i];
                  final active = t.code == site.checklistType;
                  return ListTile(
                    minTileHeight: 56,
                    selected: active,
                    selectedTileColor: c.primarySoft.withValues(alpha: .55),
                    leading: CaCodeBadge(
                      code:
                          '${t.familyCode.isEmpty ? t.code : t.familyCode} · v${t.versionNumber}',
                      width: 82,
                      tone: active ? CaTone.accent : CaTone.neutral,
                    ),
                    title: Text(t.nameFor(widget.language)),
                    trailing: active
                        ? Icon(Icons.check_rounded, color: c.primaryStrong)
                        : null,
                    onTap: () => Navigator.pop(context, t.code),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
    if (code != null && mounted) await _bindTemplateToSite(code);
  }

  Widget _mobileSitesPane() {
    final site = selectedSite;
    final c = CheckAdminColors.of(context);
    final bound = site == null
        ? null
        : templates
              .where(
                (t) => t.isPublishedVersion && t.code == site.checklistType,
              )
              .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _compactSitePicker(),
        Divider(height: 1, color: c.rule),
        if (site != null)
          CaSelectorRow(
            title: bound?.nameFor(widget.language) ?? site.checklistType,
            subtitle: bound == null
                ? site.checklistType
                : '${bound.familyCode.isEmpty ? bound.code : bound.familyCode} · v${bound.versionNumber}',
            status: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: c.good,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  _t('Bound', 'مرتبط'),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: c.good),
                ),
              ],
            ),
            onTap: canEditSites ? _showBindingSelector : null,
          ),
        CaSectionLabel(
          title: _t('Effective checklist', 'القائمة الفعلية'),
          count: effectiveItems.length,
          trailing: site != null && canEditSites
              ? IconButton(
                  tooltip: _t('Add site item', 'إضافة بند خاص بالموقع'),
                  onPressed: () => _editSiteExtra(),
                  icon: const Icon(Icons.add_rounded),
                )
              : null,
        ),
        Expanded(
          child: site == null
              ? CaEmptyState(
                  icon: Icons.location_city_outlined,
                  title: _t('Select a checklist unit', 'اختر وحدة قائمة الفحص'),
                )
              : ListView(
                  padding: EdgeInsetsDirectional.fromSTEB(
                    CaSpace.gutter,
                    0,
                    CaSpace.gutter,
                    MediaQuery.viewPaddingOf(context).bottom + CaSpace.lg,
                  ),
                  children: [
                    if (effectiveItems.isEmpty)
                      SizedBox(
                        height: 128,
                        child: CaEmptyState(
                          icon: Icons.playlist_remove_outlined,
                          title: _t('No resolved items', 'لا توجد بنود فعلية'),
                        ),
                      )
                    else
                      CaLedger(
                        children: [
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
                    if (siteExtras.isNotEmpty) ...[
                      CaSectionLabel(
                        title: _t('Site-only items', 'بنود الموقع فقط'),
                        count: siteExtras.length,
                      ),
                      CaLedger(
                        children: [
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
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _templatesPane() {
    if (selected == null) return _templateGalleryPane();
    final narrow = MediaQuery.sizeOf(context).width < 980;
    if (narrow) return _mobileTemplatesPane();

    return LayoutBuilder(
      builder: (context, constraints) {
        final sidebarWidth = (constraints.maxWidth * 0.30)
            .clamp(360.0, 430.0)
            .toDouble();

        final list = Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _t('Templates', 'القوالب'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _t(
                            'Shared lists used by CheckIn & CheckView',
                            'قوائم مشتركة يستخدمها CheckIn وCheckView',
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (canCreateGlobalTemplates)
                    IconButton(
                      tooltip: _t('New list', 'قائمة جديدة'),
                      onPressed: _createTemplate,
                      icon: const Icon(Icons.add_rounded),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: templates.length,
                itemBuilder: (context, index) {
                  final t = templates[index];
                  final code = t.familyCode.isEmpty ? t.code : t.familyCode;
                  final name = t.nameFor(widget.language);
                  return Tooltip(
                    message: '$name\n$code · v${t.versionNumber}',
                    waitDuration: const Duration(milliseconds: 500),
                    child: ListTile(
                      selected: selected?.id == t.id,
                      contentPadding: const EdgeInsetsDirectional.fromSTEB(
                        14,
                        4,
                        10,
                        4,
                      ),
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: t.paperTheme.accent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: t.paperTheme.border),
                        ),
                        child: Icon(
                          Icons.list_alt_rounded,
                          size: 18,
                          color: t.paperTheme.accentText,
                        ),
                      ),
                      title: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        '$code · v${t.versionNumber} · ${t.lifecycleStatus}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                      onTap: () => _selectTemplate(t.id),
                    ),
                  );
                },
              ),
            ),
          ],
        );

        final detail = selected == null
            ? CaEmptyState(
                icon: Icons.library_books_outlined,
                title: _t('Select a template', 'اختر قالباً'),
                message: _t(
                  'Choose a list from the left to review or edit it.',
                  'اختر قائمة من الجانب لمراجعتها أو تعديلها.',
                ),
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                    child: CaPanel(
                      tone: CaTone.accent,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: selected!.paperTheme.accent,
                                  borderRadius: BorderRadius.circular(11),
                                  border: Border.all(
                                    color: selected!.paperTheme.border,
                                  ),
                                ),
                                child: Icon(
                                  Icons.list_alt_rounded,
                                  color: selected!.paperTheme.accentText,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      selected!.nameFor(widget.language),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${selected!.familyCode} · v${selected!.versionNumber}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _t(
                              '${items.length} items · ${sites.where((s) => s.checklistType == selected!.code).length} linked units',
                              '${items.length} بند · ${sites.where((s) => s.checklistType == selected!.code).length} وحدات مرتبطة',
                            ),
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
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
                              if (canManageSelectedTemplate)
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
                                  label: Text(
                                    _t('Publish version', 'نشر الإصدار'),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                      child: Material(
                        color: Theme.of(context).colorScheme.surface,
                        clipBehavior: Clip.antiAlias,
                        borderRadius: BorderRadius.circular(14),
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
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
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
                                            _t(
                                              'Add first item',
                                              'إضافة أول بند',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              )
                            : ListView.separated(
                                itemCount: items.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
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
                    ),
                  ),
                ],
              );

        return Row(
          children: [
            SizedBox(width: sidebarWidth, child: list),
            const VerticalDivider(width: 1),
            Expanded(child: detail),
          ],
        );
      },
    );
  }

  // Retained for compatibility while the UI exposes only Library | Templates.
  // ignore: unused_element
  Widget _sitesPane() {
    final narrow = MediaQuery.sizeOf(context).width < 980;
    if (narrow) return _mobileSitesPane();

    final codes = templates
        .where((template) => template.isPublishedVersion)
        .map((template) => template.code)
        .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final sidebarWidth = (constraints.maxWidth * 0.31)
            .clamp(380.0, 450.0)
            .toDouble();

        final picker = Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t('Checklist locations', 'مواقع قوائم الفحص'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _t(
                      'Site → building/floor/area context → checklist',
                      'الموقع ← المبنى/الطابق/المنطقة ← قائمة الفحص',
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 6),
                children: [
                  for (final g in campusGroups) ...[
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        12,
                        10,
                        10,
                        4,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.account_balance_outlined, size: 17),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              g.titleFor(widget.language),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    for (final site in g.checklists)
                      Tooltip(
                        message:
                            '${site.nameFor(widget.language)}\n${site.buildingCode} · ${site.checklistType}',
                        waitDuration: const Duration(milliseconds: 500),
                        child: ListTile(
                          contentPadding: const EdgeInsetsDirectional.fromSTEB(
                            18,
                            4,
                            10,
                            4,
                          ),
                          selected: selectedSite?.id == site.id,
                          leading: const Icon(
                            Icons.fact_check_outlined,
                            size: 20,
                          ),
                          title: Text(
                            site.nameFor(widget.language),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                            ),
                          ),
                          subtitle: Text(
                            '${site.buildingCode} · ${site.checklistType}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10.5),
                          ),
                          onTap: () async {
                            setState(() => selectedSite = site);
                            await _loadSiteDetail();
                          },
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        );

        final detail = selectedSite == null
            ? CaEmptyState(
                icon: Icons.location_on_outlined,
                title: _t('Select a checklist location', 'اختر موقع قائمة فحص'),
                message: _t(
                  'Choose a location from the left to review its effective checklist.',
                  'اختر موقعاً من الجانب لمراجعة قائمة الفحص الفعلية.',
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
                children: [
                  CaPanel(
                    tone: CaTone.accent,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          selectedSite!.nameFor(widget.language),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${selectedSite!.buildingCode} · ${selectedSite!.checklistType}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _t(
                            'Effective list = default template items + custom location items.',
                            'القائمة الفعلية = بنود القالب الافتراضي + البنود المخصّصة للموقع.',
                          ),
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue:
                              codes.contains(selectedSite!.checklistType)
                              ? selectedSite!.checklistType
                              : (codes.isNotEmpty ? codes.first : null),
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: _t(
                              'Bound default list',
                              'القائمة الافتراضية المرتبطة',
                            ),
                            prefixIcon: const Icon(Icons.link_rounded),
                          ),
                          items: [
                            for (final code in codes)
                              DropdownMenuItem(
                                value: code,
                                child: Text(
                                  code,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: canEditSites
                              ? (value) {
                                  if (value != null) {
                                    _bindTemplateToSite(value);
                                  }
                                }
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  CaPanel(
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
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            _sourceChip(false),
                            const SizedBox(width: 6),
                            _sourceChip(true),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (effectiveItems.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            child: Text(
                              _t('No items resolved', 'لا بنود محلولة'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
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
                  const SizedBox(height: 12),
                  CaPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _t(
                                      'Location-only items',
                                      'بنود خاصة بالموقع',
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _t(
                                      'Extra questions for this location only.',
                                      'أسئلة إضافية لهذا الموقع فقط.',
                                    ),
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (canEditSites)
                              IconButton(
                                tooltip: _t(
                                  'Add location item',
                                  'إضافة بند للموقع',
                                ),
                                onPressed: () => _editSiteExtra(),
                                icon: const Icon(Icons.add_rounded),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (siteExtras.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Text(
                              _t(
                                'No location-only items',
                                'لا توجد بنود خاصة بالموقع',
                              ),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        else
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
                    ),
                  ),
                ],
              );

        return Row(
          children: [
            SizedBox(width: sidebarWidth, child: picker),
            const VerticalDivider(width: 1),
            Expanded(child: detail),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final publishedCount = templates.where((t) => t.isPublishedVersion).length;
    final draftCount = templates.length - publishedCount;
    final compactMobile = MediaQuery.sizeOf(context).width < 700;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!compactMobile)
          CaContextBlock(
            loading: loading,
            fields: [
              CaContextField(
                label: _t('Library', 'المكتبة'),
                value: _t(
                  '${templates.length} versions',
                  '${templates.length} إصدارات',
                ),
              ),
              CaContextField(
                label: _t('Deployment', 'التوزيع'),
                value: _t(
                  '${sites.length} units${draftCount > 0 ? ' · $draftCount drafts' : ''}',
                  '${sites.length} وحدات${draftCount > 0 ? ' · $draftCount مسودات' : ''}',
                ),
              ),
            ],
          ),
        if (loading)
          LinearProgressIndicator(
            minHeight: 2,
            color: CheckAdminColors.of(context).primaryStrong,
            backgroundColor: Colors.transparent,
          ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CaSpace.gutter,
              CaSpace.md,
              CaSpace.gutter,
              0,
            ),
            child: CaInlineNotice(
              message: message!,
              tone: CaTone.danger,
              onDismiss: () => setState(() => message = null),
            ),
          ),
        ChecklistFilterWorkbench(
          profile: widget.profile,
          language: widget.language,
          onOpenLegacySite: (siteId) async {
            final matching = sites.where((s) => s.id == siteId).firstOrNull;
            if (matching == null || !mounted) return;
            setState(() {
              selectedSite = matching;
              mode = 1;
            });
            await _loadSiteDetail();
          },
        ),
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            CaSpace.gutter,
            compactMobile ? 6 : CaSpace.sm,
            CaSpace.gutter,
            compactMobile ? 4 : CaSpace.sm,
          ),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 0, label: Text(_t('Library', 'المكتبة'))),
                ButtonSegment(
                  value: 1,
                  label: Text(_t('Templates', 'القوالب')),
                ),
              ],
              selected: {mode},
              onSelectionChanged: loading
                  ? null
                  : (values) {
                      final nextMode = values.first;
                      setState(() {
                        mode = nextMode;
                        if (nextMode == 1) {
                          selected = null;
                          items = [];
                        }
                      });
                    },
            ),
          ),
        ),
        Expanded(
          child: loading && templates.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(CaSpace.gutter),
                  child: CaSkeletonList(rows: 6),
                )
              : mode == 0
              ? ChecklistLibraryPane(
                  profile: widget.profile,
                  language: widget.language,
                  onInstalled: (templateId) async {
                    setState(() => mode = 1);
                    await _load();
                    await _selectTemplate(templateId);
                  },
                )
              : _templatesPane(),
        ),
      ],
    );
  }
}

class _NewTemplateResult {
  const _NewTemplateResult({
    required this.organizationId,
    required this.nameEn,
    required this.nameAr,
  });

  final String organizationId;
  final String nameEn;
  final String nameAr;
}
