import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/checkadmin_errors.dart';

/// A single shared filtering vocabulary in CheckAdmin and CheckView.
/// The existing admin tabs, template library and A4 list editor are untouched.
class ChecklistFilterWorkbench extends ConsumerStatefulWidget {
  const ChecklistFilterWorkbench({
    super.key,
    required this.profile,
    required this.language,
    required this.onOpenLegacySite,
    this.onMatchingLegacySiteIdsChanged,
  });
  final Profile profile;
  final String language;
  final ValueChanged<String> onOpenLegacySite;
  final ValueChanged<Set<String>?>? onMatchingLegacySiteIdsChanged;
  @override
  ConsumerState<ChecklistFilterWorkbench> createState() =>
      _ChecklistFilterWorkbenchState();
}

class _ChecklistFilterWorkbenchState
    extends ConsumerState<ChecklistFilterWorkbench> {
  LocationFilterScope scope = const LocationFilterScope([]);
  LocationFilterSelection selection = const LocationFilterSelection();
  bool expanded = true, loading = true, saving = false;
  DateTime date = DateTime.now();
  String? error;
  String get language => widget.language;
  bool get ar => language == 'ar';
  bool get canManage =>
      widget.profile.isPlatformOwner ||
      widget.profile.role == UserRole.superAdmin;
  String t(String en, String arabic) => ar ? arabic : en;
  ChecklistFilterRepository get repo =>
      ref.read(checklistFilterRepositoryProvider);
  String? get orgId =>
      selection.organizationId ??
      widget.profile.homeOrganizationId ??
      scope.leaves.firstOrNull?.organizationId;

  static const _hierarchy = <LocationFilterDimension>[
    LocationFilterDimension.sector,
    LocationFilterDimension.serviceClass,
    LocationFilterDimension.department,
    LocationFilterDimension.coverage,
    LocationFilterDimension.documentKind,
  ];
  static const _kindNames = <LocationFilterDimension, String>{
    LocationFilterDimension.sector: 'sector',
    LocationFilterDimension.serviceClass: 'service_class',
    LocationFilterDimension.department: 'department',
    LocationFilterDimension.coverage: 'coverage',
    LocationFilterDimension.documentKind: 'document_kind',
  };
  static const _parent = <LocationFilterDimension, LocationFilterDimension>{
    LocationFilterDimension.serviceClass: LocationFilterDimension.sector,
    LocationFilterDimension.department: LocationFilterDimension.serviceClass,
    LocationFilterDimension.coverage: LocationFilterDimension.department,
  };

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      // Never block the existing site-grant filters because of a newer
      // facility hierarchy RPC failing or having no mapped assignments.
      final mapped = await ref
          .read(locationHierarchyRepositoryProvider)
          .listMyChecklistLocationScope(requirement: SiteAccessRequirement.read)
          .catchError((Object _) => const LocationFilterScope([]));
      var s = mapped;
      try {
        final groups = await ref
            .read(siteRepositoryProvider)
            .listAccessibleCampusGroups(profile: widget.profile);
        final orgs = await ref
            .read(organizationRepositoryProvider)
            .listOrganizations(activeOnly: true);
        final zones = await ref
            .read(organizationRepositoryProvider)
            .listAllZones();
        s = combineAuthorizedLegacyChecklistScope(
          mapped: mapped,
          authorizedSections: groupCampusGroupsByOrgThenZone(
            organizations: orgs,
            zones: zones,
            groups: groups,
          ),
        );
      } catch (_) {
        // Existing mapped/granted records remain available even when
        // legacy catalog metadata is temporarily unavailable.
      }
      if (!mounted) return;
      setState(() {
        scope = s;
        selection = s.normalize(selection);
      });
    } catch (e) {
      if (mounted) setState(() => error = checkAdminUserMessage(e, language));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await operation();
      if (mounted) await _load();
    } catch (e) {
      if (mounted) setState(() => error = checkAdminUserMessage(e, language));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  String label(LocationFilterDimension d) => switch (d) {
    LocationFilterDimension.sector => t('Sector', 'المجال'),
    LocationFilterDimension.serviceClass => t('Service class', 'صنف الخدمة'),
    LocationFilterDimension.department => t('Department', 'القسم'),
    LocationFilterDimension.coverage => t(
      'Area type / Coverage',
      'نوع المنطقة / التغطية',
    ),
    LocationFilterDimension.documentKind => t(
      'List / Work type',
      'نوع القائمة / العمل',
    ),
    _ => d.name,
  };

  // Category terms are organization-scoped. The admin gets inventory,
  // while CheckView only receives terms from authorized checklist leaves.
  Future<void> _manage(LocationFilterDimension dim) async {
    if (!canManage) return;
    final org = orgId;
    if (org == null) {
      setState(
        () => error = t(
          'Select an organization with checklists first.',
          'اختر مؤسسة تحتوي على قوائم أولًا.',
        ),
      );
      return;
    }
    List<ChecklistFilterTerm> terms;
    try {
      terms = await repo.listTerms(org);
    } catch (e) {
      if (mounted) setState(() => error = checkAdminUserMessage(e, language));
      return;
    }
    if (!mounted) return;
    final parentDimension = _parent[dim];
    String? parentId = parentDimension == null
        ? null
        : selection.valueFor(parentDimension);
    if (parentDimension != null &&
        (parentId == null || !terms.any((x) => x.id == parentId && x.active))) {
      parentId = terms
          .where((x) => x.dimension == _kindNames[parentDimension] && x.active)
          .firstOrNull
          ?.id;
    }
    final codeController = TextEditingController();
    final nameEn = TextEditingController();
    final nameAr = TextEditingController();
    String? localError;
    bool pending = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, update) {
          final parents = parentDimension == null
              ? <ChecklistFilterTerm>[]
              : terms
                    .where(
                      (x) =>
                          x.dimension == _kindNames[parentDimension] &&
                          x.active,
                    )
                    .toList();
          if (parents.isNotEmpty && !parents.any((x) => x.id == parentId)) {
            parentId = parents.first.id;
          }
          final visible = terms
              .where(
                (x) =>
                    x.dimension == _kindNames[dim] &&
                    x.active &&
                    x.parentId == parentId,
              )
              .toList();
          return AlertDialog(
            title: Text('${label(dim)} · ${t('Manage', 'إدارة')}'),
            content: SizedBox(
              width: 520,
              height: MediaQuery.sizeOf(ctx).height * .56,
              child: Column(
                children: [
                  if (parents.isNotEmpty)
                    DropdownButtonFormField<String>(
                      initialValue: parentId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: t('Parent', 'التصنيف الأعلى'),
                      ),
                      items: [
                        for (final p in parents)
                          DropdownMenuItem(
                            value: p.id,
                            child: Text(
                              p.nameFor(language),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => update(() => parentId = v),
                    ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final term in visible)
                          ListTile(
                            dense: true,
                            title: Text(term.nameFor(language)),
                            subtitle: Text(term.code),
                            trailing: IconButton(
                              tooltip: t(
                                'Archive if unused',
                                'أرشفة إن لم يكن مرتبطًا بقائمة',
                              ),
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: pending
                                  ? null
                                  : () async {
                                      final confirmed = await showDialog<bool>(
                                        context: ctx,
                                        builder: (c) => AlertDialog(
                                          title: Text(
                                            t(
                                              'Archive classification?',
                                              'أرشفة التصنيف؟',
                                            ),
                                          ),
                                          content: Text(
                                            t(
                                              'Used classifications cannot be archived.',
                                              'لا يمكن أرشفة تصنيف مرتبط بقوائم أو بتصنيفات فرعية.',
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(c, false),
                                              child: Text(t('Cancel', 'إلغاء')),
                                            ),
                                            FilledButton(
                                              onPressed: () =>
                                                  Navigator.pop(c, true),
                                              child: Text(
                                                t('Archive', 'أرشفة'),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirmed != true || !ctx.mounted) {
                                        return;
                                      }
                                      update(() => pending = true);
                                      try {
                                        await repo.archiveTerm(term);
                                        terms = await repo.listTerms(org);
                                        if (ctx.mounted) {
                                          update(() => localError = null);
                                        }
                                        await _load();
                                      } catch (e) {
                                        if (ctx.mounted) {
                                          update(
                                            () => localError =
                                                checkAdminUserMessage(
                                                  e,
                                                  language,
                                                ),
                                          );
                                        }
                                      } finally {
                                        if (ctx.mounted) {
                                          update(() => pending = false);
                                        }
                                      }
                                    },
                            ),
                          ),
                        if (visible.isEmpty)
                          ListTile(
                            title: Text(
                              t(
                                'No items yet. Add one below.',
                                'لا توجد خيارات بعد. أضف خيارًا أدناه.',
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Divider(),
                  TextField(
                    controller: nameEn,
                    decoration: InputDecoration(
                      labelText: t('English name', 'الاسم بالإنجليزية'),
                    ),
                    maxLength: 100,
                  ),
                  TextField(
                    controller: nameAr,
                    decoration: InputDecoration(
                      labelText: t('Arabic name', 'الاسم بالعربية'),
                    ),
                    maxLength: 100,
                  ),
                  TextField(
                    controller: codeController,
                    decoration: InputDecoration(
                      labelText: t(
                        'Code — lowercase letters / underscores',
                        'الرمز — أحرف إنجليزية صغيرة وشرطة سفلية',
                      ),
                    ),
                  ),
                  if (localError != null)
                    Text(
                      localError!,
                      style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                    ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.add),
                    onPressed: pending
                        ? null
                        : () async {
                            if (nameEn.text.trim().isEmpty ||
                                nameAr.text.trim().isEmpty ||
                                codeController.text.trim().isEmpty) {
                              update(
                                () => localError = t(
                                  'All names and code are required.',
                                  'الاسم باللغتين والرمز مطلوبة.',
                                ),
                              );
                              return;
                            }
                            update(() => pending = true);
                            try {
                              await repo.addTerm(
                                organizationId: org,
                                dimension: _kindNames[dim]!,
                                parentId: parentId,
                                code: codeController.text.trim(),
                                nameEn: nameEn.text.trim(),
                                nameAr: nameAr.text.trim(),
                              );
                              terms = await repo.listTerms(org);
                              codeController.clear();
                              nameEn.clear();
                              nameAr.clear();
                              if (ctx.mounted) update(() => localError = null);
                              await _load();
                            } catch (e) {
                              if (ctx.mounted) {
                                update(
                                  () => localError = checkAdminUserMessage(
                                    e,
                                    language,
                                  ),
                                );
                              }
                            } finally {
                              if (ctx.mounted) update(() => pending = false);
                            }
                          },
                    label: Text(t('Add new', 'إضافة جديد')),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: pending ? null : () => Navigator.pop(ctx),
                child: Text(t('Close', 'إغلاق')),
              ),
            ],
          );
        },
      ),
    );
    // Controllers have been removed with the dialog.
    codeController.dispose();
    nameEn.dispose();
    nameAr.dispose();
  }

  Future<void> _editAssignment(LocationScopeLeaf leaf) async {
    if (!canManage) return;
    List<ChecklistFilterTerm> terms;
    try {
      terms = await repo.listTerms(leaf.organizationId);
    } catch (e) {
      if (mounted) setState(() => error = checkAdminUserMessage(e, language));
      return;
    }
    if (!mounted) return;
    final current = <LocationFilterDimension, String?>{
      LocationFilterDimension.sector: leaf.sectorId,
      LocationFilterDimension.serviceClass: leaf.serviceClassId,
      LocationFilterDimension.department: leaf.departmentId,
      LocationFilterDimension.coverage: leaf.coverageId,
      LocationFilterDimension.documentKind: leaf.documentKindId,
    };
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(t('Classify checklist', 'تصنيف القائمة')),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    leaf.checklistNameEn,
                    style: Theme.of(ctx).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  for (final dim in _hierarchy)
                    Builder(
                      builder: (ctx) {
                        final p = _parent[dim];
                        final options = terms
                            .where(
                              (x) =>
                                  x.active &&
                                  x.dimension == _kindNames[dim] &&
                                  (p == null || x.parentId == current[p]),
                            )
                            .toList();
                        final choice = options.any((x) => x.id == current[dim])
                            ? current[dim]
                            : null;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('${dim.name}:$choice'),
                            initialValue: choice,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: label(dim),
                              border: const OutlineInputBorder(),
                            ),
                            items: [
                              for (final term in options)
                                DropdownMenuItem(
                                  value: term.id,
                                  child: Text(
                                    term.nameFor(language),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (v) => update(() {
                              current[dim] = v;
                              final i = _hierarchy.indexOf(dim);
                              if (dim != LocationFilterDimension.documentKind) {
                                for (final below in _hierarchy.skip(i + 1)) {
                                  if (below !=
                                      LocationFilterDimension.documentKind) {
                                    current[below] = null;
                                  }
                                }
                              }
                            }),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('Cancel', 'إلغاء')),
            ),
            FilledButton(
              onPressed: current.values.any((v) => v == null)
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: Text(t('Save', 'حفظ')),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && mounted) {
      await _run(
        () => repo.assign(
          assignmentId: leaf.assignmentId,
          sectorId: current[LocationFilterDimension.sector]!,
          serviceClassId: current[LocationFilterDimension.serviceClass]!,
          departmentId: current[LocationFilterDimension.department]!,
          coverageId: current[LocationFilterDimension.coverage]!,
          documentKindId: current[LocationFilterDimension.documentKind]!,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = scope.filteredLeaves(scope.normalize(selection));
    final screen = MediaQuery.sizeOf(context);
    final panelHeight = expanded
        ? (screen.height * .43).clamp(250.0, 435.0)
        : 108.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: panelHeight,
          child: SingleChildScrollView(
            child: ChecklistLocationFilterPanel(
              scope: scope,
              selection: selection,
              onSelectionChanged: (v) {
                setState(() => selection = v);
                widget.onMatchingLegacySiteIdsChanged?.call({
                  for (final leaf in scope.filteredLeaves(v))
                    if (leaf.legacySiteId != null) leaf.legacySiteId!,
                });
              },
              date: date,
              onPreviousDate: () =>
                  setState(() => date = date.subtract(const Duration(days: 1))),
              onNextDate: date.isBefore(DateTime.now())
                  ? () =>
                        setState(() => date = date.add(const Duration(days: 1)))
                  : null,
              onPickDate: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: DateTime(2024),
                  lastDate: DateTime.now(),
                );
                if (picked != null && mounted) setState(() => date = picked);
              },
              expanded: expanded,
              onExpandedChanged: (v) => setState(() => expanded = v),
              language: language,
              loading: loading,
              margin: const EdgeInsets.fromLTRB(12, 4, 12, 2),
              onManageDimension: canManage ? _manage : null,
            ),
          ),
        ),
        if (saving || loading) const LinearProgressIndicator(minHeight: 2),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 5, 14, 3),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  t(
                    'Matching checklists · ${filtered.length}',
                    'القوائم المطابقة · ${filtered.length}',
                  ),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() => selection = const LocationFilterSelection());
                  widget.onMatchingLegacySiteIdsChanged?.call(null);
                },
                icon: const Icon(Icons.restart_alt, size: 17),
                label: Text(t('Reset', 'إعادة ضبط')),
              ),
              if (canManage)
                TextButton.icon(
                  onPressed: () => _manage(LocationFilterDimension.department),
                  icon: const Icon(Icons.add, size: 17),
                  label: Text(t('Manage categories', 'إدارة الأقسام')),
                ),
              IconButton(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                tooltip: t('Refresh', 'تحديث'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 108,
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    t(
                      'No checklists match these filters.',
                      'لا توجد قوائم مطابقة للفلاتر.',
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 3,
                  ),
                  scrollDirection: Axis.vertical,
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 7),
                  itemBuilder: (ctx, i) {
                    final leaf = filtered[i];
                    return SizedBox(
                      height: 106,
                      child: Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      language == 'ar' &&
                                              (leaf.checklistNameAr ?? '')
                                                  .isNotEmpty
                                          ? leaf.checklistNameAr!
                                          : leaf.checklistNameEn,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(ctx).textTheme.labelLarge,
                                    ),
                                  ),
                                  if (canManage)
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(Icons.tune, size: 18),
                                      tooltip: t(
                                        'Assign classifications',
                                        'تعيين التصنيفات',
                                      ),
                                      onPressed: saving
                                          ? null
                                          : () => _editAssignment(leaf),
                                    ),
                                ],
                              ),
                              Text(
                                '${leaf.serviceClassNameEn} · ${leaf.departmentNameEn}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(ctx).textTheme.bodySmall,
                              ),
                              Expanded(
                                child: Align(
                                  alignment: AlignmentDirectional.bottomStart,
                                  child: TextButton(
                                    onPressed: leaf.legacySiteId == null
                                        ? null
                                        : () => widget.onOpenLegacySite(
                                            leaf.legacySiteId!,
                                          ),
                                    child: Text(
                                      t('Open checklist', 'فتح القائمة'),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
