import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DeleteTab extends ConsumerStatefulWidget {
  const DeleteTab({super.key, required this.profile});
  final Profile profile;

  @override
  ConsumerState<DeleteTab> createState() => _DeleteTabState();
}

class _DeleteTabState extends ConsumerState<DeleteTab> {
  List<Inspection> records = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final list = await ref.read(inspectionRepositoryProvider).listInspections();
    setState(() {
      records = list;
      loading = false;
    });
  }

  Future<void> _delete(Inspection row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف السجل'),
        content: Text('حذف ${row.buildingCode} بتاريخ ${row.dateIso}؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(inspectionRepositoryProvider).deleteInspection(row);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return ListView.builder(
      itemCount: records.length,
      itemBuilder: (context, i) {
        final r = records[i];
        return ListTile(
          title: Text('${r.buildingCode} — ${r.dateIso}'),
          subtitle: Text(r.inspectorName),
          trailing: IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () => _delete(r),
          ),
        );
      },
    );
  }
}
