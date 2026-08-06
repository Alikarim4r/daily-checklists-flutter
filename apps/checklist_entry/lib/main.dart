import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signature/signature.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ChecklistChrome.use(ChecklistBrand.entry);
  await bootstrapSupabase();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const EntryRoot(),
    ),
  );
}

class EntryRoot extends ConsumerStatefulWidget {
  const EntryRoot({super.key});

  @override
  ConsumerState<EntryRoot> createState() => _EntryRootState();
}

class _EntryRootState extends ConsumerState<EntryRoot> {
  String language = 'en';

  @override
  Widget build(BuildContext context) {
    final labels = AppLabels(language);
    final rtl = isRtlLanguage(language);
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: labels.title,
      debugShowCheckedModeBanner: false,
      theme: ChecklistChrome.theme(),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: ChecklistChrome.accent,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: themeMode,
      builder: (context, child) => Directionality(
        textDirection: rtl ? ui.TextDirection.rtl : ui.TextDirection.ltr,
        child: child ?? const SizedBox.shrink(),
      ),
      home: ChecklistAuthGate(
        appTitle: labels.login,
        subtitle: labels.technicianVersion,
        allowedForProfile: (p) =>
            p.isPlatformOwner || p.role.canUseEntry,
        siteAccessRequirement: SiteAccessRequirement.write,
        homeBuilder: (context, profile) => EntryHome(
          profile: profile,
          language: language,
          onLanguageChanged: (v) => setState(() => language = v),
        ),
      ),
    );
  }
}

class EntryHome extends ConsumerStatefulWidget {
  const EntryHome({
    super.key,
    required this.profile,
    required this.language,
    required this.onLanguageChanged,
  });

  final Profile profile;
  final String language;
  final ValueChanged<String> onLanguageChanged;

  @override
  ConsumerState<EntryHome> createState() => _EntryHomeState();
}

class _EntryHomeState extends ConsumerState<EntryHome> {
  List<CampusChecklistGroup> groups = [];
  bool loading = true;
  String? message;

  AppLabels get L => AppLabels(widget.language);

  @override
  void initState() {
    super.initState();
    _loadSites();
  }

