import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/checkadmin_errors.dart';
import '../design/checkadmin_widgets.dart';

class DeleteTab extends ConsumerStatefulWidget {
  const DeleteTab({super.key, required this.profile, required this.language});
  final Profile profile;
  final String language;

  @override
  ConsumerState<DeleteTab> createState() => _DeleteTabState();
}

class _DeleteTabState extends ConsumerState<DeleteTab> {
  List<Inspection> records = [];
  bool loading = true;
  String? message;
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
    final repository = ref.read(inspectionRepositoryProvider);
    try {
      try {
        await repository.retryPendingMediaCleanup();
      } catch (_) {}
      final list = await repository.listInspections();
      if (!mounted) return;
      setState(() => records = list);
    } catch (e) {
      if (mounted) {
        setState(() => message = checkAdminUserMessage(e, widget.language));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _delete(Inspection row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('Delete inspection', 'حذف الفحص')),
        content: Text(
          _t(
            'Permanently delete ${row.buildingCode} from ${row.dateIso}? This action is recorded in the audit log.',
            'حذف ${row.buildingCode} بتاريخ ${row.dateIso} نهائيًا؟ سيتم تسجيل العملية في سجل التدقيق.',
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
            child: Text(_t('Delete permanently', 'حذف نهائي')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(inspectionRepositoryProvider).deleteInspection(row);
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() => message = checkAdminUserMessage(e, widget.language));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CaPageHeader(
                eyebrow: _t('Governance', 'الحوكمة'),
                title: _t('Deletion control', 'إدارة الحذف'),
                subtitle: _t(
                  'Restricted destructive actions with audit visibility.',
                  'إجراءات حذف مقيدة مع توثيق كامل في سجل التدقيق.',
                ),
              ),
              const SizedBox(height: 10),
              CaMetricStrip(
                metrics: [
                  CaMetric(
                    label: _t('Records', 'السجلات'),
                    value: '${records.length}',
                    icon: Icons.inventory_2_outlined,
                  ),
                ],
              ),
            ],
          ),
        ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: CaInlineNotice(
              message: message!,
              tone: CaTone.danger,
              onDismiss: () => setState(() => message = null),
            ),
          ),
        Expanded(
          child: records.isEmpty
              ? CaEmptyState(
                  icon: Icons.delete_sweep_outlined,
                  title: _t('No inspections available', 'لا توجد فحوصات متاحة'),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                  itemCount: records.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final r = records[i];
                    return CaCommandRow(
                      leading: const Icon(Icons.description_outlined),
                      title: '${r.buildingCode} — ${r.dateIso}',
                      subtitle: r.inspectorName,
                      trailing: IconButton(
                        tooltip: _t('Delete inspection', 'حذف الفحص'),
                        onPressed: () => _delete(r),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
