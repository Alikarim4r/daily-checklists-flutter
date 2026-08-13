import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PoliciesScreen extends ConsumerStatefulWidget {
  const PoliciesScreen({
    super.key,
    required this.profile,
    this.initialOrganizationId,
  });
  final Profile profile;
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
      setState(() {
        orgs = list;
        orgId = id;
        policy = p;
      });
    } catch (e) {
      setState(() => message = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _selectOrg(String? id) async {
    if (id == null) return;
    setState(() {
      orgId = id;
      loading = true;
    });
    final p = await ref.read(policyRepositoryProvider).getOrCreate(id);
    setState(() {
      policy = p;
      loading = false;
    });
  }

  Future<void> _save() async {
    final p = policy;
    if (p == null || !canEdit) return;
    setState(() => saving = true);
    try {
      final saved = await ref.read(policyRepositoryProvider).upsert(p);
      setState(() => policy = saved);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم حفظ السياسات')));
      }
    } catch (e) {
      setState(() => message = '$e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('السياسات'),
        actions: [
          if (canEdit)
            TextButton(
              onPressed: saving ? null : _save,
              child: Text(saving ? '…' : 'حفظ'),
            ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (message != null)
                  Text(message!, style: const TextStyle(color: Colors.red)),
                DropdownButtonFormField<String>(
                  initialValue: orgId,
                  decoration: const InputDecoration(
                    labelText: 'الجهة',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final o in orgs)
                      DropdownMenuItem(value: o.id, child: Text(o.nameAr)),
                  ],
                  onChanged: _selectOrg,
                ),
                const SizedBox(height: 16),
                if (policy != null) ...[
                  Card(
                    child: SwitchListTile(
                      title: const Text('إلزام صورة عند وجود مشكلة'),
                      subtitle: const Text(
                        'عند تسجيل إجابة مخالفة للحالة المثالية',
                      ),
                      value: policy!.photoRequiredOnProblem,
                      onChanged: canEdit
                          ? (v) => setState(() {
                              policy = policy!.copyWith(
                                photoRequiredOnProblem: v,
                              );
                            })
                          : null,
                    ),
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'شدة نقص الصورة',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          SegmentedButton<PolicySeverity>(
                            segments: [
                              for (final s in PolicySeverity.values)
                                ButtonSegment(value: s, label: Text(s.labelAr)),
                            ],
                            selected: {policy!.missingPhotoSeverity},
                            onSelectionChanged: canEdit
                                ? (s) => setState(() {
                                    policy = policy!.copyWith(
                                      missingPhotoSeverity: s.first,
                                    );
                                  })
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Card(
                    child: SwitchListTile(
                      title: const Text('إلزام صورة الإصلاح'),
                      value: policy!.requireFixPhoto,
                      onChanged: canEdit
                          ? (v) => setState(() {
                              policy = policy!.copyWith(requireFixPhoto: v);
                            })
                          : null,
                    ),
                  ),
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text('أيام الأوفرديو'),
                      subtitle: Text(
                        'تُضبط لكل بند من تبويب القوائم (ليس جهة واحدة لجميع البنود).',
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
