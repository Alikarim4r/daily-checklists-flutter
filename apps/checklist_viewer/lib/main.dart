import 'dart:ui' as ui;

import 'package:checklist_shared/checklist_shared.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await bootstrapSupabase();
  runApp(const ProviderScope(child: ViewerRoot()));
}

class ViewerRoot extends StatelessWidget {
  const ViewerRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'فحص يومي — عرض',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: ViewerPalette.orange,
          primary: ViewerPalette.orange,
        ),
        scaffoldBackgroundColor: ViewerPalette.bg,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: ViewerPalette.slate900,
          foregroundColor: Colors.white,
        ),
      ),
      builder: (context, child) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: ChecklistAuthGate(
        appTitle: 'لوحة العرض',
        subtitle: 'نظام الفحص اليومي للمرافق — عرض النموذج',
        allowedForProfile: (p) =>
            p.isPlatformOwner || p.role.canUseViewer,
        siteAccessRequirement: SiteAccessRequirement.read,
        homeBuilder: (context, profile) => ViewerHome(profile: profile),
      ),
    );
  }
}

class ViewerHome extends ConsumerStatefulWidget {
  const ViewerHome({super.key, required this.profile});
  final Profile profile;

  @override
  ConsumerState<ViewerHome> createState() => _ViewerHomeState();
}

class _ViewerHomeState extends ConsumerState<ViewerHome> {
  String language = 'ar';
  List<ChecklistSite> sites = [];
  List<UserSiteAccess> myAccess = [];
  List<Inspection> records = [];
  String? siteFilter;
  DateTime date = DateTime.now();
  Inspection? selected;
  bool loading = true;
  String? message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _wide => MediaQuery.sizeOf(context).width >= 900;

  bool _canWriteSelected() {
    final insp = selected;
    if (insp == null) return false;
    if (widget.profile.isPlatformOwner ||
        widget.profile.role == UserRole.superAdmin) {
      return true;
    }
    return myAccess.any((a) => a.siteId == insp.siteId && a.canWrite);
  }

