import 'dart:convert';

import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../design/checkadmin_errors.dart';

/// P2 workbench: assets -> scheduled plans -> auditable work orders.
class PpmTab extends ConsumerStatefulWidget {
  const PpmTab({super.key, required this.profile, required this.language});
  final Profile profile;
  final String language;
  @override
  ConsumerState<PpmTab> createState() => _PpmTabState();
}

class _PpmTabState extends ConsumerState<PpmTab> {
  List<Organization> organizations = [];
  List<ChecklistSite> sites = [];
  List<FmAsset> assets = [];
  List<FmPpmPlan> plans = [];
  List<FmPpmJob> jobs = [];
  String? organizationId;
  bool loading = true, busy = false;
  String? error, info;
  String statusFilter = 'all';
  int selectedTab = 0;
  int request = 0;
  bool get ar => widget.language == 'ar';
  String t(String en, String arValue) => ar ? arValue : en;
  bool get canManage =>
      widget.profile.isPlatformOwner ||
      widget.profile.role == UserRole.superAdmin;
  FmPpmRepository get repository => ref.read(fmPpmRepositoryProvider);

  @override
  void initState() {
    super.initState();
    Future.microtask(_initialize);
  }

  Future<void> _initialize() async {
    try {
      final orgs = await ref
          .read(organizationRepositoryProvider)
          .listOrganizations(activeOnly: true);
      if (!mounted) return;
      final home = widget.profile.homeOrganizationId;
      setState(() {
        organizations = widget.profile.isPlatformOwner
            ? orgs
            : orgs.where((org) => org.id == home).toList();
        organizationId = widget.profile.isPlatformOwner
            ? organizations.firstOrNull?.id
            : home;
      });
      await _reload();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = checkAdminUserMessage(e, widget.language);
          loading = false;
        });
      }
    }
  }

  Future<void> _reload() async {
    final orgId = organizationId;
    if (orgId == null) {
      if (mounted) setState(() => loading = false);
      return;
    }
    final id = ++request;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      // While an organization administrator uses the workbench, materialize
      // the upcoming bounded schedule automatically and idempotently.
      // The explicit Generate button remains available for catch-up.
      if (canManage) {
        try {
          await repository.generateDueJobs(
            orgId,
            horizonDays: 45,
            maxJobs: 200,
          );
        } catch (_) {
          /* Reads remain available if scheduling requires attention. */
        }
      }
      final result = await Future.wait<Object>([
        repository.listAssets(orgId),
        repository.listPlans(orgId),
        repository.listJobs(orgId),
        ref.read(siteRepositoryProvider).listCampusSites(activeOnly: true),
      ]);
      if (!mounted || id != request) return;
      setState(() {
        assets = result[0] as List<FmAsset>;
        plans = result[1] as List<FmPpmPlan>;
        jobs = result[2] as List<FmPpmJob>;
        sites = (result[3] as List<ChecklistSite>)
            .where((site) => site.organizationId == orgId)
            .toList();
      });
    } catch (e) {
      if (mounted && id == request) {
        setState(() => error = checkAdminUserMessage(e, widget.language));
      }
    } finally {
      if (mounted && id == request) setState(() => loading = false);
    }
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      info = null;
    });
    try {
      await action();
      if (mounted) await _reload();
    } catch (e) {
      if (mounted) {
        setState(() => error = checkAdminUserMessage(e, widget.language));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _assetName(String id) =>
      assets.where((a) => a.id == id).firstOrNull?.nameFor(widget.language) ??
      id;
  String _planName(String id) =>
      plans.where((a) => a.id == id).firstOrNull?.titleFor(widget.language) ??
      id;
  String _date(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  Future<void> _editAsset({FmAsset? existing}) async {
    final code = TextEditingController(text: existing?.code ?? '');
    final name = TextEditingController(text: existing?.nameEn ?? '');
    final arabic = TextEditingController(text: existing?.nameAr ?? '');
    final type = TextEditingController(text: existing?.type ?? 'hvac');
    final notes = TextEditingController(text: existing?.notes ?? '');
    String? siteId = existing?.siteId;
    String? buildingId = existing?.buildingId;
    String? floorId = existing?.floorId;
    String? areaId = existing?.areaId;
    final locations = ref.read(locationHierarchyRepositoryProvider);
    List<FacilityBuilding> buildings = [];
    List<FacilityFloor> floors = [];
    List<FacilityArea> areas = [];
    try {
      if (siteId != null) {
        buildings = await locations.listBuildings(siteId: siteId);
      }
      if (buildingId != null) {
        floors = await locations.listFloors(buildingId: buildingId);
      }
      if (floorId != null) areas = await locations.listAreas(floorId: floorId);
    } catch (_) {
      /* Leave location fields empty until server is available. */
    }
    if (!mounted) return;
    var criticality = existing?.criticality ?? 'medium';
    final form = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: Text(
            existing == null
                ? t('Register asset', 'تسجيل أصل')
                : t('Edit asset', 'تعديل الأصل'),
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: code,
                      decoration: InputDecoration(
                        labelText: t('Asset code', 'رمز الأصل'),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? t('Required', 'مطلوب')
                          : null,
                    ),
                    TextFormField(
                      controller: name,
                      decoration: InputDecoration(
                        labelText: t('Asset name', 'اسم الأصل'),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? t('Required', 'مطلوب')
                          : null,
                    ),
                    TextFormField(
                      controller: arabic,
                      decoration: InputDecoration(
                        labelText: t('Arabic name', 'الاسم بالعربية'),
                      ),
                    ),
                    TextFormField(
                      controller: type,
                      decoration: InputDecoration(
                        labelText: t('Asset type', 'نوع الأصل'),
                      ),
                    ),
                    DropdownButtonFormField<String?>(
                      key: ValueKey('asset-site-$siteId'),
                      initialValue: siteId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: t('Site', 'الموقع'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text(t('Not assigned', 'غير مرتبط بموقع')),
                        ),
                        for (final s in sites)
                          DropdownMenuItem(
                            value: s.id,
                            child: Text(
                              s.nameFor(widget.language),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) async {
                        refresh(() {
                          siteId = v;
                          buildingId = null;
                          floorId = null;
                          areaId = null;
                          buildings = [];
                          floors = [];
                          areas = [];
                        });
                        if (v != null) {
                          try {
                            final rows = await locations.listBuildings(
                              siteId: v,
                            );
                            if (context.mounted) {
                              refresh(() => buildings = rows);
                            }
                          } catch (_) {
                            /* Manual asset can still be registered at site level. */
                          }
                        }
                      },
                    ),
                    if (siteId != null)
                      DropdownButtonFormField<String?>(
                        key: ValueKey('asset-building-$siteId-$buildingId'),
                        initialValue: buildingId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: t('Building', 'المبنى'),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text(t('All buildings', 'كل المباني')),
                          ),
                          for (final b in buildings)
                            DropdownMenuItem(
                              value: b.id,
                              child: Text(
                                b.nameFor(widget.language),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) async {
                          refresh(() {
                            buildingId = v;
                            floorId = null;
                            areaId = null;
                            floors = [];
                            areas = [];
                          });
                          if (v != null) {
                            try {
                              final rows = await locations.listFloors(
                                buildingId: v,
                              );
                              if (context.mounted) refresh(() => floors = rows);
                            } catch (_) {}
                          }
                        },
                      ),
                    if (buildingId != null)
                      DropdownButtonFormField<String?>(
                        key: ValueKey('asset-floor-$buildingId-$floorId'),
                        initialValue: floorId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: t('Floor', 'الطابق'),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text(t('All floors', 'كل الطوابق')),
                          ),
                          for (final f in floors)
                            DropdownMenuItem(
                              value: f.id,
                              child: Text(
                                f.nameFor(widget.language),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) async {
                          refresh(() {
                            floorId = v;
                            areaId = null;
                            areas = [];
                          });
                          if (v != null) {
                            try {
                              final rows = await locations.listAreas(
                                floorId: v,
                              );
                              if (context.mounted) refresh(() => areas = rows);
                            } catch (_) {}
                          }
                        },
                      ),
                    if (floorId != null)
                      DropdownButtonFormField<String?>(
                        key: ValueKey('asset-area-$floorId-$areaId'),
                        initialValue: areaId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: t('Area', 'المساحة'),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text(t('All areas', 'كل المساحات')),
                          ),
                          for (final area in areas)
                            DropdownMenuItem(
                              value: area.id,
                              child: Text(
                                area.nameFor(widget.language),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) => refresh(() => areaId = v),
                      ),
                    DropdownButtonFormField<String>(
                      initialValue: criticality,
                      decoration: InputDecoration(
                        labelText: t('Criticality', 'درجة الأهمية'),
                      ),
                      items: [
                        for (final c in const [
                          'low',
                          'medium',
                          'high',
                          'critical',
                        ])
                          DropdownMenuItem(value: c, child: Text(c)),
                      ],
                      onChanged: (v) =>
                          refresh(() => criticality = v ?? criticality),
                    ),
                    TextFormField(
                      controller: notes,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: t('Notes', 'ملاحظات'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('Cancel', 'إلغاء')),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState?.validate() ?? false) {
                  Navigator.pop(context, true);
                }
              },
              child: Text(t('Save', 'حفظ')),
            ),
          ],
        ),
      ),
    );
    if (saved == true && mounted && organizationId != null) {
      await _perform(() async {
        await repository.saveAsset(
          organizationId: organizationId!,
          assetId: existing?.id,
          code: code.text,
          name: name.text,
          type: type.text,
          siteId: siteId,
          nameAr: arabic.text.isEmpty ? null : arabic.text,
          criticality: criticality,
          notes: notes.text.isEmpty ? null : notes.text,
          buildingId: buildingId,
          floorId: floorId,
          areaId: areaId,
        );
      });
    }
    code.dispose();
    name.dispose();
    arabic.dispose();
    type.dispose();
    notes.dispose();
  }

  Future<List<ChecklistAssignment>> _assignmentsForAsset(String assetId) async {
    final asset = assets.where((a) => a.id == assetId).firstOrNull;
    if (asset?.siteId == null || organizationId == null) return const [];
    final rows = await ref
        .read(supabaseClientProvider)
        .from('checklist_assignments')
        .select()
        .eq('organization_id', organizationId!)
        .eq('site_id', asset!.siteId!)
        .eq('is_active', true)
        .order('name_en');
    return [
      for (final row in rows)
        ChecklistAssignment.fromJson(Map<String, dynamic>.from(row)),
    ];
  }

  Future<void> _editPlan({String? preselectedAssetId}) async {
    if (assets.isEmpty) return;
    String assetId = preselectedAssetId ?? assets.first.id;
    String? assignmentId;
    List<ChecklistAssignment> assignments = [];
    try {
      assignments = await _assignmentsForAsset(assetId);
    } catch (_) {
      /* Existing checklist is optional. */
    }
    if (!mounted) return;
    String recipeCode = 'custom';
    String recurrence = 'monthly';
    int interval = 1;
    DateTime anchor = DateTime.now();
    final title = TextEditingController();
    final arabic = TextEditingController();
    final instructions = TextEditingController();
    final timezone = TextEditingController(text: 'UTC');
    final form = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: Text(t('New PPM schedule', 'خطة صيانة وقائية جديدة')),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: recipeCode,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: t(
                          'Starter plan (draft, editable)',
                          'نموذج خطة مبدئي غير معتمد (قابل للتعديل)',
                        ),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'custom',
                          child: Text(t('Custom plan', 'خطة مخصصة')),
                        ),
                        for (final recipe in fmPpmStarterRecipes)
                          DropdownMenuItem(
                            value: recipe.code,
                            child: Text(
                              t(recipe.titleEn, recipe.titleAr),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        refresh(() {
                          recipeCode = v;
                          final recipe = fmPpmStarterRecipes
                              .where((r) => r.code == v)
                              .firstOrNull;
                          if (recipe != null) {
                            title.text = recipe.titleEn;
                            arabic.text = recipe.titleAr;
                            recurrence = recipe.frequency;
                            instructions.text = recipe.instructions;
                          }
                        });
                      },
                    ),
                    DropdownButtonFormField<String>(
                      key: ValueKey('ppm-asset-$assetId'),
                      initialValue: assetId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: t('Asset', 'الأصل'),
                      ),
                      items: [
                        for (final a in assets)
                          DropdownMenuItem(
                            value: a.id,
                            child: Text(
                              '${a.code} · ${a.nameFor(widget.language)}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) async {
                        if (v == null) return;
                        refresh(() {
                          assetId = v;
                          assignmentId = null;
                          assignments = [];
                        });
                        try {
                          final rows = await _assignmentsForAsset(v);
                          if (context.mounted) {
                            refresh(() => assignments = rows);
                          }
                        } catch (_) {
                          /* Leave manual PPM without a form. */
                        }
                      },
                    ),
                    DropdownButtonFormField<String?>(
                      key: ValueKey('ppm-assignment-$assetId-$assignmentId'),
                      initialValue: assignmentId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: t(
                          'Linked A4 checklist (optional)',
                          'ربط قائمة فحص A4 (اختياري)',
                        ),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text(t('No linked checklist', 'دون ربط')),
                        ),
                        for (final a in assignments)
                          DropdownMenuItem(
                            value: a.id,
                            child: Text(
                              a.nameFor(widget.language),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => refresh(() => assignmentId = v),
                    ),
                    TextFormField(
                      controller: title,
                      decoration: InputDecoration(
                        labelText: t('Plan title', 'اسم الخطة'),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? t('Required', 'مطلوب')
                          : null,
                    ),
                    TextFormField(
                      controller: arabic,
                      decoration: InputDecoration(
                        labelText: t('Arabic title', 'اسم الخطة بالعربية'),
                      ),
                    ),
                    DropdownButtonFormField<String>(
                      key: ValueKey('ppm-frequency-$recurrence'),
                      initialValue: recurrence,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: t('Frequency', 'الدورية'),
                      ),
                      items: [
                        for (final v in const [
                          'daily',
                          'weekly',
                          'monthly',
                          'quarterly',
                          'biannual',
                          'annual',
                        ])
                          DropdownMenuItem(value: v, child: Text(v)),
                      ],
                      onChanged: (v) =>
                          refresh(() => recurrence = v ?? recurrence),
                    ),
                    DropdownButtonFormField<int>(
                      initialValue: interval,
                      decoration: InputDecoration(labelText: t('Every', 'كل')),
                      items: [
                        for (final n in const [1, 2, 3, 6, 12])
                          DropdownMenuItem(value: n, child: Text('$n')),
                      ],
                      onChanged: (v) => refresh(() => interval = v ?? interval),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(t('First due date', 'تاريخ الاستحقاق الأول')),
                      subtitle: Text(_date(anchor)),
                      trailing: const Icon(Icons.calendar_month),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: anchor,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) refresh(() => anchor = picked);
                      },
                    ),
                    TextFormField(
                      controller: timezone,
                      decoration: InputDecoration(
                        labelText: t(
                          'IANA timezone (e.g. Asia/Qatar)',
                          'المنطقة الزمنية (مثل Asia/Qatar)',
                        ),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? t('Timezone required', 'المنطقة الزمنية مطلوبة')
                          : null,
                    ),
                    TextFormField(
                      controller: instructions,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: t('Work instructions', 'تعليمات العمل'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('Cancel', 'إلغاء')),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState?.validate() ?? false) {
                  Navigator.pop(context, true);
                }
              },
              child: Text(t('Save plan', 'حفظ الخطة')),
            ),
          ],
        ),
      ),
    );
    if (saved == true && mounted && organizationId != null) {
      await _perform(() async {
        await repository.savePlan(
          organizationId: organizationId!,
          assetId: assetId,
          title: title.text,
          titleAr: arabic.text.isEmpty ? null : arabic.text,
          frequency: recurrence,
          every: interval,
          anchorDate: anchor,
          instructions: instructions.text,
          timezone: timezone.text,
          checklistAssignmentId: assignmentId,
        );
        // Prepare a bounded set of upcoming jobs.
        await repository.generateDueJobs(organizationId!, horizonDays: 45);
      });
    }
    title.dispose();
    arabic.dispose();
    instructions.dispose();
    timezone.dispose();
  }

  Future<void> _complete(FmPpmJob job) async {
    final notes = TextEditingController();
    final readings = TextEditingController(text: '{}');
    final inspection = TextEditingController();
    String? validation;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) => AlertDialog(
          title: Text(t('Complete maintenance', 'إغلاق أعمال الصيانة')),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_assetName(job.assetId)),
                  TextField(
                    controller: notes,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: t(
                        'Actual work & evidence notes',
                        'الأعمال المنفذة والملاحظات',
                      ),
                    ),
                  ),
                  TextField(
                    controller: readings,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: t('Readings (JSON)', 'القراءات (JSON)'),
                      hintText: '{"temperature_c":6.5}',
                    ),
                  ),
                  TextField(
                    controller: inspection,
                    decoration: InputDecoration(
                      labelText: t(
                        'Submitted inspection ID (optional)',
                        'معرّف فحص معتمد (اختياري)',
                      ),
                    ),
                  ),
                  if (validation != null)
                    Text(
                      validation!,
                      style: TextStyle(color: Theme.of(ctx).colorScheme.error),
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
              onPressed: () {
                if (notes.text.trim().length < 5) {
                  refresh(
                    () => validation = t(
                      'Add execution details',
                      'أدخل تفاصيل التنفيذ',
                    ),
                  );
                  return;
                }
                try {
                  if (jsonDecode(readings.text) is! Map) {
                    throw const FormatException('JSON object required');
                  }
                  refresh(() => validation = null);
                  Navigator.pop(ctx, true);
                } catch (_) {
                  refresh(
                    () => validation = t(
                      'Invalid JSON readings',
                      'صيغة القراءات غير صحيحة',
                    ),
                  );
                }
              },
              child: Text(t('Complete', 'إكمال')),
            ),
          ],
        ),
      ),
    );
    if (saved == true && mounted) {
      await _perform(
        () => repository.completeJob(
          job.id,
          notes: notes.text,
          readings: Map<String, dynamic>.from(jsonDecode(readings.text) as Map),
          inspectionId: inspection.text.trim().isEmpty
              ? null
              : inspection.text.trim(),
        ),
      );
    }
    notes.dispose();
    readings.dispose();
    inspection.dispose();
  }

  Future<void> _skip(FmPpmJob job) async {
    final notes = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Skip planned work', 'تجاوز عمل مجدول')),
        content: TextField(
          controller: notes,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: t('Required reason', 'سبب إلزامي'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('Cancel', 'إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, notes.text.trim().length >= 5),
            child: Text(t('Confirm', 'تأكيد')),
          ),
        ],
      ),
    );
    if (result == true) {
      await _perform(() => repository.skipJob(job.id, reason: notes.text));
    }
    notes.dispose();
  }

  Future<void> _assign(FmPpmJob job) async {
    if (organizationId == null || !canManage) return;
    try {
      final rows = await ref
          .read(supabaseClientProvider)
          .from('profiles')
          .select('id,full_name,email')
          .eq('home_organization_id', organizationId!)
          .eq('is_active', true)
          .eq('approval_status', 'approved')
          .order('full_name');
      if (!mounted) return;
      String? selected = job.assignedTo;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, update) => AlertDialog(
            title: Text(t('Assign technician', 'تعيين الفني')),
            content: SizedBox(
              width: 440,
              child: DropdownButtonFormField<String?>(
                key: ValueKey('ppm-worker-$selected'),
                initialValue: selected,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: t('Authorized person', 'المستخدم المصرح'),
                ),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(t('Unassigned', 'غير معيّن')),
                  ),
                  for (final row in rows)
                    DropdownMenuItem(
                      value: row['id'] as String,
                      child: Text(
                        (row['full_name'] ?? row['email'] ?? '').toString(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => update(() => selected = v),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(t('Cancel', 'إلغاء')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(t('Save assignment', 'حفظ التعيين')),
              ),
            ],
          ),
        ),
      );
      if (confirmed == true && mounted) {
        await _perform(() => repository.assignJob(job.id, selected));
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = checkAdminUserMessage(e, widget.language));
      }
    }
  }

  Future<void> _showEvents(FmPpmJob job) async {
    try {
      final events = await repository.listEvents(job.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('Maintenance history', 'سجل الصيانة')),
          content: SizedBox(
            width: 500,
            height: 350,
            child: ListView(
              children: [
                for (final e in events)
                  ListTile(
                    leading: const Icon(Icons.history),
                    title: Text(e.action),
                    subtitle: Text(
                      '${e.recordedAt.toLocal()}\n${e.notes ?? ''}',
                    ),
                    isThreeLine: e.notes != null,
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(t('Close', 'إغلاق')),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => error = checkAdminUserMessage(e, widget.language));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final org = organizationId;
    final tabLabel = [
      t('Assets', 'الأصول'),
      t('PPM plans', 'خطط PPM'),
      t('Work orders', 'أوامر العمل'),
    ];
    final overdue = jobs.where((j) => j.overdue).length;
    final complete = jobs.where((j) => j.status == 'completed').length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t(
                        'Assets & Preventive Maintenance',
                        'الأصول والصيانة الوقائية',
                      ),
                      style: Theme.of(context).textTheme.titleLarge,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: loading || busy ? null : _reload,
                    tooltip: t('Refresh', 'تحديث'),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              if (widget.profile.isPlatformOwner && organizations.isNotEmpty)
                DropdownButtonFormField<String>(
                  key: ValueKey('ppm-org-$org'),
                  initialValue: org,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: t('Organization', 'المؤسسة'),
                  ),
                  items: [
                    for (final o in organizations)
                      DropdownMenuItem(
                        value: o.id,
                        child: Text(
                          o.nameFor(widget.language),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => organizationId = v);
                      _reload();
                    }
                  },
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  Chip(
                    label: Text(
                      t('Assets: ${assets.length}', 'الأصول: ${assets.length}'),
                    ),
                  ),
                  Chip(
                    label: Text(
                      t('Scheduled: ${jobs.length}', 'المهام: ${jobs.length}'),
                    ),
                  ),
                  Chip(
                    label: Text(
                      t('Completed: $complete', 'المكتملة: $complete'),
                    ),
                  ),
                  Chip(
                    label: Text(t('Overdue: $overdue', 'المتأخرة: $overdue')),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: busy || !canManage || org == null
                          ? null
                          : () => _editAsset(),
                      icon: const Icon(Icons.add_box_outlined, size: 18),
                      label: Text(t('Add asset', 'إضافة أصل'), maxLines: 1),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: busy || !canManage || assets.isEmpty
                          ? null
                          : () => _editPlan(),
                      icon: const Icon(Icons.calendar_month, size: 18),
                      label: Text(t('New PPM', 'خطة PPM'), maxLines: 1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              FilledButton.icon(
                onPressed: busy || !canManage || org == null
                    ? null
                    : () => _perform(() async {
                        final n = await repository.generateDueJobs(org);
                        if (mounted) {
                          setState(
                            () => info = t(
                              'Generated $n work orders',
                              'تم إنشاء $n أمر عمل',
                            ),
                          );
                        }
                      }),
                icon: const Icon(Icons.event_repeat),
                label: Text(
                  t(
                    'Generate scheduled work (next 45 days)',
                    'إنشاء مهام الصيانة للأيام الـ45 القادمة',
                  ),
                ),
              ),
            ],
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (info != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              info!,
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          ),
        SizedBox(
          height: 46,
          child: Row(
            children: [
              for (var i = 0; i < 3; i++)
                Expanded(
                  child: TextButton(
                    onPressed: () => setState(() => selectedTab = i),
                    child: Text(
                      tabLabel[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: selectedTab == i
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 5, 12, 24),
              children: selectedTab == 0
                  ? [
                      for (final a in assets)
                        Card(
                          child: ListTile(
                            title: Text(
                              '${a.code} · ${a.nameFor(widget.language)}',
                            ),
                            subtitle: Text(
                              '${a.type} · ${a.criticality} · ${a.status}',
                            ),
                            trailing: canManage
                                ? PopupMenuButton<String>(
                                    onSelected: (v) {
                                      if (v == 'edit') _editAsset(existing: a);
                                      if (v == 'plan') {
                                        _editPlan(preselectedAssetId: a.id);
                                      }
                                    },
                                    itemBuilder: (_) => [
                                      PopupMenuItem(
                                        value: 'edit',
                                        child: Text(t('Edit', 'تعديل')),
                                      ),
                                      PopupMenuItem(
                                        value: 'plan',
                                        child: Text(
                                          t(
                                            'Create PPM plan',
                                            'إضافة خطة صيانة',
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : null,
                          ),
                        ),
                    ]
                  : selectedTab == 1
                  ? [
                      for (final p in plans)
                        Card(
                          child: ListTile(
                            title: Text(p.titleFor(widget.language)),
                            subtitle: Text(
                              '${_assetName(p.assetId)} · ${p.frequency} / ${p.intervalCount}\n'
                              '${t('Next due', 'الاستحقاق القادم')}: ${_date(p.nextDueOn)}',
                            ),
                            isThreeLine: true,
                            trailing: canManage
                                ? Switch.adaptive(
                                    value: p.isActive,
                                    onChanged: busy
                                        ? null
                                        : (active) => _perform(
                                            () => repository.setPlanActive(
                                              p.id,
                                              active,
                                            ),
                                          ),
                                  )
                                : Icon(
                                    p.isActive
                                        ? Icons.event_available
                                        : Icons.event_busy,
                                  ),
                          ),
                        ),
                    ]
                  : [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Wrap(
                          spacing: 5,
                          children: [
                            for (final s in const [
                              'all',
                              'scheduled',
                              'in_progress',
                              'completed',
                              'skipped',
                            ])
                              ChoiceChip(
                                label: Text(s),
                                selected: statusFilter == s,
                                onSelected: (_) =>
                                    setState(() => statusFilter = s),
                              ),
                          ],
                        ),
                      ),
                      for (final j in jobs.where(
                        (j) =>
                            statusFilter == 'all' || j.status == statusFilter,
                      ))
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _planName(j.planId),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                Text(
                                  '${_assetName(j.assetId)} · ${_date(j.dueOn)} · ${j.status}',
                                ),
                                if (j.executionNotes?.isNotEmpty ?? false)
                                  Text(j.executionNotes!),
                                if (j.assignedTo != null)
                                  Text(
                                    '${t('Assigned technician', 'الفني المعين')}: ${j.assignedTo!}',
                                  ),

                                Wrap(
                                  spacing: 5,
                                  children: [
                                    if (!j.closed && j.status == 'scheduled')
                                      TextButton.icon(
                                        onPressed: busy
                                            ? null
                                            : () => _perform(
                                                () => repository.startJob(j.id),
                                              ),
                                        icon: const Icon(
                                          Icons.play_arrow,
                                          size: 16,
                                        ),
                                        label: Text(t('Start', 'بدء')),
                                      ),
                                    if (!j.closed)
                                      TextButton.icon(
                                        onPressed: busy
                                            ? null
                                            : () => _complete(j),
                                        icon: const Icon(
                                          Icons.task_alt,
                                          size: 16,
                                        ),
                                        label: Text(t('Complete', 'إكمال')),
                                      ),
                                    if (!j.closed && canManage)
                                      TextButton.icon(
                                        onPressed: busy
                                            ? null
                                            : () => _assign(j),
                                        icon: const Icon(
                                          Icons.person_add_alt_1_outlined,
                                          size: 16,
                                        ),
                                        label: Text(t('Assign', 'تعيين')),
                                      ),
                                    if (!j.closed && canManage)
                                      TextButton(
                                        onPressed: busy ? null : () => _skip(j),
                                        child: Text(t('Skip', 'تجاوز')),
                                      ),
                                    TextButton.icon(
                                      onPressed: () => _showEvents(j),
                                      icon: const Icon(Icons.history, size: 16),
                                      label: Text(t('History', 'السجل')),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
            ),
          ),
        ),
      ],
    );
  }
}
