import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/checkadmin_errors.dart';
import 'technical_payload_form.dart';

/// P3 A+B+C — multi-tenant technical document lifecycle, approvals and HSE workflows.
class TechnicalDocumentsTab extends ConsumerStatefulWidget {
  const TechnicalDocumentsTab({
    super.key,
    required this.profile,
    required this.language,
  });
  final Profile profile;
  final String language;
  @override
  ConsumerState<TechnicalDocumentsTab> createState() =>
      _TechnicalDocumentsTabState();
}

class _TechnicalDocumentsTabState extends ConsumerState<TechnicalDocumentsTab> {
  List<Organization> organizations = [];
  List<ChecklistSite> sites = [];
  List<FmAsset> assets = [];
  List<FmPpmJob> workOrders = [];
  List<TechnicalDocument> documents = [];
  String? orgId;
  String kind = 'all', status = 'all', query = '';
  bool busy = false, loading = true;
  String? error, success;
  int request = 0;
  bool get ar => widget.language == 'ar';
  bool get manager =>
      widget.profile.isPlatformOwner ||
      widget.profile.role == UserRole.superAdmin;
  String t(String en, String arValue) => ar ? arValue : en;
  TechnicalDocumentsRepository get repo =>
      ref.read(technicalDocumentsRepositoryProvider);

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
      setState(() {
        organizations = widget.profile.isPlatformOwner
            ? orgs
            : orgs
                  .where((org) => org.id == widget.profile.homeOrganizationId)
                  .toList();
        orgId = widget.profile.isPlatformOwner
            ? organizations.firstOrNull?.id
            : widget.profile.homeOrganizationId;
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
    final org = orgId;
    if (org == null) {
      if (mounted) setState(() => loading = false);
      return;
    }
    final marker = ++request;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final rows = await Future.wait<Object>([
        repo.listDocuments(org),
        ref.read(fmPpmRepositoryProvider).listAssets(org),
        ref.read(fmPpmRepositoryProvider).listJobs(org),
        ref.read(siteRepositoryProvider).listCampusSites(activeOnly: true),
      ]);
      if (!mounted || marker != request) return;
      setState(() {
        documents = rows[0] as List<TechnicalDocument>;
        assets = rows[1] as List<FmAsset>;
        workOrders = rows[2] as List<FmPpmJob>;
        sites = (rows[3] as List<ChecklistSite>)
            .where((s) => s.organizationId == org)
            .toList();
      });
    } catch (e) {
      if (mounted && marker == request) {
        setState(() => error = checkAdminUserMessage(e, widget.language));
      }
    } finally {
      if (mounted && marker == request) setState(() => loading = false);
    }
  }

