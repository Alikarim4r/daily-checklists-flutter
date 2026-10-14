part of '../main.dart';

/// P2 online + encrypted offline PPM execution for CheckIn.
class PpmJobsScreen extends ConsumerStatefulWidget {
  const PpmJobsScreen({
    super.key,
    required this.profile,
    required this.language,
  });
  final Profile profile;
  final String language;
  @override
  ConsumerState<PpmJobsScreen> createState() => _PpmJobsScreenState();
}

class _PpmJobsScreenState extends ConsumerState<PpmJobsScreen> {
  List<FmPpmJob> jobs = const [];
  List<FmAsset> assets = const [];
  List<FmPpmPlan> plans = const [];
  bool loading = false;
  bool busy = false;
  String? message;
  bool cached = false;
  String t(String en, String ar) => widget.language == 'ar' ? ar : en;
  OfflineInspectionQueue get outbox => OfflineInspectionQueue.instance;
  String? get orgId => widget.profile.homeOrganizationId;
  String assetName(String id) =>
      assets.where((a) => a.id == id).firstOrNull?.nameFor(widget.language) ??
      id;
  String planName(String id) =>
      plans.where((a) => a.id == id).firstOrNull?.titleFor(widget.language) ??
      id;

  @override
  void initState() {
    super.initState();
    _restoreCache();
    Future.microtask(_load);
  }

  void _restoreCache() {
    final source = outbox.cachedPpmJobs(widget.profile.id);
    if (source == null) return;
    try {
      final rights = outbox
          .cachedOfflineSiteAccess()
          .where(
            (a) =>
                a.userId == widget.profile.id &&
                a.canWrite &&
                a.isCurrentlyValid,
          )
          .map((a) => a.siteId)
          .toSet();
      final isAdmin =
          widget.profile.isPlatformOwner ||
          widget.profile.role == UserRole.superAdmin;
      final raw = source['jobs'] as List? ?? const [];
      jobs = [
        for (final value in raw)
          if (value is Map)
            if (FmPpmJob.fromJson(Map<String, dynamic>.from(value)) case final j
                when isAdmin || (j.siteId != null && rights.contains(j.siteId)))
              j,
      ];
      assets = [
        for (final value in source['assets'] as List? ?? const [])
          if (value is Map) FmAsset.fromJson(Map<String, dynamic>.from(value)),
      ];
      plans = [
        for (final value in source['plans'] as List? ?? const [])
          if (value is Map)
            FmPpmPlan.fromJson(Map<String, dynamic>.from(value)),
      ];
      cached = true;
    } catch (_) {
      /* Corrupted cache cannot block online access. */
    }
  }

