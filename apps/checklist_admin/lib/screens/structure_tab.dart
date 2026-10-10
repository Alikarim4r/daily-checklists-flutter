import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/checkadmin_errors.dart';
import '../design/checkadmin_tokens.dart';
import '../design/checkadmin_widgets.dart';

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
        selection = _sanitizeSelection(selection);
      });
    } catch (e) {
      setState(() => message = checkAdminUserMessage(e, widget.language));
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
        scrollable: true,
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
    try {
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
    } catch (e) {
      _showWriteError(e);
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
        scrollable: true,
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
    try {
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
    } catch (e) {
      _showWriteError(e);
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
    final preferences = ref.read(sharedPreferencesProvider);
    final pinHistoryKey = 'checkadmin.recent_pin_numbers.$orgId';
    final recentPins = preferences.getStringList(pinHistoryKey) ?? <String>[];

    final catalog = ref.read(catalogRepositoryProvider);
    final allTemplates = await catalog.listTemplates(activeOnly: false);
    final libraryTemplates = await ref
        .read(checklistLibraryRepositoryProvider)
        .listTemplates(organizationId: orgId);
    if (!mounted) return;

    final libraryTemplateIds = {
      for (final row in libraryTemplates)
        if (row.installedTemplateId != null) row.installedTemplateId!,
    };
    final customerTemplates = allTemplates
        .where(
          (template) =>
              template.organizationId == orgId &&
              template.libraryTemplateId == null &&
              !libraryTemplateIds.contains(template.id),
        )
        .toList();

    final nameEn = TextEditingController(text: existing?.nameEn ?? '');
    final nameAr = TextEditingController(text: existing?.nameAr ?? '');
    final code = TextEditingController(text: existing?.buildingCode ?? '');
    final pin = TextEditingController(
      text: existing?.pin ?? (recentPins.isEmpty ? '' : recentPins.first),
    );
    final defaultParentSite = sites
        .where((site) => site.id == defaultParent)
        .firstOrNull;
    String locationForCampus(String? campusId) {
      final campus = sites.where((site) => site.id == campusId).firstOrNull;
      if (campus == null) return '';
      final address = campus.location.trim();
      return address.isNotEmpty && address != '—'
          ? address
          : campus.nameFor(widget.language);
    }

    final location = TextEditingController(
      text:
          existing?.location ??
          (defaultParentSite == null
              ? ''
              : locationForCampus(defaultParentSite.id)),
    );
    var checklistType = existing?.checklistType ?? 'DEFAULT';
    var checklistCategory = existing?.checklistCategory ?? 'general';
    var checklistSubcategory = existing?.checklistSubcategory ?? '';
    var floorScope = existing?.floorScope ?? 'all';
    var floorChoice = floorScope == 'floor_number:-1'
        ? 'lgf'
        : floorScope == 'ground'
        ? 'gf'
        : floorScope == 'first'
        ? 'ff'
        : floorScope.startsWith('floor_number:')
        ? 'floor_number'
        : floorScope;
    final floorNumber = TextEditingController(
      text: floorScope.startsWith('floor_number:')
          ? floorScope.substring('floor_number:'.length)
          : '',
    );

    final currentTemplate = allTemplates
        .where((template) => template.code == checklistType)
        .firstOrNull;
    String templateChoice;
    if (currentTemplate?.libraryTemplateId != null) {
      templateChoice = 'library:${currentTemplate!.libraryTemplateId}';
    } else if (currentTemplate != null &&
        currentTemplate.organizationId == orgId) {
      templateChoice = 'customer:${currentTemplate.id}';
    } else {
      final preferredLibrary = libraryTemplates
          .where((row) => row.canAccess || row.isInstalled)
          .firstOrNull;
      if (existing == null && preferredLibrary != null) {
        templateChoice = 'library:${preferredLibrary.id}';
      } else if (existing == null && customerTemplates.isNotEmpty) {
        templateChoice = 'customer:${customerTemplates.first.id}';
      } else {
        templateChoice = 'legacy:$checklistType';
      }
    }

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
        builder: (context, setLocal) {
          InputDecoration decoration(String label) => InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true,
          );

          return AlertDialog(
            scrollable: true,
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
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameEn,
                    decoration: decoration(_t('Name EN', 'الاسم إنجليزي')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameAr,
                    decoration: decoration(_t('Name AR', 'الاسم عربي')),
                  ),
                  if (!isCampus) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: code,
                      decoration: decoration(
                        _t('Building / list code', 'رمز المبنى / القائمة'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: pin,
                      decoration: decoration('PIN No.').copyWith(
                        suffixIcon: recentPins.isEmpty
                            ? null
                            : PopupMenuButton<String>(
                                tooltip: _t(
                                  'Previous PIN numbers',
                                  'أرقام PIN السابقة',
                                ),
                                icon: const Icon(Icons.history),
                                onSelected: (value) =>
                                    setLocal(() => pin.text = value),
                                itemBuilder: (_) => [
                                  for (final number in recentPins)
                                    PopupMenuItem(
                                      value: number,
                                      child: Text(number),
                                    ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      initialValue: parentSiteId,
                      isExpanded: true,
                      decoration: decoration(
                        _t('Parent campus', 'الموقع الأب (الحرم)'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text(
                            _t('— Standalone —', '— بدون (مستقلة) —'),
                          ),
                        ),
                        for (final campus in campusChoices)
                          DropdownMenuItem(
                            value: campus.id,
                            child: Text(
                              campus.nameFor(widget.language),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        final previousAutoLocation = locationForCampus(
                          parentSiteId,
                        );
                        setLocal(() {
                          parentSiteId = value;
                          if (existing == null &&
                              (location.text.trim().isEmpty ||
                                  location.text == previousAutoLocation)) {
                            location.text = locationForCampus(value);
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: templateChoice,
                      isExpanded: true,
                      decoration: decoration(
                        _t('Checklist template', 'قالب قائمة الفحص'),
                      ),
                      items: [
                        DropdownMenuItem<String>(
                          value: '__library_header__',
                          enabled: false,
                          child: Text(
                            _t('LIBRARY', 'المكتبة'),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        for (final row in libraryTemplates)
                          DropdownMenuItem<String>(
                            value: 'library:${row.id}',
                            enabled: row.canAccess || row.isInstalled,
                            child: Text(
                              '${row.nameFor(widget.language)} · '
                              '${row.categoryNameFor(widget.language)}'
                              '${(!row.canAccess && !row.isInstalled) ? ' · Premium' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        DropdownMenuItem<String>(
                          value: '__my_header__',
                          enabled: false,
                          child: Text(
                            _t('MY TEMPLATES', 'قوالب العميل'),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        for (final template in customerTemplates)
                          DropdownMenuItem<String>(
                            value: 'customer:${template.id}',
                            child: Text(
                              template.nameFor(widget.language),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        if (templateChoice.startsWith('legacy:'))
                          DropdownMenuItem<String>(
                            value: templateChoice,
                            child: Text(
                              _t(
                                'Current template · $checklistType',
                                'القالب الحالي · $checklistType',
                              ),
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null && !value.startsWith('__')) {
                          setLocal(() => templateChoice = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: checklistCategory,
                      isExpanded: true,
                      decoration: decoration(
                        _t('Checklist category', 'تصنيف قائمة الفحص'),
                      ),
                      items: [
                        for (final category in ChecklistCategories.ids)
                          DropdownMenuItem(
                            value: category,
                            child: Text(
                              ChecklistCategories.title(
                                category,
                                widget.language,
                              ),
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setLocal(() {
                            checklistCategory = value;
                            if (value != 'facilities') {
                              checklistSubcategory = '';
                            }
                          });
                        }
                      },
                    ),
                    if (checklistCategory == 'facilities' && !isCampus) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey('subcategory-$checklistCategory'),
                        initialValue: checklistSubcategory,
                        decoration: decoration(
                          _t('Subfolder', 'الفرع الداخلي'),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: '',
                            child: Text(
                              _t('Directly in category', 'داخل الصنف مباشرة'),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'washrooms',
                            child: Text(
                              ChecklistSubcategories.title(
                                'washrooms',
                                widget.language,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (v) =>
                            setLocal(() => checklistSubcategory = v ?? ''),
                      ),
                    ],
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: floorChoice,
                      isExpanded: true,
                      decoration: decoration(
                        _t('Floor scope', 'الدور / نطاق الدور'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'all',
                          child: Text(_t('All floors', 'كل الأدوار')),
                        ),
                        DropdownMenuItem(
                          value: 'basement',
                          child: Text(_t('Basement', 'البيسمنت')),
                        ),
                        DropdownMenuItem(
                          value: 'parking',
                          child: Text(_t('Parking', 'الباركينغ')),
                        ),
                        DropdownMenuItem(
                          value: 'lgf',
                          child: Text(
                            _t(
                              'LGF · Lower Ground Floor',
                              'LGF · الأرضي السفلي',
                            ),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'gf',
                          child: Text(_t('GF · Ground Floor', 'GF · الأرضي')),
                        ),
                        DropdownMenuItem(
                          value: 'ff',
                          child: Text(
                            _t('FF · First Floor', 'FF · الدور الأول'),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'roof',
                          child: Text(_t('Roof', 'السطح')),
                        ),
                        DropdownMenuItem(
                          value: 'floor_number',
                          child: Text(
                            _t('Specific floor number', 'رقم دور محدد'),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setLocal(() => floorChoice = value);
                        }
                      },
                    ),
                    if (floorChoice == 'floor_number') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: floorNumber,
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                        ),
                        decoration: decoration(_t('Floor number', 'رقم الدور')),
                      ),
                    ],
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: location,
                    decoration: decoration(_t('Location', 'الموقع / العنوان')),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: zoneId,
                    isExpanded: true,
                    decoration: decoration(_t('Zone', 'المنطقة')),
                    items: [
                      DropdownMenuItem(
                        value: null,
                        child: Text(_t('— None —', '— بدون —')),
                      ),
                      for (final zone in orgZones)
                        DropdownMenuItem(
                          value: zone.id,
                          child: Text(
                            zone.nameFor(widget.language),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => setLocal(() => zoneId = value),
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
          );
        },
      ),
    );
    if (ok != true) return;

    try {
      if (!isCampus) {
        if (templateChoice.startsWith('library:')) {
          final libraryId = templateChoice.substring('library:'.length);
          final row = libraryTemplates
              .where((item) => item.id == libraryId)
              .firstOrNull;
          if (row == null || (!row.canAccess && !row.isInstalled)) {
            throw StateError('Checklist template is not available');
          }
          final installedId =
              row.installedTemplateId ??
              await ref
                  .read(checklistLibraryRepositoryProvider)
                  .installTemplate(
                    libraryTemplateId: row.id,
                    organizationId: orgId,
                  );
          final installed = await catalog.getTemplateById(installedId);
          if (installed == null) {
            throw StateError('Checklist installation failed');
          }
          checklistType = installed.code;
        } else if (templateChoice.startsWith('customer:')) {
          final templateId = templateChoice.substring('customer:'.length);
          final template = allTemplates
              .where((item) => item.id == templateId)
              .firstOrNull;
          if (template == null) {
            throw StateError('Checklist template not found');
          }
          checklistType = template.code;
        }

        if (floorChoice == 'floor_number') {
          final number = int.tryParse(floorNumber.text.trim());
          if (number == null) {
            throw StateError('Enter a valid floor number');
          }
          floorScope = 'floor_number:$number';
        } else {
          // Keep storage compatible with the existing floor_scope constraint.
          floorScope = switch (floorChoice) {
            'lgf' => 'floor_number:-1',
            'gf' => 'ground',
            'ff' => 'first',
            _ => floorChoice,
          };
        }
      }

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
          checklistCategory: checklistCategory,
          checklistSubcategory: checklistCategory == 'facilities'
              ? checklistSubcategory
              : '',
          floorScope: floorScope,
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
          checklistCategory: checklistCategory,
          checklistSubcategory: checklistCategory == 'facilities'
              ? checklistSubcategory
              : '',
          floorScope: floorScope,
          location: location.text.trim(),
          isActive: existing.isActive,
        );
        await _load();
      }
      if (!isCampus && pin.text.trim().isNotEmpty) {
        final pinValue = pin.text.trim();
        await preferences.setStringList(
          pinHistoryKey,
          [
            pinValue,
            ...recentPins.where((value) => value != pinValue),
          ].take(15).toList(),
        );
      }
    } catch (error) {
      _showWriteError(error);
    } finally {
      nameEn.dispose();
      nameAr.dispose();
      code.dispose();
      pin.dispose();
      location.dispose();
      floorNumber.dispose();
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
      await ref.read(siteRepositoryProvider).deleteSite(site.id);
      await _load();
    } catch (e) {
      _showWriteError(e);
    }
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
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(_t('Archive', 'أرشفة')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(organizationRepositoryProvider)
          .update(org.copyWith(isActive: false));
      await _load();
    } catch (e) {
      _showWriteError(e);
    }
  }

  void _showWriteError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(checkAdminUserMessage(error, widget.language))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= CaBreakpoint.twoPane;
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

    Widget workspace;
    if (loading && orgs.isEmpty) {
      workspace = const Padding(
        padding: EdgeInsets.all(CaSpace.gutter),
        child: CaSkeletonList(rows: 6),
      );
    } else if (!wide) {
      workspace = tree;
    } else {
      workspace = Row(
        children: [
          SizedBox(
            width: 360,
            child: Material(
              color: CheckAdminColors.of(context).surface,
              child: tree,
            ),
          ),
          VerticalDivider(width: 1, color: CheckAdminColors.of(context).rule),
          Expanded(
            child: selection == null
                ? CaEmptyState(
                    icon: Icons.account_tree_outlined,
                    title: _t(
                      'Select an organization, zone, or site',
                      'اختر جهة أو منطقة أو موقعاً',
                    ),
                    message: _t(
                      'The detail workspace will appear here without losing your position in the hierarchy.',
                      'ستظهر مساحة التفاصيل هنا دون فقدان موضعك في الهيكل.',
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CaContextBlock(
          loading: loading,
          fields: [
            CaContextField(
              label: _t('Scope', 'النطاق'),
              value: _t('All organizations', 'كل الجهات'),
            ),
            CaContextField(
              label: _t('Portfolio', 'المحفظة'),
              value: _t(
                '${orgs.length} orgs · ${zones.length} zones · ${sites.length} units',
                '${orgs.length} جهات · ${zones.length} مناطق · ${sites.length} وحدات',
              ),
              flex: 2,
            ),
          ],
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
        Expanded(child: workspace),
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
    final c = CheckAdminColors.of(context);
    return Column(
      children: [
        CaSectionLabel(
          title: _t('Organizations', 'الجهات'),
          count: orgs.length,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: _t('Refresh', 'تحديث'),
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
              if (onAddOrg != null)
                CaCreateButton(
                  onPressed: onAddOrg,
                  icon: Icons.add,
                  label: _t('Organization', 'جهة'),
                  compactLabel: _t('Org', 'جهة'),
                ),
            ],
          ),
        ),
        Expanded(
          child: orgs.isEmpty
              ? CaEmptyState(
                  icon: Icons.account_tree_outlined,
                  title: _t('No organizations', 'لا توجد جهات'),
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsetsDirectional.fromSTEB(
                    CaSpace.gutter,
                    0,
                    CaSpace.gutter,
                    MediaQuery.viewPaddingOf(context).bottom + CaSpace.lg,
                  ),
                  itemCount: orgs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final org = orgs[i];
                    return Material(
                      color: c.surface,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(CaRadius.panel),
                        side: BorderSide(color: c.rule),
                      ),
                      child: _OrgNode(
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
                        initiallyExpanded: false,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _OrgNode extends StatefulWidget {
  const _OrgNode({
    required this.org,
    required this.zones,
    required this.sites,
    required this.selection,
    required this.language,
    required this.onSelect,
    required this.initiallyExpanded,
  });

  final Organization org;
  final List<Zone> zones;
  final List<ChecklistSite> sites;
  final StructureSelection? selection;
  final String language;
  final ValueChanged<StructureSelection> onSelect;
  final bool initiallyExpanded;

  @override
  State<_OrgNode> createState() => _OrgNodeState();
}

class _OrgNodeState extends State<_OrgNode> {
  int _branchEpoch = 0;

  @override
  Widget build(BuildContext context) {
    final selected =
        widget.selection is StructureOrgSelection &&
        (widget.selection! as StructureOrgSelection).organizationId ==
            widget.org.id;
    final theme = Theme.of(context);
    final c = CheckAdminColors.of(context);
    final sortedZones = [...widget.zones]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: false,
        maintainState: false,
        minTileHeight: 68,
        tilePadding: const EdgeInsetsDirectional.fromSTEB(12, 0, 8, 0),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        onExpansionChanged: (expanded) {
          if (expanded) {
            setState(() => _branchEpoch++);
          }
        },
        leading: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.surfaceRaised,
            borderRadius: BorderRadius.circular(CaRadius.control),
          ),
          child: Icon(
            Icons.account_balance_outlined,
            size: 20,
            color: selected ? c.primaryStrong : c.inkMuted,
          ),
        ),
        title: InkWell(
          onTap: () => widget.onSelect(StructureOrgSelection(widget.org.id)),
          child: Text(
            widget.org.nameFor(widget.language),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              color: selected ? c.primaryStrong : c.ink,
            ),
          ),
        ),
        subtitle: Text(
          widget.language == 'ar'
              ? '${widget.zones.length} مناطق · ${widget.sites.length} وحدات'
              : '${widget.zones.length} zones · ${widget.sites.length} units',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall,
        ),
        children: [
          for (final zone in sortedZones)
            _ZoneNode(
              key: ValueKey('zone-${zone.id}-$_branchEpoch'),
              zone: zone,
              sites: widget.sites,
              selection: widget.selection,
              language: widget.language,
              onSelect: widget.onSelect,
            ),
        ],
      ),
    );
  }
}

class _ZoneNode extends StatefulWidget {
  const _ZoneNode({
    super.key,
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
  State<_ZoneNode> createState() => _ZoneNodeState();
}

class _ZoneNodeState extends State<_ZoneNode> {
  int _branchEpoch = 0;

  @override
  Widget build(BuildContext context) {
    final selected =
        widget.selection is StructureZoneSelection &&
        (widget.selection! as StructureZoneSelection).zoneId == widget.zone.id;
    final theme = Theme.of(context);
    final c = CheckAdminColors.of(context);
    final inZone = widget.sites.where((site) {
      if (site.zoneId == widget.zone.id) return true;
      if (site.parentSiteId == null) return false;
      final parent = widget.sites
          .where((candidate) => candidate.id == site.parentSiteId)
          .firstOrNull;
      return parent?.zoneId == widget.zone.id && site.zoneId == null;
    }).toList();
    final campuses = inZone.where((site) => site.isCampus).toList()
      ..sort((a, b) => a.nameEn.compareTo(b.nameEn));
    final units = inZone.where((site) => site.isChecklistUnit).toList();

    return Container(
      margin: const EdgeInsetsDirectional.fromSTEB(12, 6, 12, 0),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(CaRadius.control),
        border: Border.all(color: c.rule),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          maintainState: false,
          minTileHeight: 54,
          tilePadding: const EdgeInsetsDirectional.fromSTEB(12, 0, 8, 0),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          onExpansionChanged: (expanded) {
            if (expanded) {
              setState(() => _branchEpoch++);
            }
          },
          leading: Icon(
            Icons.map_outlined,
            size: 19,
            color: selected ? c.primaryStrong : c.inkMuted,
          ),
          title: InkWell(
            onTap: () =>
                widget.onSelect(StructureZoneSelection(widget.zone.id)),
            child: Text(
              widget.zone.nameFor(widget.language),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: selected ? c.primaryStrong : c.ink,
              ),
            ),
          ),
          subtitle: Text(
            widget.language == 'ar'
                ? '${inZone.length} مواقع / وحدات'
                : '${inZone.length} sites / units',
            maxLines: 1,
            style: theme.textTheme.bodySmall,
          ),
          children: [
            for (final campus in campuses)
              _CampusNode(
                key: ValueKey('campus-${campus.id}-$_branchEpoch'),
                campus: campus,
                checklists:
                    units
                        .where((unit) => unit.parentSiteId == campus.id)
                        .toList()
                      ..sort(
                        (a, b) => a.buildingCode.compareTo(b.buildingCode),
                      ),
                selection: widget.selection,
                language: widget.language,
                onSelect: widget.onSelect,
              ),
            for (final category in ChecklistCategories.groupAvailable(
              units.where((unit) => unit.parentSiteId == null),
              includeInactive: true,
            ).entries)
              _ChecklistCategoryNode(
                key: ValueKey('uncategorized-${category.key}-$_branchEpoch'),
                category: category.key,
                sites: category.value,
                selection: widget.selection,
                language: widget.language,
                onSelect: widget.onSelect,
              ),
          ],
        ),
      ),
    );
  }
}

class _CampusNode extends StatelessWidget {
  const _CampusNode({
    super.key,
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
    final c = CheckAdminColors.of(context);

    return Container(
      margin: const EdgeInsetsDirectional.fromSTEB(10, 6, 10, 0),
      decoration: BoxDecoration(
        color: c.surfaceRaised.withValues(alpha: .48),
        borderRadius: BorderRadius.circular(CaRadius.control),
        border: Border.all(color: c.rule),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          maintainState: false,
          minTileHeight: 54,
          tilePadding: const EdgeInsetsDirectional.fromSTEB(12, 0, 8, 0),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          leading: _ThemeMarker(
            paperTheme: campus.paperTheme,
            icon: Icons.place_outlined,
            selected: selected,
            size: 28,
          ),
          title: InkWell(
            onTap: () => onSelect(StructureCampusSelection(campus.id)),
            child: Text(
              campus.nameFor(language),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: selected ? c.primaryStrong : c.ink,
              ),
            ),
          ),
          subtitle: checklists.isEmpty
              ? null
              : Text(
                  language == 'ar'
                      ? '${checklists.length} قوائم'
                      : '${checklists.length} checklists',
                  style: theme.textTheme.bodySmall,
                ),
          children: [
            for (final category in ChecklistCategories.groupAvailable(
              checklists,
              includeInactive: true,
            ).entries)
              _ChecklistCategoryNode(
                category: category.key,
                sites: category.value,
                selection: selection,
                language: language,
                onSelect: onSelect,
              ),
          ],
        ),
      ),
    );
  }
}

/// Editable structure is grouped by the same nonempty categories as CheckView.
class _ChecklistCategoryNode extends StatelessWidget {
  const _ChecklistCategoryNode({
    super.key,
    required this.category,
    required this.sites,
    required this.selection,
    required this.language,
    required this.onSelect,
  });

  final String category;
  final List<ChecklistSite> sites;
  final StructureSelection? selection;
  final String language;
  final ValueChanged<StructureSelection> onSelect;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(12, 5, 12, 0),
    child: ExpansionTile(
      key: ValueKey('structure-category-$category'),
      initiallyExpanded: false,
      leading: const Icon(Icons.folder_outlined, size: 20),
      title: Text(ChecklistCategories.title(category, language)),
      subtitle: Text(
        language == 'ar'
            ? '${sites.length} قوائم فحص'
            : '${sites.length} checklists',
      ),
      children: [
        if (category == 'facilities')
          for (final branch in ChecklistSubcategories.available(sites).entries)
            if (branch.key.isNotEmpty)
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 12, 4),
                child: ExpansionTile(
                  initiallyExpanded: false,
                  leading: const Icon(Icons.folder_copy_outlined, size: 18),
                  title: Text(
                    ChecklistSubcategories.title(branch.key, language),
                  ),
                  subtitle: Text(
                    language == 'ar'
                        ? '${branch.value.length} قوائم'
                        : '${branch.value.length} checklists',
                  ),
                  children: [
                    for (final site in branch.value)
                      _ChecklistLeaf(
                        key: ValueKey('structure-unit-${site.id}'),
                        site: site,
                        selection: selection,
                        language: language,
                        onSelect: onSelect,
                        indent: 12,
                      ),
                  ],
                ),
              )
            else
              for (final site in branch.value)
                _ChecklistLeaf(
                  key: ValueKey('structure-unit-${site.id}'),
                  site: site,
                  selection: selection,
                  language: language,
                  onSelect: onSelect,
                  indent: 12,
                )
        else
          for (final site in sites)
            _ChecklistLeaf(
              key: ValueKey('structure-unit-${site.id}'),
              site: site,
              selection: selection,
              language: language,
              onSelect: onSelect,
              indent: 12,
            ),
      ],
    ),
  );
}

class _ChecklistLeaf extends StatelessWidget {
  const _ChecklistLeaf({
    super.key,
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
    final c = CheckAdminColors.of(context);
    return Container(
      margin: const EdgeInsetsDirectional.fromSTEB(10, 6, 10, 0),
      decoration: BoxDecoration(
        color: selected ? c.primarySoft.withValues(alpha: .55) : c.surface,
        borderRadius: BorderRadius.circular(CaRadius.control),
        border: Border.all(color: c.rule),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        minTileHeight: 52,
        dense: true,
        contentPadding: EdgeInsetsDirectional.only(start: indent, end: 8),
        leading: CaCodeBadge(
          code: site.buildingCode,
          width: 64,
          tone: selected ? CaTone.accent : CaTone.neutral,
        ),
        title: Text(
          site.nameFor(language),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selected ? c.primaryStrong : c.ink,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        subtitle: site.checklistType.isEmpty
            ? null
            : Text(
                site.checklistType,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
        onTap: () => onSelect(StructureChecklistSelection(site.id)),
      ),
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
        borderRadius: BorderRadius.circular(CaRadius.control),
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

  Widget _statusChip(BuildContext context, {required bool active}) {
    final c = CheckAdminColors.of(context);
    final tint = active ? c.good : c.warning;
    return Chip(
      avatar: Icon(
        active ? Icons.check_circle : Icons.pause_circle_filled,
        size: 16,
        color: tint,
      ),
      label: Text(active ? _t('Active', 'مفعل') : _t('Inactive', 'معطل')),
      labelStyle: Theme.of(
        context,
      ).textTheme.labelMedium?.copyWith(color: c.ink),
      visualDensity: VisualDensity.compact,
      backgroundColor: active ? c.goodSoft : c.warningSoft,
      side: BorderSide(color: tint.withValues(alpha: .45)),
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
            _statusChip(context, active: org.isActive),
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
                  body: UsersTab(profile: profile, language: language),
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
                  language: language,
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
            _statusChip(context, active: zone.isActive),
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
                  body: UsersTab(profile: profile, language: language),
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
            _statusChip(context, active: site.isActive),
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
                  body: UsersTab(profile: profile, language: language),
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
