import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await bootstrapSupabase();
  runApp(const ProviderScope(child: EntryRoot()));
}

class EntryRoot extends StatelessWidget {
  const EntryRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'فحص يومي — إدخال',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: ViewerPalette.orange),
        useMaterial3: true,
      ),
      builder: (context, child) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: ChecklistAuthGate(
        appTitle: 'تسجيل الدخول',
        subtitle: 'نظام الفحص اليومي للمرافق — إدخال',
        allowedForProfile: (p) =>
            p.isPlatformOwner || p.role.canUseEntry,
        siteAccessRequirement: SiteAccessRequirement.write,
        homeBuilder: (context, profile) => EntryHome(profile: profile),
      ),
    );
  }
}

class EntryHome extends ConsumerStatefulWidget {
  const EntryHome({super.key, required this.profile});
  final Profile profile;

  @override
  ConsumerState<EntryHome> createState() => _EntryHomeState();
}

class _EntryHomeState extends ConsumerState<EntryHome> {
  String language = 'ar';
  List<ChecklistSite> sites = [];
  ChecklistSite? selectedSite;
  DateTime date = DateTime.now();
  Inspection? inspection;
  bool loading = true;
  bool saving = false;
  String? message;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      loading = true;
      message = null;
    });
    try {
      final list = await ref
          .read(siteRepositoryProvider)
          .listWritableSites(profile: widget.profile);
      setState(() {
        sites = list;
        selectedSite = list.isNotEmpty ? list.first : null;
      });
      if (selectedSite != null) await _loadOrCreate();
    } catch (e) {
      setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _loadOrCreate() async {
    final site = selectedSite;
    if (site == null) return;
    setState(() {
      loading = true;
      message = null;
    });
    try {
      final repo = ref.read(inspectionRepositoryProvider);
      var existing = await repo.getForSiteDate(siteId: site.id, date: date);
      existing ??= await repo.createDraft(
        site: site,
        date: date,
        inspectorName: widget.profile.fullName,
        inspectionTime: DateFormat('h:mm a').format(DateTime.now()),
        language: language,
      );
      setState(() => inspection = existing);
    } catch (e) {
      setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _save() async {
    final current = inspection;
    if (current == null) return;
    setState(() => saving = true);
    try {
      await ref.read(inspectionRepositoryProvider).saveItems(current);
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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() => date = picked);
    await _loadOrCreate();
  }

  Future<void> _pickPhoto(InspectionItem item, {required bool isIssue}) async {
    final current = inspection;
    final site = selectedSite;
    if (current == null || site == null || current.isSubmitted) return;
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
      maxWidth: 1600,
    );
    if (file == null) return;
    try {
      final bytes = await file.readAsBytes();
      final orgId = site.organizationId.isNotEmpty
          ? site.organizationId
          : current.organizationId;
      if (orgId.isEmpty) {
        throw StateError('organization_id missing for upload path');
      }
      final kind = isIssue ? 'issue' : 'fix';
      final path = await ref.read(inspectionRepositoryProvider).uploadBytes(
            organizationId: orgId,
            siteId: site.id,
            inspectionId: current.id,
            fileName: '${item.itemIndex}_$kind.jpg',
            bytes: bytes,
          );
      setState(() {
        if (isIssue) {
          item.issueImagePath = path;
          item.imagePath = path;
        } else {
          item.fixImagePath = path;
        }
      });
      await ref.read(inspectionRepositoryProvider).saveItems(current);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isIssue ? 'تم حفظ صورة المشكلة' : 'تم حفظ صورة الإصلاح'),
          ),
        );
      }
    } catch (e) {
      setState(() => message = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text('إدخال الفحص اليومي'),
        backgroundColor: ViewerPalette.slate900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 280,
                          child: DropdownButtonFormField<ChecklistSite>(
                            value: selectedSite,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'المبنى',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              for (final s in sites)
                                DropdownMenuItem(
                                  value: s,
                                  child: Text(
                                    '${s.buildingCode} — ${s.nameFor(language)}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (v) async {
                              setState(() => selectedSite = v);
                              await _loadOrCreate();
                            },
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _pickDate,
                          icon: const Icon(Icons.calendar_today),
                          label: Text(DateFormat('yyyy-MM-dd').format(date)),
                        ),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: ViewerPalette.orange,
                          ),
                          onPressed: saving ? null : _save,
                          icon: const Icon(Icons.save),
                          label: Text(saving ? 'جاري الحفظ…' : 'حفظ'),
                        ),
                      ],
                    ),
                  ),
                ),
                if (message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(message!, style: const TextStyle(color: Colors.red)),
                  ),
                const SizedBox(height: 12),
                if (inspection != null)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = MediaQuery.sizeOf(context).width >= 800;
                      final form = ChecklistFormLayout(
                        inspection: inspection!,
                        language: wide ? 'en' : language,
                        forceTableLayout: wide,
                        readOnly: inspection!.isSubmitted,
                        onInspectorChanged: (v) =>
                            setState(() => inspection!.inspectorName = v),
                        onTimeChanged: (v) =>
                            setState(() => inspection!.inspectionTime = v),
                        onFloorChanged: (v) =>
                            setState(() => inspection!.floorLabel = v),
                        onResponseChanged: (item, value) => setState(() {
                          item.response = value;
                        }),
                        onActionsChanged: (item, value) => setState(() {
                          item.actionsTaken = value;
                        }),
                        onPickIssuePhoto: (item) =>
                            _pickPhoto(item, isIssue: true),
                        onPickFixPhoto: (item) =>
                            _pickPhoto(item, isIssue: false),
                      );
                      if (!wide) {
                        return Card(clipBehavior: Clip.antiAlias, child: form);
                      }
                      return SizedBox(
                        height: math.max(900, MediaQuery.sizeOf(context).height * 0.75),
                        child: A4PaperSheet(child: form),
                      );
                    },
                  ),
              ],
            ),
    );
  }
}