  Future<void> _loadSites() async {
    setState(() {
      loading = true;
      message = null;
    });
    try {
      final list = await ref
          .read(siteRepositoryProvider)
          .listWritableCampusGroups(profile: widget.profile);
      setState(() => groups = list);
    } catch (e) {
      setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _openChecklist(ChecklistSite site) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EntrySiteScreen(
          profile: widget.profile,
          site: site,
          language: widget.language,
          onLanguageChanged: widget.onLanguageChanged,
        ),
      ),
    );
  }

  void _openCampus(CampusChecklistGroup group) {
    if (group.checklists.length == 1 && group.campus == null) {
      _openChecklist(group.checklists.first);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EntryCampusScreen(
          profile: widget.profile,
          group: group,
          language: widget.language,
          onLanguageChanged: widget.onLanguageChanged,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.profile.fullName.isEmpty
        ? widget.profile.email
        : widget.profile.fullName;
    return Scaffold(
      drawer: ChecklistSettingsDrawer(
        profile: widget.profile,
        language: widget.language,
        onLanguageChanged: widget.onLanguageChanged,
        languages: supportedLanguages,
        appIconAsset: 'assets/branding/app_icon_simple.png',
      ),
      appBar: checklistGradientAppBar(
        title: L.mySites,
        actions: [
          IconButton(
            onPressed: _loadSites,
            icon: const Icon(Icons.refresh),
          ),
          Builder(
            builder: (ctx) => IconButton(
              tooltip: widget.language == 'ar' ? 'الإعدادات' : 'Settings',
              onPressed: () => Scaffold.of(ctx).openDrawer(),
              icon: const Icon(Icons.settings_outlined),
            ),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                Text(
                  '${L.welcome}, $name',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: ChecklistChrome.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  L.selectSiteHint,
                  style: TextStyle(color: ChecklistChrome.inkMuted),
                ),
                if (message != null) ...[
                  const SizedBox(height: 8),
                  Text(message!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 16),
                if (groups.isEmpty)
                  ChecklistBrandCard(
                    child: Text(
                      widget.language == 'ar'
                          ? 'لا توجد مواقع مصرّح لك بالإدخال.'
                          : 'No writable sites assigned to your account.',
                      style: TextStyle(color: ChecklistChrome.inkMuted),
                    ),
                  )
                else
                  for (final group in groups)
                    ChecklistBrandCard(
                      onTap: () => _openCampus(group),
                      child: Row(
                        children: [
                          ChecklistIconWell(
                            icon: group.campus != null
                                ? Icons.account_balance_rounded
                                : Icons.apartment_rounded,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  group.titleFor(widget.language),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    color: ChecklistChrome.ink,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.language == 'ar'
                                      ? '${group.checklists.length} قوائم فحص'
                                      : '${group.checklists.length} checklists',
                                  style: TextStyle(
                                    color: ChecklistChrome.inkMuted,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: ChecklistChrome.accent,
                          ),
                        ],
                      ),
                    ),
              ],
            ),
    );
  }
}

/// Lists building/area checklists nested under a campus site.
class EntryCampusScreen extends ConsumerWidget {
  const EntryCampusScreen({
    super.key,
    required this.profile,
    required this.group,
    required this.language,
    required this.onLanguageChanged,
  });

  final Profile profile;
  final CampusChecklistGroup group;
  final String language;
  final ValueChanged<String> onLanguageChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L = AppLabels(language);
    return Scaffold(
      appBar: checklistGradientAppBar(
        title: group.titleFor(language),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Text(
            L.siteChecklists,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: ChecklistChrome.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            L.selectChecklistHint,
            style: TextStyle(color: ChecklistChrome.inkMuted),
          ),
          const SizedBox(height: 16),
          for (final site in group.checklists)
            ChecklistBrandCard(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => EntrySiteScreen(
                      profile: profile,
                      site: site,
                      language: language,
                      onLanguageChanged: onLanguageChanged,
                    ),
                  ),
                );
              },
              child: Row(
                children: [
                  ChecklistIconWell(icon: Icons.checklist_rtl_rounded),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          site.nameFor(language),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: ChecklistChrome.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${site.buildingCode} · ${site.checklistType}',
                          style: TextStyle(
                            color: ChecklistChrome.inkMuted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: ChecklistChrome.accent),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class EntrySiteScreen extends ConsumerStatefulWidget {
  const EntrySiteScreen({
    super.key,
    required this.profile,
    required this.site,
    required this.language,
    required this.onLanguageChanged,
  });

  final Profile profile;
  final ChecklistSite site;
  final String language;
  final ValueChanged<String> onLanguageChanged;

  @override
  ConsumerState<EntrySiteScreen> createState() => _EntrySiteScreenState();
}

class _EntrySiteScreenState extends ConsumerState<EntrySiteScreen> {
  DateTime date = DateTime.now();
  Inspection? inspection;
  Map<int, InspectionItem> previousByIndex = {};
  ChecklistOrgPolicy? policy;
  Set<int> overdueIndexes = {};
  bool loading = true;
  bool saving = false;
  String? message;
  late String language;
  final SignatureController _signature = SignatureController(
    penStrokeWidth: 2.6,
    // Classic blue ink (ballpoint) — matches paper form signature look.
    penColor: const Color(0xFF0B3D91),
    exportBackgroundColor: Colors.white,
    exportPenColor: const Color(0xFF0B3D91),
  );
  String? _signaturePreviewUrl;
  Uint8List? _signaturePreviewBytes;

  AppLabels get L => AppLabels(language);

  @override
  void initState() {
    super.initState();
    language = widget.language;
    _loadOrCreate();
  }

  @override
  void dispose() {
    _signature.dispose();
    super.dispose();
  }

  void _setLanguage(String code) {
    setState(() => language = code);
    widget.onLanguageChanged(code);
  }

  Future<void> _refreshSignaturePreview() async {
    final path = inspection?.signaturePath;
    if (path == null || path.isEmpty) {
      setState(() {
        _signaturePreviewUrl = null;
        _signaturePreviewBytes = null;
      });
      return;
    }
    final bytes =
        await ref.read(inspectionRepositoryProvider).downloadBytes(path);
    if (!mounted) return;
    if (bytes != null && bytes.isNotEmpty) {
      setState(() {
        _signaturePreviewBytes =
            recolorSignatureToBlueInk(Uint8List.fromList(bytes));
        _signaturePreviewUrl = null;
      });
      return;
    }
    final url = await ref.read(inspectionRepositoryProvider).signedUrl(path);
    if (mounted) {
      setState(() {
        _signaturePreviewUrl = url;
        _signaturePreviewBytes = null;
      });
    }
  }

  Future<bool> _persistSignature() async {
    final current = inspection;
    if (current == null) return false;
    if (current.signaturePath != null &&
        current.signaturePath!.isNotEmpty &&
        !_signature.isNotEmpty) {
      return true;
    }
    if (!_signature.isNotEmpty) return false;
    final raw = await _signature.toPngBytes();
    if (raw == null || raw.isEmpty) return false;
    final bytes = recolorSignatureToBlueInk(Uint8List.fromList(raw));
    final orgId = widget.site.organizationId.isNotEmpty
        ? widget.site.organizationId
        : current.organizationId;
    final path = await ref.read(inspectionRepositoryProvider).uploadBytes(
          organizationId: orgId,
          siteId: widget.site.id,
          inspectionId: current.id,
          fileName: 'signature.png',
          bytes: bytes,
          contentType: 'image/png',
        );
    current.signaturePath = path;
    return true;
  }

  Future<void> _loadHistory(Inspection current) async {
    final prev = await ref.read(inspectionRepositoryProvider).getPreviousForSite(
          siteId: widget.site.id,
          beforeDate: current.inspectionDate,
        );
    final lookback = current.items.isEmpty
        ? 14
        : current.items
            .map((e) => e.overdueAfterDays)
            .fold<int>(14, (a, b) => math.max(a, b + 2));
    final history =
        await ref.read(inspectionRepositoryProvider).listRecentForSite(
              siteId: widget.site.id,
              asOfDate: current.inspectionDate,
              lookbackDays: lookback,
            );
    final map = buildProblemHistory(history: history, current: current);
    final overdue = overdueItemIndexes(
      inspection: current,
      problemByDateIso: map,
    );
    if (!mounted) return;
    setState(() {
      previousByIndex = {
        for (final i in prev?.items ?? const <InspectionItem>[]) i.itemIndex: i,
      };
      overdueIndexes = overdue;
    });
  }

  Future<void> _loadOrCreate() async {
    setState(() {
      loading = true;
      message = null;
    });
    try {
      final repo = ref.read(inspectionRepositoryProvider);
      var existing = await repo.getForSiteDate(
        siteId: widget.site.id,
        date: date,
      );
      existing ??= await repo.createDraft(
        site: widget.site,
        date: date,
        inspectorName: widget.profile.fullName,
        inspectionTime: DateFormat('h:mm a').format(DateTime.now()),
        language: language,
      );
      final orgId = widget.site.organizationId.isNotEmpty
          ? widget.site.organizationId
          : existing.organizationId;
      ChecklistOrgPolicy? pol;
      if (orgId.isNotEmpty) {
        pol = await ref.read(policyRepositoryProvider).getOrCreate(orgId);
      }
      setState(() {
        inspection = existing;
        policy = pol;
      });
      await _loadHistory(existing);
      await _refreshSignaturePreview();
    } catch (e) {
      setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<bool> _gatePhotos() async {
    final current = inspection;
    final pol = policy ??
        ChecklistOrgPolicy(
          organizationId: widget.site.organizationId,
        );
    if (current == null) return false;
    final result = validateEntryPhotos(
      inspection: current,
      policy: pol,
      previousByIndex: previousByIndex,
    );
    if (result.ok) return true;
    final msg = result.messageFor(language);
    if (result.severity == PolicySeverity.info) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
      return true;
    }
    if (result.severity == PolicySeverity.warning) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(L.photoRequired),
          content: Text(msg),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(L.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(L.send),
            ),
          ],
        ),
      );
      return proceed == true;
    }
    // critical / default: block
    setState(() => message = msg);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
    return false;
  }

  Future<void> _save() async {
    final current = inspection;
    if (current == null || current.isSubmitted) return;
    setState(() => saving = true);
    try {
      final signed = await _persistSignature();
      if (!signed &&
          (current.signaturePath == null || current.signaturePath!.isEmpty)) {
        // Saving answers without signature is allowed; submit requires it.
      }
      await ref.read(inspectionRepositoryProvider).saveItems(current);
      await _loadHistory(current);
      await _refreshSignaturePreview();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L.success)),
        );
      }
    } catch (e) {
      setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _submit() async {
    final current = inspection;
    if (current == null || current.isSubmitted) return;
    if (!await _gatePhotos()) return;
    final signedOk = await _persistSignature();
    if (!signedOk &&
        (current.signaturePath == null || current.signaturePath!.isEmpty)) {
      setState(() {
        message = language == 'ar'
            ? 'التوقيع مطلوب قبل الإرسال'
            : 'Signature is required before submit';
      });
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L.send),
        content: Text(
          language == 'ar'
              ? 'تأكيد إرسال الفحص للمراجعة؟'
              : 'Submit this inspection for review?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(L.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(L.send),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => saving = true);
    try {
      await ref.read(inspectionRepositoryProvider).saveItems(current);
      await ref.read(inspectionRepositoryProvider).submit(current.id);
      final full =
          await ref.read(inspectionRepositoryProvider).getById(current.id);
      setState(() => inspection = full);
      await _refreshSignaturePreview();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L.awaitingApproval)),
        );
      }
    } catch (e) {
      setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _pickPhoto(InspectionItem item, {required bool isIssue}) async {
    final current = inspection;
    if (current == null || current.isSubmitted) return;

    final source = await _choosePhotoSource();
    if (source == null) return;

    try {
      final file = await ImagePicker().pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1600,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final orgId = widget.site.organizationId.isNotEmpty
          ? widget.site.organizationId
          : current.organizationId;
      final kind = isIssue ? 'issue' : 'fix';
      final path = await ref.read(inspectionRepositoryProvider).uploadBytes(
            organizationId: orgId,
            siteId: widget.site.id,
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
    } catch (e) {
      setState(() => message = e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              language == 'ar'
                  ? 'تعذّر إرفاق الصورة. اختر ملفاً من الجهاز.'
                  : 'Could not attach photo. Pick an image from this device.',
            ),
          ),
        );
      }
    }
  }

  /// Camera is unreliable on macOS desktop — prefer gallery/file there.
  Future<ImageSource?> _choosePhotoSource() async {
    final desktop = !kIsWeb &&
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
    if (desktop) {
      // Single-path on desktop: system file/photo picker via gallery source.
      return ImageSource.gallery;
    }
    if (!mounted) return null;
    return showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(L.takePhoto),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(L.gallery),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locked = inspection?.isSubmitted == true;
    final site = widget.site;
    return Scaffold(
      drawer: ChecklistSettingsDrawer(
        profile: widget.profile,
        language: language,
        onLanguageChanged: _setLanguage,
        languages: supportedLanguages,
        appIconAsset: 'assets/branding/app_icon_simple.png',
      ),
      appBar: checklistGradientAppBar(
        title: site.buildingCode,
        actions: [
          Builder(
            builder: (ctx) => IconButton(
              tooltip: language == 'ar' ? 'الإعدادات' : 'Settings',
              onPressed: () => Scaffold.of(ctx).openDrawer(),
              icon: const Icon(Icons.settings_outlined),
            ),
          ),
          TextButton(
            onPressed: saving || locked ? null : _save,
            child: Text(L.save, style: TextStyle(color: ChecklistChrome.onAccent)),
          ),
          TextButton(
            onPressed: saving || locked ? null : _submit,
            child: Text(
              locked ? '✓' : L.send,
              style: TextStyle(color: ChecklistChrome.onAccent),
            ),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: ChecklistBrandCard(
                    margin: EdgeInsets.zero,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                site.nameFor(language),
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: ChecklistChrome.ink,
                                ),
                              ),
                              Text(
                                L.inspectionItems,
                                style: TextStyle(
                                  color: ChecklistChrome.inkMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: date,
                              firstDate: DateTime(2024),
                              lastDate:
                                  DateTime.now().add(const Duration(days: 1)),
                            );
                            if (picked == null) return;
                            setState(() => date = picked);
                            await _loadOrCreate();
                          },
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(DateFormat('yyyy-MM-dd').format(date)),
                        ),
                      ],
                    ),
                  ),
                ),
                if (message != null)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(message!, style: const TextStyle(color: Colors.red)),
                  ),
                if (locked)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: ChecklistBrandCard(
                      borderColor: ChecklistChrome.accent,
                      child: Row(
                        children: [
                          Icon(Icons.lock_outline, color: ChecklistChrome.accent),
                          const SizedBox(width: 8),
                          Expanded(child: Text(L.awaitingApproval)),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: inspection == null
                      ? const SizedBox.shrink()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                          itemCount: inspection!.items.length + 1,
                          itemBuilder: (context, i) {
                            if (i == inspection!.items.length) {
                              return _SignatureCard(
                                labels: L,
                                readOnly: locked,
                                controller: _signature,
                                previewUrl: _signaturePreviewUrl,
                                previewBytes: _signaturePreviewBytes,
                                onClear: () {
                                  _signature.clear();
                                  setState(() {
                                    inspection!.signaturePath = null;
                                    _signaturePreviewUrl = null;
                                    _signaturePreviewBytes = null;
                                  });
                                },
                              );
                            }
                            final item = inspection!.items[i];
                            final prev = previousByIndex[item.itemIndex];
                            final needsFix = prev != null &&
                                prev.isProblem &&
                                item.isIdealAnswer &&
                                !item.hasFixPhoto;
                            final needsIssue =
                                item.isProblem && !item.hasIssuePhoto;
                            return _EntryItemCard(
                              labels: L,
                              language: language,
                              item: item,
                              previous: prev,
                              readOnly: locked,
                              overdue: overdueIndexes.contains(item.itemIndex),
                              needsIssuePhoto: needsIssue,
                              needsFixPhoto: needsFix,
                              onResponse: (v) =>
                                  setState(() => item.response = v),
                              onActions: (v) =>
                                  setState(() => item.actionsTaken = v),
                              onPickIssue: () =>
                                  _pickPhoto(item, isIssue: true),
                              onPickFix: () =>
                                  _pickPhoto(item, isIssue: false),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _SignatureCard extends StatelessWidget {
  const _SignatureCard({
    required this.labels,
    required this.readOnly,
    required this.controller,
    required this.previewUrl,
    this.previewBytes,
    required this.onClear,
  });

  final AppLabels labels;
  final bool readOnly;
  final SignatureController controller;
  final String? previewUrl;
  final Uint8List? previewBytes;
  final VoidCallback onClear;

  bool get _hasPreview =>
      (previewBytes != null && previewBytes!.isNotEmpty) ||
      (previewUrl != null && previewUrl!.isNotEmpty);

  Widget _previewChild() {
    if (previewBytes != null && previewBytes!.isNotEmpty) {
      return Image.memory(previewBytes!, fit: BoxFit.contain);
    }
    return Image.network(previewUrl!, fit: BoxFit.contain);
  }

  @override
  Widget build(BuildContext context) {
    return ChecklistBrandCard(
      borderColor: ChecklistChrome.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ChecklistIconWell(icon: Icons.draw_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  labels.signature,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: ChecklistChrome.ink,
                  ),
                ),
              ),
              if (!readOnly)
                TextButton(onPressed: onClear, child: Text(labels.clear)),
            ],
          ),
          const SizedBox(height: 10),
          if (_hasPreview && readOnly)
            SizedBox(height: 120, child: _previewChild())
          else if (!readOnly)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 160,
                color: Colors.white,
                child: Signature(
                  controller: controller,
                  backgroundColor: Colors.white,
                ),
              ),
            )
          else
            Text(
              labels.signature,
              style: TextStyle(color: ChecklistChrome.inkMuted),
            ),
          if (!readOnly && _hasPreview) ...[
            const SizedBox(height: 8),
            Text(
              '✓',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ChecklistChrome.accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EntryItemCard extends StatelessWidget {
  const _EntryItemCard({
    required this.labels,
    required this.language,
    required this.item,
    required this.previous,
    required this.readOnly,
    required this.overdue,
    required this.needsIssuePhoto,
    required this.needsFixPhoto,
    required this.onResponse,
    required this.onActions,
    required this.onPickIssue,
    required this.onPickFix,
  });

  final AppLabels labels;
  final String language;
  final InspectionItem item;
  final InspectionItem? previous;
  final bool readOnly;
  final bool overdue;
  final bool needsIssuePhoto;
  final bool needsFixPhoto;
  final ValueChanged<ChecklistResponse?> onResponse;
  final ValueChanged<String> onActions;
  final VoidCallback onPickIssue;
  final VoidCallback onPickFix;

  @override
  Widget build(BuildContext context) {
    final problem = item.isProblem;
    final prevProblem = previous?.isProblem == true;
    Color? border;
    var width = 1.2;
    if (overdue) {
      border = const Color(0xFFB91C1C);
      width = 1.6;
    } else if (needsFixPhoto || needsIssuePhoto) {
      border = const Color(0xFFEA580C);
      width = 1.5;
    } else if (problem) {
      border = ChecklistChrome.accent;
      width = 1.4;
    }

    return ChecklistBrandCard(
      borderColor: border,
      borderWidth: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: ChecklistChrome.primary,
                foregroundColor: ChecklistChrome.onAccent,
                child: Text(
                  '${item.itemIndex}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.descriptionFor(language),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                    color: ChecklistChrome.ink,
                  ),
                ),
              ),
              if (overdue)
                _chip(labels.overdue, const Color(0xFFB91C1C)),
              if (problem && !overdue)
                _chip(labels.problemIndicator, ChecklistChrome.accentDeep),
            ],
          ),
          if (previous != null) ...[
            const SizedBox(height: 8),
            Text(
              '${labels.previousAnswer} ${previous!.response?.label ?? '—'}'
              '${prevProblem ? ' · ${labels.previousIssue}' : ''}',
              style: TextStyle(fontSize: 12, color: ChecklistChrome.inkMuted),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final r in ChecklistResponse.values)
                ChoiceChip(
                  label: Text(
                    r == ChecklistResponse.yes
                        ? labels.yes
                        : r == ChecklistResponse.no
                            ? labels.no
                            : labels.na,
                  ),
                  selected: item.response == r,
                  onSelected: readOnly
                      ? null
                      : (sel) => onResponse(sel ? r : null),
                  selectedColor: item.response == r && item.isIdealAnswer
                      ? ChecklistChrome.accentSoft
                      : item.response == r
                          ? const Color(0xFFFECACA)
                          : null,
                ),
            ],
          ),
          const SizedBox(height: 10),
          _RemarksField(
            key: ValueKey('remarks-${item.id ?? item.itemIndex}'),
            initial: item.actionsTaken,
            readOnly: readOnly,
            label: labels.actions,
            onChanged: onActions,
          ),
          if (problem || needsIssuePhoto) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: readOnly ? null : onPickIssue,
              icon: Icon(
                item.hasIssuePhoto
                    ? Icons.check_circle
                    : Icons.camera_alt_outlined,
                size: 18,
              ),
              label: Text(
                item.hasIssuePhoto
                    ? '${labels.issuePhoto} ✓'
                    : '${labels.issuePhoto}${needsIssuePhoto ? ' *' : ''}',
              ),
            ),
          ],
          if (prevProblem) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: readOnly ? null : onPickFix,
              icon: Icon(
                item.hasFixPhoto
                    ? Icons.check_circle
                    : Icons.build_circle_outlined,
                size: 18,
              ),
              label: Text(
                item.hasFixPhoto
                    ? '${labels.repairPhoto} ✓'
                    : '${labels.takeFixPhoto}${needsFixPhoto ? ' *' : ''}',
              ),
            ),
            if (needsFixPhoto)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  labels.photoFixMessage,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFB45309),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RemarksField extends StatefulWidget {
  const _RemarksField({
    super.key,
    required this.initial,
    required this.readOnly,
    required this.label,
    required this.onChanged,
  });

  final String initial;
  final bool readOnly;
  final String label;
  final ValueChanged<String> onChanged;

  @override
  State<_RemarksField> createState() => _RemarksFieldState();
}

class _RemarksFieldState extends State<_RemarksField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      enabled: !widget.readOnly,
      controller: _ctrl,
      onChanged: widget.onChanged,
      maxLines: 2,
      decoration: InputDecoration(
        labelText: widget.label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}