  Future<void> _load() async {
    if (orgId == null) {
      setState(
        () => message = t(
          'Select an organization in CheckAdmin to manage PPM.',
          'حدد المؤسسة من CheckAdmin لإدارة PPM.',
        ),
      );
      return;
    }
    setState(() {
      loading = true;
      message = null;
    });
    try {
      final repo = ref.read(fmPpmRepositoryProvider);
      final rows = await Future.wait<Object>([
        repo.listJobs(orgId!),
        repo.listAssets(orgId!),
        repo.listPlans(orgId!),
      ]);
      if (!mounted) return;
      final fetchedJobs = rows[0] as List<FmPpmJob>;
      final fetchedAssets = rows[1] as List<FmAsset>;
      final fetchedPlans = rows[2] as List<FmPpmPlan>;
      setState(() {
        jobs = fetchedJobs;
        assets = fetchedAssets;
        plans = fetchedPlans;
        cached = false;
      });
      // Use the AES-encrypted box shared by CheckIn's existing offline cache.
      await outbox.cachePpmJobs(
        userId: widget.profile.id,
        jobs: [
          for (final j in jobs)
            {
              'id': j.id,
              'organization_id': j.organizationId,
              'plan_id': j.planId,
              'asset_id': j.assetId,
              'site_id': j.siteId,
              'due_on': j.dueOn.toIso8601String().substring(0, 10),
              'status': j.status,
              'is_overdue': j.isOverdueOnPlanTimezone,
              'execution_notes': j.executionNotes,
              'inspection_id': j.inspectionId,
            },
        ],
        assets: [
          for (final a in assets)
            {
              'id': a.id,
              'organization_id': a.organizationId,
              'asset_code': a.code,
              'name_en': a.nameEn,
              'name_ar': a.nameAr,
              'asset_type': a.type,
              'status': a.status,
              'criticality': a.criticality,
              'site_id': a.siteId,
            },
        ],
        plans: [
          for (final p in plans)
            {
              'id': p.id,
              'organization_id': p.organizationId,
              'asset_id': p.assetId,
              'title_en': p.titleEn,
              'title_ar': p.titleAr,
              'frequency': p.frequency,
              'timezone_id': p.timezone,
              'interval_count': p.intervalCount,
              'anchor_date': p.anchorDate.toIso8601String().substring(0, 10),
              'next_due_on': p.nextDueOn.toIso8601String().substring(0, 10),
              'is_active': p.isActive,
            },
        ],
      );
    } catch (e) {
      if (mounted) {
        setState(
          () => message = jobs.isEmpty
              ? checkInUserMessage(e, widget.language)
              : t(
                  'Showing encrypted offline work orders.',
                  'عرض مهام الصيانة المحفوظة دون اتصال.',
                ),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _complete(FmPpmJob job) async {
    final notes = TextEditingController();
    final reading = TextEditingController(text: '{}');
    final inspection = TextEditingController();
    String? validation;
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(t('Complete work order', 'إكمال أمر الصيانة')),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(planName(job.planId)),
                  TextField(
                    controller: notes,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: t(
                        'Actual work completed',
                        'الأعمال المنفذة فعليًا',
                      ),
                    ),
                  ),
                  TextField(
                    controller: inspection,
                    decoration: InputDecoration(
                      labelText: t(
                        'Submitted A4 inspection ID (optional)',
                        'معرّف فحص A4 المعتمد (اختياري)',
                      ),
                    ),
                  ),
                  TextField(
                    controller: reading,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: t('Readings as JSON', 'القراءات بصيغة JSON'),
                      hintText: '{"temperature_c":6.5}',
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
                  update(
                    () => validation = t(
                      'Enter work details',
                      'أدخل تفاصيل التنفيذ',
                    ),
                  );
                  return;
                }
                try {
                  if (jsonDecode(reading.text) is! Map) {
                    throw const FormatException();
                  }
                  Navigator.pop(ctx, true);
                } catch (_) {
                  update(
                    () => validation = t(
                      'Invalid readings JSON',
                      'صيغة القراءات غير صحيحة',
                    ),
                  );
                }
              },
              child: Text(t('Save completion', 'حفظ التنفيذ')),
            ),
          ],
        ),
      ),
    );
    if (save != true || !mounted) {
      notes.dispose();
      reading.dispose();
      inspection.dispose();
      return;
    }
    final note = notes.text.trim();
    final inspectionId = inspection.text.trim().isEmpty
        ? null
        : inspection.text.trim();
    final readings = Map<String, dynamic>.from(jsonDecode(reading.text) as Map);
    notes.dispose();
    reading.dispose();
    inspection.dispose();
    setState(() => busy = true);
    try {
      final backend = ref.read(supabaseClientProvider);
      final online =
          await _ensurePpmSession(ref) &&
          await ChecklistConnectivity.canReachBackend(backend);
      if (online) {
        await ref
            .read(fmPpmRepositoryProvider)
            .completeJob(
              job.id,
              notes: note,
              readings: readings,
              inspectionId: inspectionId,
            );
        await outbox.removePpmIfQueued(widget.profile.id, job.id);
        if (mounted) await _load();
      } else {
        await outbox.enqueuePpmCompletion(
          userId: widget.profile.id,
          jobId: job.id,
          notes: note,
          readings: readings,
          inspectionId: inspectionId,
        );
        if (mounted) {
          setState(
            () => message = t(
              'Completion saved in encrypted offline queue. It will sync when online.',
              'حُفظ التنفيذ مشفّرًا دون اتصال وسيُزامن عند عودة الإنترنت.',
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => message = checkInUserMessage(e, widget.language));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = outbox
        .pendingPpm(widget.profile.id)
        .map((entry) => entry.value['jobId'])
        .toSet();
    return Scaffold(
      appBar: AppBar(
        title: Text(t('PPM Work Orders', 'أوامر الصيانة الوقائية')),
        actions: [
          IconButton(
            onPressed: loading ? null : _load,
            tooltip: t('Refresh', 'تحديث'),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (loading) const LinearProgressIndicator(minHeight: 3),
          if (cached)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(t('Offline cached tasks', 'مهام مخزنة دون اتصال')),
            ),
          if (pending.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                t(
                  '${pending.length} work orders awaiting sync',
                  '${pending.length} أمر صيانة بانتظار المزامنة',
                ),
              ),
            ),
          if (message != null)
            Padding(padding: const EdgeInsets.all(8), child: Text(message!)),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  for (final job in jobs.where((j) => !j.closed))
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              planName(job.planId),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 5),
                            Text(assetName(job.assetId)),
                            Text(
                              '${job.dueOn.year}-${job.dueOn.month}-${job.dueOn.day}  ·  ${job.status}',
                            ),
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: FilledButton.icon(
                                onPressed: busy || pending.contains(job.id)
                                    ? null
                                    : () => _complete(job),
                                icon: Icon(
                                  pending.contains(job.id)
                                      ? Icons.cloud_upload_outlined
                                      : Icons.task_alt,
                                ),
                                label: Text(
                                  pending.contains(job.id)
                                      ? t('Awaiting sync', 'بانتظار المزامنة')
                                      : t('Record completion', 'تسجيل التنفيذ'),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (jobs.where((j) => !j.closed).isEmpty)
                    ListTile(
                      title: Text(
                        t(
                          'No open PPM work orders',
                          'لا توجد مهام صيانة مفتوحة',
                        ),
                      ),
                      subtitle: Text(
                        t('Refresh when connected.', 'حدّث عند الاتصال.'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
