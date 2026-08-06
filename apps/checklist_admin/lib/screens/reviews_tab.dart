import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Submitted inspections awaiting site_admin / super_admin approval.
class ReviewsTab extends ConsumerStatefulWidget {
  const ReviewsTab({super.key, required this.profile});
  final Profile profile;

  @override
  ConsumerState<ReviewsTab> createState() => _ReviewsTabState();
}

class _ReviewsTabState extends ConsumerState<ReviewsTab> {
  List<Inspection> rows = [];
  bool loading = true;
  String? message;

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
      final list =
          await ref.read(inspectionRepositoryProvider).listPendingReview();
      setState(() => rows = list);
    } catch (e) {
      setState(() => message = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _open(Inspection inspection) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => _ReviewEditScreen(
          profile: widget.profile,
          inspection: inspection,
        ),
      ),
    );
    if (updated == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (message != null) {
      return Center(child: Text(message!, style: const TextStyle(color: Colors.red)));
    }
    if (rows.isEmpty) {
      return const Center(child: Text('لا توجد فحوصات بانتظار الاعتماد'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: rows.length,
        itemBuilder: (context, i) {
          final r = rows[i];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: ListTile(
              title: Text('${r.buildingCode} — ${r.dateIso}'),
              subtitle: Text(
                '${r.inspectorName}\n${r.reviewStatus.labelAr} • ${r.items.length} بند',
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_left),
              onTap: () => _open(r),
            ),
          );
        },
      ),
    );
  }
}

class _ReviewEditScreen extends ConsumerStatefulWidget {
  const _ReviewEditScreen({
    required this.profile,
    required this.inspection,
  });

  final Profile profile;
  final Inspection inspection;

  @override
  ConsumerState<_ReviewEditScreen> createState() => _ReviewEditScreenState();
}

class _ReviewEditScreenState extends ConsumerState<_ReviewEditScreen> {
  late Inspection inspection;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    inspection = widget.inspection;
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      await ref.read(inspectionRepositoryProvider).saveItems(inspection);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم الحفظ')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _approve() async {
    setState(() => saving = true);
    try {
      await ref.read(inspectionRepositoryProvider).saveItems(inspection);
      await ref
          .read(inspectionRepositoryProvider)
          .approveInspection(inspection.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${inspection.buildingCode} — ${inspection.dateIso}'),
        actions: [
          TextButton(
            onPressed: saving ? null : _save,
            child: const Text('حفظ'),
          ),
          FilledButton(
            onPressed: saving ? null : _approve,
            child: const Text('اعتماد'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: ChecklistFormLayout(
          inspection: inspection,
          language: 'ar',
          forceTableLayout: MediaQuery.sizeOf(context).width >= 800,
          onInspectorChanged: (v) =>
              setState(() => inspection.inspectorName = v),
          onTimeChanged: (v) =>
              setState(() => inspection.inspectionTime = v),
          onFloorChanged: (v) => setState(() => inspection.floorLabel = v),
          onResponseChanged: (item, value) => setState(() {
            item.response = value;
          }),
          onActionsChanged: (item, value) => setState(() {
            item.actionsTaken = value;
          }),
        ),
      ),
    );
  }
}