  Future<void> _action(Future<void> Function() operation) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      success = null;
    });
    try {
      await operation();
      if (mounted) {
        await _reload();
        if (mounted) {
          setState(
            () => success = t(
              'Changes saved successfully',
              'تم حفظ التغييرات بنجاح',
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = checkAdminUserMessage(e, widget.language));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  List<TechnicalDocument> get filtered => documents.where((doc) {
    if (kind != 'all' && doc.kind != kind) return false;
    if (status != 'all' && doc.status != status) return false;
    final term = query.trim().toLowerCase();
    if (term.isEmpty) return true;
    return '${doc.title} ${doc.code} ${doc.labelFor(widget.language)}'
        .toLowerCase()
        .contains(term);
  }).toList();

  String _statusLabel(String value) => switch (value) {
    'draft' => t('Draft', 'مسودة'),
    'in_review' => t('In review', 'قيد المراجعة'),
    'approved' => t('Approved', 'معتمد'),
    'rejected' => t('Returned', 'أُعيد للتصحيح'),
    'superseded' => t('Superseded', 'مستبدل'),
    _ => value,
  };

  Future<String?> _textPrompt(
    String title,
    String hint, {
    String initial = '',
    int minLength = 0,
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: hint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('Cancel', 'إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(t('Confirm', 'تأكيد')),
          ),
        ],
      ),
    );
    controller.dispose();
    return result == null || result.length < minLength ? null : result;
  }

  Future<void> _create() async {
    if (!manager || orgId == null) return;
    final code = TextEditingController();
    final title = TextEditingController();
    final standard = TextEditingController();
    final edition = TextEditingController();
    String docKind = 'method_statement';
    String? siteId, assetId, jobId;
    final form = GlobalKey<FormState>();
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(t('New technical document', 'مستند فني جديد')),
          content: SizedBox(
            width: 490,
            child: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: docKind,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: t('Document type', 'نوع المستند'),
                      ),
                      items: [
                        for (final entry in technicalDocumentKinds.entries)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text(
                              ar
                                  ? technicalDocumentKindsAr[entry.key] ??
                                        entry.value
                                  : entry.value,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) update(() => docKind = value);
                      },
                    ),
                    TextFormField(
                      controller: code,
                      decoration: InputDecoration(
                        labelText: t('Document reference', 'رقم المستند'),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? t('Required', 'مطلوب')
                          : null,
                    ),
                    TextFormField(
                      controller: title,
                      decoration: InputDecoration(
                        labelText: t('Document title', 'عنوان المستند'),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? t('Required', 'مطلوب')
                          : null,
                    ),
                    DropdownButtonFormField<String?>(
                      key: ValueKey('doc-site-$siteId'),
                      initialValue: siteId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: t('Site (optional)', 'الموقع (اختياري)'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text(
                            t('Organization-wide', 'على مستوى المؤسسة'),
                          ),
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
                      onChanged: (value) => update(() {
                        siteId = value;
                        assetId = null;
                        jobId = null;
                      }),
                    ),
                    DropdownButtonFormField<String?>(
                      key: ValueKey('doc-asset-$siteId-$assetId'),
                      initialValue: assetId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: t('Asset (optional)', 'الأصل (اختياري)'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text(t('No asset', 'دون أصل')),
                        ),
                        for (final a in assets.where(
                          (a) => siteId == null || a.siteId == siteId,
                        ))
                          DropdownMenuItem(
                            value: a.id,
                            child: Text(
                              '${a.code} · ${a.nameFor(widget.language)}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) => update(() {
                        assetId = value;
                        jobId = null;
                      }),
                    ),
                    DropdownButtonFormField<String?>(
                      key: ValueKey('doc-job-$assetId-$jobId'),
                      initialValue: jobId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: t(
                          'PPM work order (optional)',
                          'أمر صيانة (اختياري)',
                        ),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text(t('No work order', 'دون أمر عمل')),
                        ),
                        for (final job in workOrders.where(
                          (j) => assetId == null || j.assetId == assetId,
                        ))
                          DropdownMenuItem(
                            value: job.id,
                            child: Text(
                              '${job.id.substring(0, 8)} · ${job.dueOn.toIso8601String().substring(0, 10)}',
                            ),
                          ),
                      ],
                      onChanged: (value) => update(() => jobId = value),
                    ),
                    TextFormField(
                      controller: standard,
                      decoration: InputDecoration(
                        labelText: t(
                          'Standard reference (optional)',
                          'المرجع المعياري (اختياري)',
                        ),
                      ),
                    ),
                    TextFormField(
                      controller: edition,
                      decoration: InputDecoration(
                        labelText: t(
                          'Standard edition (optional)',
                          'إصدار المرجع (اختياري)',
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        t(
                          'Templates are drafts until reviewed by an authorized person.',
                          'النماذج مسودات حتى يراجعها ويعتمدها شخص مخوّل.',
                        ),
                      ),
                    ),
                  ],
                ),
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
                if (form.currentState?.validate() ?? false) {
                  Navigator.pop(ctx, true);
                }
              },
              child: Text(t('Create draft', 'إنشاء المسودة')),
            ),
          ],
        ),
      ),
    );
    if (created == true && mounted) {
      String? newId;
      await _action(() async {
        newId = await repo.create(
          organizationId: orgId!,
          kind: docKind,
          code: code.text,
          title: title.text,
          siteId: siteId,
          assetId: assetId,
          ppmJobId: jobId,
          standard: standard.text.trim().isEmpty ? null : standard.text.trim(),
          edition: edition.text.trim().isEmpty ? null : edition.text.trim(),
          language: widget.language,
        );
      });
      if (newId != null && mounted) await _editVersion(newId!, docKind);
    }
    code.dispose();
    title.dispose();
    standard.dispose();
    edition.dispose();
  }

  Future<void> _editVersion(String docId, String docKind) async {
    Map<String, dynamic> initial = {};
    try {
      final revisions = await repo.versions(docId);
      if (revisions.isNotEmpty) initial = revisions.first.payload;
    } catch (e) {
      if (mounted) {
        setState(() => error = checkAdminUserMessage(e, widget.language));
      }
      return;
    }
    if (!mounted) return;
    Map<String, dynamic> content = Map.of(initial);
    final note = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Edit document content', 'تحرير محتوى المستند')),
        content: SizedBox(
          width: 720,
          height: MediaQuery.sizeOf(ctx).height * .58,
          child: Column(
            children: [
              Expanded(
                child: TechnicalPayloadForm(
                  kind: docKind,
                  initial: initial,
                  language: widget.language,
                  onChanged: (value) => content = value,
                ),
              ),
              TextField(
                controller: note,
                decoration: InputDecoration(
                  labelText: t('Version change note', 'وصف تغيير الإصدار'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('Cancel', 'إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('Save new version', 'حفظ إصدار جديد')),
          ),
        ],
      ),
    );
    if (saved == true && mounted) {
      await _action(() async {
        await repo.saveVersion(docId, content, changeNote: note.text);
      });
    }
    note.dispose();
  }

  Future<void> _review(TechnicalDocument doc, bool approve) async {
    final note = await _textPrompt(
      approve
          ? t('Approve document', 'اعتماد المستند')
          : t('Return document for correction', 'إرجاع المستند للتصحيح'),
      t('Review remarks', 'ملاحظات المراجع'),
      minLength: approve ? 0 : 5,
    );
    if (note == null) return;
    await _action(() => repo.decide(doc.id, approve: approve, remarks: note));
  }

  Future<void> _link(TechnicalDocument doc) async {
    final targets = documents
        .where(
          (x) =>
              x.id != doc.id &&
              (doc.kind != 'ptw' ||
                  x.kind == 'risk_assessment' ||
                  x.kind == 'jsa'),
        )
        .toList();
    if (targets.isEmpty) {
      setState(
        () => error = t(
          'No documents available to link',
          'لا توجد مستندات متاحة للربط',
        ),
      );
      return;
    }
    String selected = targets.first.id;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(t('Link related document', 'ربط مستند ذي صلة')),
          content: SizedBox(
            width: 480,
            child: DropdownButtonFormField<String>(
              initialValue: selected,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: t('Related document', 'المستند المرتبط'),
              ),
              items: [
                for (final x in targets)
                  DropdownMenuItem(
                    value: x.id,
                    child: Text(
                      '${x.code} — ${x.title}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v != null) update(() => selected = v);
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('Cancel', 'إلغاء')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t('Link', 'ربط')),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && mounted) {
      await _action(
        () => repo.link(
          doc.id,
          selected,
          relation: doc.kind == 'ptw' ? 'risk_assessment' : 'related',
        ),
      );
    }
  }

  Future<void> _supersede(TechnicalDocument old) async {
    final replacements = documents
        .where((x) => x.id != old.id && x.kind == old.kind && x.isApproved)
        .toList();
    if (replacements.isEmpty) {
      setState(
        () => error = t(
          'Approve a replacement document first.',
          'يجب اعتماد المستند البديل أولًا.',
        ),
      );
      return;
    }
    String selected = replacements.first.id;
    final note = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(
            t('Supersede approved version', 'استبدال المستند المعتمد'),
          ),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: t('Approved replacement', 'البديل المعتمد'),
                  ),
                  items: [
                    for (final doc in replacements)
                      DropdownMenuItem(
                        value: doc.id,
                        child: Text(
                          '${doc.code} · ${doc.title}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) update(() => selected = v);
                  },
                ),
                TextField(
                  controller: note,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: t('Reason for supersession', 'سبب الاستبدال'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('Cancel', 'إلغاء')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, note.text.trim().length >= 5),
              child: Text(t('Supersede', 'استبدال')),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && mounted) {
      await _action(() => repo.supersede(old.id, selected, note.text));
    }
    note.dispose();
  }

  Future<void> _issuePermit(TechnicalDocument doc) async {
    final candidates = documents
        .where(
          (x) =>
              x.isApproved && (x.kind == 'risk_assessment' || x.kind == 'jsa'),
        )
        .toList();
    if (candidates.isEmpty) {
      setState(
        () => error = t(
          'An approved risk assessment is required first.',
          'يجب اعتماد تقييم مخاطر أولًا.',
        ),
      );
      return;
    }
    String selected = candidates.first.id;
    int hours = 8;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(
            t('Issue controlled work permit', 'إصدار تصريح عمل مضبوط'),
          ),
          content: SizedBox(
            width: 490,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t(
                    'Permits require an approved linked risk assessment.',
                    'يشترط تقييم مخاطر معتمد ومرتبط بالتصريح.',
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: t(
                      'Approved risk assessment',
                      'تقييم المخاطر المعتمد',
                    ),
                  ),
                  items: [
                    for (final x in candidates)
                      DropdownMenuItem(
                        value: x.id,
                        child: Text(
                          '${x.code} · ${x.title}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) update(() => selected = v);
                  },
                ),
                DropdownButtonFormField<int>(
                  initialValue: hours,
                  decoration: InputDecoration(
                    labelText: t(
                      'Permit duration (hours)',
                      'مدة التصريح بالساعات',
                    ),
                  ),
                  items: [
                    for (final h in const [1, 2, 4, 8, 12, 24])
                      DropdownMenuItem(value: h, child: Text('$h')),
                  ],
                  onChanged: (v) {
                    if (v != null) update(() => hours = v);
                  },
                ),
                Text(
                  t(
                    'Work begins at issuance, expires automatically at end of period.',
                    'يبدأ عند الإصدار وتنتهي الصلاحية تلقائيًا بانتهاء المدة.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('Cancel', 'إلغاء')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t('Issue permit', 'إصدار التصريح')),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && mounted) {
      await _action(() async {
        await repo.link(doc.id, selected, relation: 'risk_assessment');
        final start = DateTime.now();
        await repo.issuePermit(
          ptwId: doc.id,
          raId: selected,
          from: start,
          until: start.add(Duration(hours: hours)),
        );
      });
    }
  }

  Future<void> _transitionPermit(
    Map<String, dynamic> permit,
    String action,
  ) async {
    String? note;
    if (action == 'closed') {
      note = await _textPrompt(
        t('Close work permit', 'إغلاق تصريح العمل'),
        t('Closure reason / confirmation', 'سبب الإغلاق / التأكيد'),
        minLength: 5,
      );
      if (note == null) return;
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('Confirm permit status', 'تأكيد تغيير حالة التصريح')),
          content: Text(action),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('Cancel', 'إلغاء')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t('Confirm', 'تأكيد')),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      note = action;
    }
    if (mounted) {
      await _action(
        () => repo.transitionPermit(permit['id'] as String, action, note: note),
      );
    }
  }

  Future<void> _signItp(TechnicalDocument doc) async {
    final rows = await Future.wait<Object>([
      repo.versions(doc.id),
      repo.itpResults(doc.id),
    ]);
    if (!mounted) return;
    final versions = rows[0] as List<TechnicalVersion>;
    final done = rows[1] as List<Map<String, dynamic>>;
    if (versions.isEmpty) return;
    final check = versions.first.payload['checkpoints'];
    if (check is! List) return;
    final signed = done.map((r) => r['checkpoint_id']).toSet();
    final open = [
      for (final c in check)
        if (c is Map && !signed.contains(c['id'])) Map<String, dynamic>.from(c),
    ];
    if (open.isEmpty) {
      setState(
        () => error = t('All checkpoints signed', 'تم توقيع جميع النقاط'),
      );
      return;
    }
    String point = open.first['id'] as String;
    String result = 'pass';
    final note = TextEditingController();
    final inspection = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(t('Sign ITP checkpoint', 'توقيع نقطة فحص ITP')),
          content: SizedBox(
            width: 490,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: point,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: t('Checkpoint', 'نقطة الفحص'),
                  ),
                  items: [
                    for (final c in open)
                      DropdownMenuItem(
                        value: c['id'] as String,
                        child: Text(
                          '${c['id']} · ${c['description']}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) update(() => point = v);
                  },
                ),
                DropdownButtonFormField<String>(
                  initialValue: result,
                  decoration: InputDecoration(
                    labelText: t('Result', 'النتيجة'),
                  ),
                  items: [
                    for (final v in const ['pass', 'fail'])
                      DropdownMenuItem(value: v, child: Text(v)),
                  ],
                  onChanged: (v) {
                    if (v != null) update(() => result = v);
                  },
                ),
                TextField(
                  controller: note,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: t(
                      'Signed evidence notes',
                      'ملاحظات الأدلة الموقعة',
                    ),
                  ),
                ),
                TextField(
                  controller: inspection,
                  decoration: InputDecoration(
                    labelText: t(
                      'Submitted A4 inspection ID (optional)',
                      'رقم فحص A4 المعتمد (اختياري)',
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('Cancel', 'إلغاء')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, note.text.trim().length >= 5),
              child: Text(t('Sign', 'توقيع')),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && mounted) {
      await _action(() async {
        await repo.signItp(
          docId: doc.id,
          checkpoint: point,
          result: result,
          evidenceNote: note.text,
          inspectionId: inspection.text.trim().isEmpty
              ? null
              : inspection.text.trim(),
        );
      });
    }
    note.dispose();
    inspection.dispose();
  }

  Future<void> _closeNcr(TechnicalDocument doc) async {
    String disposition = 'corrected';
    final note = TextEditingController();
    final inspection = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(
            t(
              'Close NCR with independent verification',
              'إغلاق NCR بتحقق مستقل',
            ),
          ),
          content: SizedBox(
            width: 490,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: disposition,
                  decoration: InputDecoration(
                    labelText: t('Disposition', 'التصرف'),
                  ),
                  items: [
                    for (final v in const [
                      'corrected',
                      'accepted_deviation',
                      'rework',
                    ])
                      DropdownMenuItem(value: v, child: Text(v)),
                  ],
                  onChanged: (v) {
                    if (v != null) update(() => disposition = v);
                  },
                ),
                TextField(
                  controller: note,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: t('Verification details', 'تفاصيل التحقق'),
                  ),
                ),
                TextField(
                  controller: inspection,
                  decoration: InputDecoration(
                    labelText: t(
                      'Submitted inspection ID (optional)',
                      'رقم فحص معتمد (اختياري)',
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('Cancel', 'إلغاء')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, note.text.trim().length >= 5),
              child: Text(t('Verify & close', 'التحقق والإغلاق')),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && mounted) {
      await _action(() async {
        await repo.closeNcr(
          docId: doc.id,
          disposition: disposition,
          verification: note.text,
          inspectionId: inspection.text.trim().isEmpty
              ? null
              : inspection.text.trim(),
        );
      });
    }
    note.dispose();
    inspection.dispose();
  }

  Widget _payloadDisplay(Map<String, dynamic> payload) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in payload.entries)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.key.replaceAll('_', ' ').toUpperCase(),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 5),
                  if (entry.value is List)
                    for (final item in entry.value as List)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Text(
                          item is Map
                              ? item.entries
                                    .map((e) => '${e.key}: ${e.value}')
                                    .join(' · ')
                              : '• $item',
                        ),
                      )
                  else
                    Text('${entry.value}'),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _details(TechnicalDocument doc) async {
    try {
      final rows = await Future.wait<Object>([
        repo.versions(doc.id),
        repo.decisions(doc.id),
        repo.links(doc.id),
        if (doc.kind == 'ptw') repo.permits(doc.organizationId),
        if (doc.kind == 'itp') repo.itpResults(doc.id),
        if (doc.kind == 'ncr') repo.ncrClosures(doc.id),
      ]);
      if (!mounted) return;
      final versions = rows[0] as List<TechnicalVersion>;
      final decisions = rows[1] as List<TechnicalDecision>;
      final links = rows[2] as List<Map<String, dynamic>>;
      int index = 0;
      final permits = doc.kind == 'ptw'
          ? (rows[3] as List<Map<String, dynamic>>)
                .where((p) => p['document_id'] == doc.id)
                .toList()
          : <Map<String, dynamic>>[];
      final extra = doc.kind == 'itp' || doc.kind == 'ncr'
          ? rows[3] as List<Map<String, dynamic>>
          : <Map<String, dynamic>>[];
      await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, update) => AlertDialog(
            title: Text('${doc.code} · ${doc.title}', maxLines: 2),
            content: SizedBox(
              width: 720,
              height: MediaQuery.sizeOf(ctx).height * .67,
              child: ListView(
                children: [
                  Text(
                    '${doc.labelFor(widget.language)} · ${_statusLabel(doc.status)}',
                  ),
                  const SizedBox(height: 8),
                  if (versions.isNotEmpty)
                    DropdownButtonFormField<int>(
                      initialValue: index,
                      decoration: InputDecoration(
                        labelText: t('Document version', 'إصدار المستند'),
                      ),
                      items: [
                        for (int i = 0; i < versions.length; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text(
                              'v${versions[i].versionNo} — ${versions[i].changeNote}',
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) update(() => index = v);
                      },
                    ),
                  if (versions.isNotEmpty)
                    _payloadDisplay(versions[index].payload),
                  if (links.isNotEmpty) ...[
                    Text(
                      t('Related documents', 'المستندات المرتبطة'),
                      style: Theme.of(ctx).textTheme.titleSmall,
                    ),
                    for (final link in links)
                      ListTile(
                        dense: true,
                        title: Text(
                          '${link['relationship']} · ${link['target_id']}',
                        ),
                      ),
                  ],
                  if (permits.isNotEmpty) ...[
                    Text(
                      t('Work permit control', 'التحكم بتصريح العمل'),
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                    for (final p in permits)
                      Card(
                        child: Column(
                          children: [
                            ListTile(
                              title: Text(
                                '${p['state']} · ${p['valid_until']}',
                              ),
                              subtitle: Text('${p['valid_from']}'),
                            ),
                            if (manager && p['state'] != 'closed')
                              Wrap(
                                spacing: 8,
                                children: [
                                  if (p['state'] == 'active')
                                    TextButton(
                                      onPressed: () {
                                        Navigator.pop(ctx);
                                        _transitionPermit(p, 'suspended');
                                      },
                                      child: Text(t('Suspend', 'إيقاف')),
                                    ),
                                  if (p['state'] == 'suspended')
                                    TextButton(
                                      onPressed: () {
                                        Navigator.pop(ctx);
                                        _transitionPermit(p, 'resumed');
                                      },
                                      child: Text(t('Resume', 'استئناف')),
                                    ),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      _transitionPermit(p, 'closed');
                                    },
                                    child: Text(
                                      t('Close permit', 'إغلاق التصريح'),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                  ],
                  if (extra.isNotEmpty) ...[
                    Text(
                      t('Recorded evidence', 'الأدلة المسجلة'),
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                    for (final row in extra)
                      ListTile(
                        title: Text(
                          doc.kind == 'itp'
                              ? '${row['checkpoint_id']} — ${row['result']}'
                              : '${row['disposition']}',
                        ),
                        subtitle: Text(
                          '${row['evidence_note'] ?? row['verified_notes'] ?? ''}',
                        ),
                      ),
                  ],
                  if (decisions.isNotEmpty) ...[
                    Text(
                      t('Approval history', 'تاريخ الاعتمادات'),
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                    for (final decision in decisions)
                      ListTile(
                        leading: const Icon(Icons.history),
                        title: Text(
                          '${decision.decision} · v${decision.version}',
                        ),
                        subtitle: Text(
                          '${decision.createdAt.toLocal()} · ${decision.remarks ?? ''}',
                        ),
                      ),
                  ],
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
    final approved = documents.where((d) => d.status == 'approved').length;
    final pending = documents.where((d) => d.status == 'in_review').length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t(
                        'Global Technical Documentation',
                        'إدارة المستندات الفنية العالمية',
                      ),
                      style: Theme.of(context).textTheme.titleLarge,
                      maxLines: 2,
                    ),
                  ),
                  IconButton(
                    onPressed: busy || loading ? null : _reload,
                    tooltip: t('Refresh', 'تحديث'),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              if (widget.profile.isPlatformOwner && organizations.isNotEmpty)
                DropdownButtonFormField<String>(
                  key: ValueKey('technical-org-$orgId'),
                  initialValue: orgId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: t('Organization', 'المؤسسة'),
                  ),
                  items: [
                    for (final org in organizations)
                      DropdownMenuItem(
                        value: org.id,
                        child: Text(
                          org.nameFor(widget.language),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => orgId = v);
                      _reload();
                    }
                  },
                ),
              Wrap(
                spacing: 7,
                children: [
                  Chip(
                    label: Text(
                      t(
                        'Documents: ${documents.length}',
                        'المستندات: ${documents.length}',
                      ),
                    ),
                  ),
                  Chip(
                    label: Text(
                      t(
                        'Awaiting review: $pending',
                        'بانتظار المراجعة: $pending',
                      ),
                    ),
                  ),
                  Chip(
                    label: Text(
                      t('Approved: $approved', 'المعتمدة: $approved'),
                    ),
                  ),
                ],
              ),
              if (manager)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FilledButton.icon(
                    onPressed: busy || orgId == null ? null : _create,
                    icon: const Icon(Icons.note_add_outlined),
                    label: Text(
                      t('Create technical document', 'إنشاء مستند فني'),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (ctx, layout) {
                  final fields = <Widget>[
                    DropdownButtonFormField<String>(
                      key: ValueKey('technical-kind-$kind'),
                      initialValue: kind,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: t('Document type', 'نوع المستند'),
                        isDense: true,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'all',
                          child: Text(t('All types', 'كل الأنواع')),
                        ),
                        for (final entry in technicalDocumentKinds.entries)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text(
                              ar
                                  ? technicalDocumentKindsAr[entry.key] ??
                                        entry.value
                                  : entry.value,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => kind = v);
                      },
                    ),
                    DropdownButtonFormField<String>(
                      key: ValueKey('technical-status-$status'),
                      initialValue: status,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: t('Approval status', 'حالة الاعتماد'),
                        isDense: true,
                      ),
                      items: [
                        for (final v in const [
                          'all',
                          'draft',
                          'in_review',
                          'approved',
                          'rejected',
                        ])
                          DropdownMenuItem(
                            value: v,
                            child: Text(
                              v == 'all'
                                  ? t('All statuses', 'كل الحالات')
                                  : _statusLabel(v),
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => status = v);
                      },
                    ),
                    TextField(
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: t(
                          'Search code or title',
                          'ابحث برقم أو عنوان المستند',
                        ),
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => query = v),
                    ),
                  ];
                  if (layout.maxWidth < 620) {
                    return Column(
                      children: [
                        for (final field in fields)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: field,
                          ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      for (final field in fields)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsetsDirectional.only(end: 8),
                            child: field,
                          ),
                        ),
                    ],
                  );
                },
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (success != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    success!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              if (loading) const LinearProgressIndicator(minHeight: 2),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 22),
              children: [
                if (!loading && filtered.isEmpty)
                  ListTile(
                    title: Text(
                      t('No matching documents', 'لا توجد مستندات مطابقة'),
                    ),
                    subtitle: Text(
                      t(
                        'Create a document to start the review workflow.',
                        'أنشئ مستندًا لبدء مسار المراجعة.',
                      ),
                    ),
                  ),
                for (final doc in filtered)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${doc.code}  ·  ${doc.title}',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                doc.status == 'approved'
                                    ? Icons.verified_outlined
                                    : doc.status == 'in_review'
                                    ? Icons.hourglass_top
                                    : Icons.edit_document,
                                size: 20,
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${doc.labelFor(widget.language)} · ${_statusLabel(doc.status)} · v${doc.currentVersion}',
                          ),
                          Wrap(
                            spacing: 4,
                            runSpacing: 3,
                            children: [
                              TextButton.icon(
                                onPressed: () => _details(doc),
                                icon: const Icon(
                                  Icons.visibility_outlined,
                                  size: 17,
                                ),
                                label: Text(
                                  t('View history', 'عرض المستند والسجل'),
                                ),
                              ),
                              if (manager && doc.isEditable)
                                TextButton.icon(
                                  onPressed: busy
                                      ? null
                                      : () => _editVersion(doc.id, doc.kind),
                                  icon: const Icon(Icons.edit_note, size: 17),
                                  label: Text(
                                    t('Edit revision', 'تعديل الإصدار'),
                                  ),
                                ),
                              if (manager &&
                                  doc.isEditable &&
                                  doc.currentVersion > 0)
                                TextButton(
                                  onPressed: busy
                                      ? null
                                      : () =>
                                            _action(() => repo.submit(doc.id)),
                                  child: Text(
                                    t('Submit review', 'إرسال للمراجعة'),
                                  ),
                                ),
                              if (manager &&
                                  doc.status == 'in_review' &&
                                  doc.createdBy != widget.profile.id) ...[
                                TextButton.icon(
                                  onPressed: busy
                                      ? null
                                      : () => _review(doc, true),
                                  icon: const Icon(
                                    Icons.check_circle_outline,
                                    size: 17,
                                  ),
                                  label: Text(t('Approve', 'اعتماد')),
                                ),
                                TextButton(
                                  onPressed: busy
                                      ? null
                                      : () => _review(doc, false),
                                  child: Text(t('Return', 'إرجاع')),
                                ),
                              ],
                              if (manager)
                                TextButton(
                                  onPressed: busy ? null : () => _link(doc),
                                  child: Text(t('Link', 'ربط')),
                                ),
                              if (manager && doc.isApproved)
                                TextButton(
                                  onPressed: busy
                                      ? null
                                      : () => _supersede(doc),
                                  child: Text(t('Supersede', 'استبدال')),
                                ),
                              if (manager &&
                                  doc.isApproved &&
                                  doc.kind == 'ptw')
                                TextButton(
                                  onPressed: busy
                                      ? null
                                      : () => _issuePermit(doc),
                                  child: Text(t('Issue PTW', 'إصدار تصريح')),
                                ),
                              if (doc.isApproved && doc.kind == 'itp')
                                TextButton(
                                  onPressed: busy ? null : () => _signItp(doc),
                                  child: Text(t('Sign ITP', 'توقيع ITP')),
                                ),
                              if (manager &&
                                  doc.isApproved &&
                                  doc.kind == 'ncr' &&
                                  doc.createdBy != widget.profile.id)
                                TextButton(
                                  onPressed: busy ? null : () => _closeNcr(doc),
                                  child: Text(t('Close NCR', 'إغلاق NCR')),
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