  bool _canManageSelected() {
    final insp = selected;
    if (insp == null) return false;
    if (widget.profile.isPlatformOwner ||
        widget.profile.role == UserRole.superAdmin) {
      return true;
    }
    return myAccess.any((a) => a.siteId == insp.siteId && a.canManage);
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      message = null;
    });
    try {
      final siteRepo = ref.read(siteRepositoryProvider);
      final inspRepo = ref.read(inspectionRepositoryProvider);
      final siteList =
          await siteRepo.listAccessibleSites(profile: widget.profile);
      final access = await siteRepo.listMySiteAccess();
      final list = await inspRepo.listInspections(
        siteId: siteFilter,
        date: date,
      );
      setState(() {
        sites = siteList;
        myAccess = access;
        records = list;
        if (selected != null) {
          selected = list.where((r) => r.id == selected!.id).firstOrNull;
        }
      });
    } catch (e) {
      setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _open(Inspection row) async {
    final full = await ref.read(inspectionRepositoryProvider).getById(row.id);
    if (full == null) {
      setState(() => message = 'تعذر فتح السجل');
      return;
    }
    if (!_wide && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => InspectionFormPage(
            profile: widget.profile,
            language: language,
            initial: full,
            myAccess: myAccess,
            onChanged: () async {
              await _load();
            },
          ),
        ),
      );
      await _load();
      return;
    }
    setState(() => selected = full);
  }

  Future<void> _save() async {
    final current = selected;
    if (current == null || current.isSubmitted || !_canWriteSelected()) return;
    try {
      await ref.read(inspectionRepositoryProvider).saveItems(current);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ التعديلات')),
        );
      }
      await _load();
    } catch (e) {
      setState(() => message = e.toString());
    }
  }

  Future<void> _submit() async {
    final current = selected;
    if (current == null || current.isSubmitted || !_canWriteSelected()) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إرسال التقرير'),
        content: const Text(
          'تأكيد إرسال سجل الفحص؟ لن يمكن تعديله بعد الإرسال إلا بصلاحية إدارة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إرسال'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(inspectionRepositoryProvider).saveItems(current);
      await ref.read(inspectionRepositoryProvider).submit(current.id);
      await _load();
      await _open(current);
    } catch (e) {
      setState(() => message = e.toString());
    }
  }

  Future<void> _correctItem(InspectionItem item) async {
    if (selected == null || item.id == null || !_canManageSelected()) return;
    final responseCtrl = TextEditingController(
      text: item.response?.dbValue ?? '',
    );
    final actionsCtrl = TextEditingController(text: item.actionsTaken);
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تصحيح بند ${item.itemIndex}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: responseCtrl,
              decoration: const InputDecoration(
                labelText: 'الإجابة (yes/no/na)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: actionsCtrl,
              decoration: const InputDecoration(
                labelText: 'الإجراءات',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'سبب التصحيح',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حفظ التصحيح'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final newResponse = ChecklistResponse.fromDb(responseCtrl.text.trim());
    try {
      await ref.read(correctionRepositoryProvider).correctItem(
            inspectionId: selected!.id,
            itemId: item.id!,
            fieldName: 'response+actions_taken',
            oldValue: '${item.response?.dbValue}|${item.actionsTaken}',
            newValue: '${newResponse?.dbValue}|${actionsCtrl.text}',
            reason: reasonCtrl.text,
            itemPatch: {
              'response': newResponse?.dbValue,
              'actions_taken': actionsCtrl.text,
            },
          );
      final full =
          await ref.read(inspectionRepositoryProvider).getById(selected!.id);
      if (full != null) setState(() => selected = full);
    } catch (e) {
      setState(() => message = e.toString());
    }
  }

  Widget _filtersBar({required bool showActions}) {
    final canEdit = selected != null &&
        !selected!.isSubmitted &&
        _canWriteSelected();
    return Material(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<String?>(
                value: siteFilter,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'المباني',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('جميع المباني'),
                  ),
                  for (final s in sites)
                    DropdownMenuItem(
                      value: s.id,
                      child: Text(
                        '${s.buildingCode} — ${s.nameFor(language)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) async {
                  setState(() => siteFilter = v);
                  await _load();
                },
              ),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: DateTime(2024),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                );
                if (picked == null) return;
                setState(() => date = picked);
                await _load();
              },
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text(DateFormat('yyyy-MM-dd').format(date)),
            ),
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
            if (showActions && canEdit) ...[
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: ViewerPalette.orange,
                ),
                onPressed: _save,
                child: const Text('حفظ'),
              ),
              FilledButton(
                onPressed: _submit,
                child: const Text('إرسال التقرير'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _recordsList() {
    if (records.isEmpty) {
      return const Center(child: Text('لا توجد سجلات فحص'));
    }
    return ListView.builder(
      itemCount: records.length,
      itemBuilder: (context, i) {
        final r = records[i];
        final selectedId = selected?.id == r.id;
        return ListTile(
          selected: selectedId,
          title: Text(r.buildingCode),
          subtitle: Text('${r.inspectorName} • ${r.status.dbValue}'),
          trailing: const Icon(Icons.chevron_left),
          onTap: () => _open(r),
        );
      },
    );
  }

  Widget _formPane() {
    if (selected == null) {
      return const ColoredBox(
        color: Color(0xFFE5E7EB),
        child: Center(child: Text('اختر سجلًا لعرض النموذج على ورقة A4')),
      );
    }
    final canEditDraft = !selected!.isSubmitted && _canWriteSelected();
    final canCorrect = selected!.isSubmitted && _canManageSelected();
    return A4PaperSheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChecklistFormLayout(
            inspection: selected!,
            language: 'en',
            forceTableLayout: true,
            readOnly: !canEditDraft,
            onInspectorChanged: (v) =>
                setState(() => selected!.inspectorName = v),
            onTimeChanged: (v) =>
                setState(() => selected!.inspectionTime = v),
            onFloorChanged: (v) => setState(() => selected!.floorLabel = v),
            onResponseChanged: (item, value) =>
                setState(() => item.response = value),
            onActionsChanged: (item, value) =>
                setState(() => item.actionsTaken = value),
          ),
          if (canCorrect) ...[
            const SizedBox(height: 16),
            const Divider(),
            const Text(
              'تصحيح بعد الإرسال (صلاحية إدارة الموقع)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            for (final item in selected!.items)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${item.itemIndex}. ${item.description}'),
                trailing: IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => _correctItem(item),
                ),
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MOEHE — عرض الفحص اليومي'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(child: Text(widget.profile.email)),
          ),
          IconButton(
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Column(
        children: [
          _filtersBar(showActions: _wide),
          if (message != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(message!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : _wide
                    ? Row(
                        children: [
                          SizedBox(width: 300, child: _recordsList()),
                          const VerticalDivider(width: 1),
                          Expanded(child: _formPane()),
                        ],
                      )
                    : _recordsList(),
          ),
        ],
      ),
    );
  }
}

/// Full-screen PDF-style form for phones.
class InspectionFormPage extends ConsumerStatefulWidget {
  const InspectionFormPage({
    super.key,
    required this.profile,
    required this.language,
    required this.initial,
    required this.myAccess,
    required this.onChanged,
  });

  final Profile profile;
  final String language;
  final Inspection initial;
  final List<UserSiteAccess> myAccess;
  final Future<void> Function() onChanged;

  @override
  ConsumerState<InspectionFormPage> createState() => _InspectionFormPageState();
}

class _InspectionFormPageState extends ConsumerState<InspectionFormPage> {
  late Inspection inspection;
  String? message;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    inspection = widget.initial;
  }

  bool get _canWrite {
    if (widget.profile.isPlatformOwner ||
        widget.profile.role == UserRole.superAdmin) {
      return true;
    }
    return widget.myAccess
        .any((a) => a.siteId == inspection.siteId && a.canWrite);
  }

  bool get _canManage {
    if (widget.profile.isPlatformOwner ||
        widget.profile.role == UserRole.superAdmin) {
      return true;
    }
    return widget.myAccess
        .any((a) => a.siteId == inspection.siteId && a.canManage);
  }

  Future<void> _save() async {
    if (inspection.isSubmitted || !_canWrite) return;
    setState(() => saving = true);
    try {
      await ref.read(inspectionRepositoryProvider).saveItems(inspection);
      await widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم الحفظ')),
        );
      }
    } catch (e) {
      setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _submit() async {
    if (inspection.isSubmitted || !_canWrite) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إرسال التقرير'),
        content: const Text('تأكيد إرسال سجل الفحص؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إرسال'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => saving = true);
    try {
      await ref.read(inspectionRepositoryProvider).saveItems(inspection);
      await ref.read(inspectionRepositoryProvider).submit(inspection.id);
      final full =
          await ref.read(inspectionRepositoryProvider).getById(inspection.id);
      if (full != null) setState(() => inspection = full);
      await widget.onChanged();
    } catch (e) {
      setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _correctItem(InspectionItem item) async {
    if (item.id == null || !_canManage) return;
    final responseCtrl =
        TextEditingController(text: item.response?.dbValue ?? '');
    final actionsCtrl = TextEditingController(text: item.actionsTaken);
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تصحيح بند ${item.itemIndex}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: responseCtrl,
              decoration: const InputDecoration(
                labelText: 'الإجابة (yes/no/na)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: actionsCtrl,
              decoration: const InputDecoration(
                labelText: 'الإجراءات',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'سبب التصحيح',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final newResponse = ChecklistResponse.fromDb(responseCtrl.text.trim());
    await ref.read(correctionRepositoryProvider).correctItem(
          inspectionId: inspection.id,
          itemId: item.id!,
          fieldName: 'response+actions_taken',
          oldValue: '${item.response?.dbValue}|${item.actionsTaken}',
          newValue: '${newResponse?.dbValue}|${actionsCtrl.text}',
          reason: reasonCtrl.text,
          itemPatch: {
            'response': newResponse?.dbValue,
            'actions_taken': actionsCtrl.text,
          },
        );
    final full =
        await ref.read(inspectionRepositoryProvider).getById(inspection.id);
    if (full != null) setState(() => inspection = full);
    await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final canEditDraft = !inspection.isSubmitted && _canWrite;
    final canCorrect = inspection.isSubmitted && _canManage;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: Text('${inspection.buildingCode} — ${inspection.dateIso}'),
        actions: [
          if (canEditDraft) ...[
            TextButton(
              onPressed: saving ? null : _save,
              child: const Text('حفظ', style: TextStyle(color: Colors.white)),
            ),
            TextButton(
              onPressed: saving ? null : _submit,
              child: const Text('إرسال', style: TextStyle(color: Colors.white)),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          if (message != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(message!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: A4PaperSheet(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ChecklistFormLayout(
                    inspection: inspection,
                    language: 'en',
                    forceTableLayout: true,
                    readOnly: !canEditDraft,
                    onInspectorChanged: (v) =>
                        setState(() => inspection.inspectorName = v),
                    onTimeChanged: (v) =>
                        setState(() => inspection.inspectionTime = v),
                    onFloorChanged: (v) =>
                        setState(() => inspection.floorLabel = v),
                    onResponseChanged: (item, value) =>
                        setState(() => item.response = value),
                    onActionsChanged: (item, value) =>
                        setState(() => item.actionsTaken = value),
                  ),
                  if (canCorrect) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const Text(
                      'تصحيح بعد الإرسال',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    for (final item in inspection.items)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${item.itemIndex}. ${item.description}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _correctItem(item),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
