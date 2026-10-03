import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/checkadmin_errors.dart';
import '../design/checkadmin_tokens.dart';
import '../design/checkadmin_widgets.dart';

class PoliciesScreen extends ConsumerStatefulWidget {
  const PoliciesScreen({
    super.key,
    required this.profile,
    required this.language,
    this.initialOrganizationId,
  });

  final Profile profile;
  final String language;
  final String? initialOrganizationId;

  @override
  ConsumerState<PoliciesScreen> createState() => _PoliciesScreenState();
}

class _PoliciesScreenState extends ConsumerState<PoliciesScreen> {
  List<Organization> orgs = [];
  String? orgId;
  ChecklistOrgPolicy? policy;
  bool loading = true;
  bool saving = false;
  String? message;

  bool get ar => widget.language == 'ar';
  String _t(String en, String arText) => ar ? arText : en;
  bool get canEdit => widget.profile.canManagePolicies;

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
          .read(organizationRepositoryProvider)
          .listOrganizations();
      final preferred = widget.initialOrganizationId;
      final id =
          orgId ??
          (preferred != null && list.any((o) => o.id == preferred)
              ? preferred
              : (list.isNotEmpty ? list.first.id : null));
      ChecklistOrgPolicy? p;
      if (id != null) {
        p = await ref.read(policyRepositoryProvider).getOrCreate(id);
      }
      if (!mounted) return;
      setState(() {
        orgs = list;
        orgId = id;
        policy = p;
      });
    } catch (e) {
      if (mounted) {
        setState(() => message = checkAdminUserMessage(e, widget.language));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _selectOrg(String? id) async {
    if (id == null) return;
    setState(() {
      orgId = id;
      loading = true;
      message = null;
    });
    try {
      final p = await ref.read(policyRepositoryProvider).getOrCreate(id);
      if (mounted) setState(() => policy = p);
    } catch (e) {
      if (mounted) {
        setState(() => message = checkAdminUserMessage(e, widget.language));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _save() async {
    final p = policy;
    if (p == null || !canEdit) return;
    setState(() => saving = true);
    try {
      final saved = await ref.read(policyRepositoryProvider).upsert(p);
      if (!mounted) return;
      setState(() => policy = saved);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('Policies saved', 'تم حفظ السياسات'))),
      );
    } catch (e) {
      if (mounted) {
        setState(() => message = checkAdminUserMessage(e, widget.language));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('Policies', 'السياسات')),
        actions: [
          if (canEdit)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: FilledButton.icon(
                onPressed: saving || loading ? null : _save,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: Text(saving ? '…' : _t('Save', 'حفظ')),
              ),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: loading && policy == null
            ? const Center(child: CircularProgressIndicator())
            : CaPageWidth(
                maxWidth: 980,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    CaSpace.gutter,
                    0,
                    CaSpace.gutter,
                    CaSpace.xxl,
                  ),
                  children: [
                    CaPageHeader(
                      eyebrow: _t('Governance', 'الحوكمة'),
                      title: _t(
                        'Inspection evidence policies',
                        'سياسات أدلة الفحص',
                      ),
                      subtitle: _t(
                        'Control how problem and repair evidence is enforced for each organization.',
                        'تحكم في إلزام صور المشاكل والإصلاح لكل جهة.',
                      ),
                      meta: [
                        CaMeta(
                          canEdit
                              ? _t('Editable', 'قابل للتعديل')
                              : _t('Read only', 'للقراءة فقط'),
                          icon: canEdit
                              ? Icons.edit_outlined
                              : Icons.lock_outline,
                          tone: canEdit ? CaTone.good : CaTone.neutral,
                        ),
                      ],
                    ),
                    const SizedBox(height: CaSpace.md),
                    if (message != null) ...[
                      CaInlineNotice(
                        message: message!,
                        tone: CaTone.danger,
                        onDismiss: () => setState(() => message = null),
                      ),
                      const SizedBox(height: CaSpace.md),
                    ],
                    DropdownButtonFormField<String>(
                      initialValue: orgId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: _t('Organization', 'الجهة'),
                        prefixIcon: const Icon(Icons.domain_outlined),
                      ),
                      items: [
                        for (final o in orgs)
                          DropdownMenuItem(
                            value: o.id,
                            child: Text(o.nameFor(widget.language)),
                          ),
                      ],
                      onChanged: loading ? null : _selectOrg,
                    ),
                    const SizedBox(height: CaSpace.lg),
                    if (policy != null) ...[
                      CaSectionLabel(
                        title: _t('Problem evidence', 'أدلة المشكلة'),
                      ),
                      CaPanel(
                        padding: EdgeInsets.zero,
                        child: SwitchListTile(
                          title: Text(
                            _t(
                              'Require a photo when an item fails',
                              'إلزام صورة عند وجود مشكلة',
                            ),
                          ),
                          subtitle: Text(
                            _t(
                              'Applies when the answer differs from the ideal state.',
                              'يُطبق عند تسجيل إجابة مخالفة للحالة المثالية.',
                            ),
                          ),
                          secondary: const Icon(Icons.photo_camera_outlined),
                          value: policy!.photoRequiredOnProblem,
                          onChanged: canEdit
                              ? (v) => setState(
                                  () => policy = policy!.copyWith(
                                    photoRequiredOnProblem: v,
                                  ),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: CaSpace.sm),
                      CaPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _t('Missing-photo severity', 'شدة نقص الصورة'),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 10),
                            SegmentedButton<PolicySeverity>(
                              segments: [
                                for (final s in PolicySeverity.values)
                                  ButtonSegment(
                                    value: s,
                                    label: Text(ar ? s.labelAr : s.name),
                                  ),
                              ],
                              selected: {policy!.missingPhotoSeverity},
                              onSelectionChanged: canEdit
                                  ? (s) => setState(
                                      () => policy = policy!.copyWith(
                                        missingPhotoSeverity: s.first,
                                      ),
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                      CaSectionLabel(
                        title: _t('Repair evidence', 'أدلة الإصلاح'),
                      ),
                      CaPanel(
                        padding: EdgeInsets.zero,
                        child: SwitchListTile(
                          title: Text(
                            _t('Require a repair photo', 'إلزام صورة الإصلاح'),
                          ),
                          subtitle: Text(
                            _t(
                              'A resolved problem must include visual evidence when enabled.',
                              'يجب إرفاق دليل مرئي عند إغلاق المشكلة إذا كان الخيار مفعّلًا.',
                            ),
                          ),
                          secondary: const Icon(Icons.build_circle_outlined),
                          value: policy!.requireFixPhoto,
                          onChanged: canEdit
                              ? (v) => setState(
                                  () => policy = policy!.copyWith(
                                    requireFixPhoto: v,
                                  ),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: CaSpace.sm),
                      CaInlineNotice(
                        title: _t('Overdue timing', 'أيام التأخير'),
                        message: _t(
                          'Overdue thresholds are configured per checklist item from the Checklists workspace.',
                          'تُضبط مهلة التأخير لكل بند من مساحة القوائم، وليست قيمة واحدة للجهة.',
                        ),
                        tone: CaTone.brass,
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}
