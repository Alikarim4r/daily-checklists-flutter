import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:checklist_shared/checklist_shared.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
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
  StructuredErrorReporter.install(appKey: 'entry');
  await OfflineInspectionQueue.init();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        sessionSecurityAppKeyProvider.overrideWithValue('entry'),
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
    final rtl = isRtlLanguage(language);
    final themeMode = ref.watch(themeModeProvider);
    final platformDark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
    final useDark = switch (themeMode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => platformDark,
    };
    return MaterialApp(
      key: ValueKey(useDark ? 'entry-dark' : 'entry-light'),
      title: language == 'ar' ? 'فحص إدخال' : 'Inspection Entry',
      debugShowCheckedModeBanner: false,
      theme: useDark ? ChecklistChrome.darkTheme() : ChecklistChrome.theme(),
      themeMode: ThemeMode.light,
      themeAnimationDuration: Duration.zero,
      themeAnimationStyle: AnimationStyle.noAnimation,
      builder: (context, child) => Directionality(
        textDirection: rtl ? ui.TextDirection.rtl : ui.TextDirection.ltr,
        child: ChecklistAppBackground(child: child ?? const SizedBox.shrink()),
      ),
      home: ChecklistAuthGate(
        appTitle: language == 'ar' ? 'فحص إدخال' : 'Inspection Entry',
        subtitle: language == 'ar'
            ? 'تسجيل الفحص اليومي للمرافق'
            : 'Daily facility inspection entry',
        language: language,
        onLanguageChanged: (v) => setState(() => language = v),
        allowSelfRegistration: true,
        registrationRequestedRole: 'technician_request',
        brandMarkAsset: 'assets/branding/app_icon_simple.png',
        allowedForProfile: (p) => p.isPlatformOwner || p.role.canUseEntry,
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
  List<OrgBrowseSection> orgSections = [];
  List<WorkflowNotification> workflowNotifications = [];
  bool loading = true;
  String? message;

  AppLabels get L => AppLabels(widget.language);

  int get _checklistCount =>
      orgSections.fold(0, (total, section) => total + section.checklistCount);

  List<ChecklistNotice> get _entryNotices => [
    ...workflowNotificationsToNotices(
      notifications: workflowNotifications,
      language: widget.language,
    ),
    ...buildEntryNotices(
      pendingSyncCount: OfflineInspectionQueue.instance.pendingCount,
      failedSyncCount: OfflineInspectionQueue.instance.failedCount,
      writableChecklistCount: _checklistCount,
      language: widget.language,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadSites();
    await _loadWorkflowNotifications();
    if (!mounted || OfflineInspectionQueue.instance.pendingCount == 0) return;
    // Retry the encrypted outbox immediately after a successful online load.
    await _syncOfflineQueue();
  }

  Future<void> _loadWorkflowNotifications() async {
    try {
      final rows = await ref.read(notificationRepositoryProvider).listUnread();
      if (mounted) setState(() => workflowNotifications = rows);
    } catch (_) {
      // Keep local/offline notices available during a migration or outage.
    }
  }

  Future<void> _refreshHome() async {
    await Future.wait([_loadSites(), _loadWorkflowNotifications()]);
  }

  Future<void> _loadSites() async {
    setState(() {
      loading = true;
      message = null;
    });
    try {
      final results = await Future.wait<Object>([
        ref
            .read(siteRepositoryProvider)
            .listWritableCampusGroups(profile: widget.profile),
        ref
            .read(organizationRepositoryProvider)
            .listOrganizations(activeOnly: true),
        ref.read(organizationRepositoryProvider).listAllZones(),
      ]);
      final groups = results[0] as List<CampusChecklistGroup>;
      final orgs = results[1] as List<Organization>;
      final zones = results[2] as List<Zone>;
      final sections = groupCampusGroupsByOrgThenZone(
        organizations: orgs,
        zones: zones.where((z) => z.isActive).toList(),
        groups: groups,
      );
      setState(() => orgSections = sections);
    } catch (e) {
      setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _openOrg(OrgBrowseSection org) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EntryZonesScreen(
          profile: widget.profile,
          section: org,
          language: widget.language,
          onLanguageChanged: widget.onLanguageChanged,
        ),
      ),
    );
  }

  Future<void> _syncOfflineQueue() async {
    final pending = OfflineInspectionQueue.instance.pending();
    if (pending.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.language == 'ar'
                ? 'لا توجد عناصر للمزامنة'
                : 'Nothing to sync',
          ),
        ),
      );
      return;
    }
    var okCount = 0;
    var savedDraftCount = 0;
    final syncErrors = <String>[];
    final draftWarnings = <String>[];
    for (final entry in pending) {
      try {
        await OfflineInspectionQueue.instance.markAttempt(entry.key);
        final payload = entry.value;
        final id = payload['inspectionId'] as String;
        final repository = ref.read(inspectionRepositoryProvider);
        final sitePayload = payload['site'];
        final site = sitePayload is Map
            ? ChecklistSite.fromJson(Map<String, dynamic>.from(sitePayload))
            : null;
        final isLocalDraft = payload['isLocalDraft'] == true;
        final Inspection full;
        if (isLocalDraft) {
          if (site == null) {
            throw const FormatException(
              'Offline draft is missing its site snapshot',
            );
          }
          full = await repository.createDraft(
            site: site,
            date: DateTime.parse(payload['inspectionDate'] as String),
            inspectorName: (payload['inspectorName'] as String?) ?? '',
            inspectionTime: (payload['inspectionTime'] as String?) ?? '',
            floorLabel: (payload['floorLabel'] as String?) ?? 'ALL',
            language: (payload['language'] as String?) ?? widget.language,
            clientReference: id,
            reinspectionReason: payload['reinspectionReason'] as String?,
          );
        } else {
          final serverInspection = await repository.getById(id);
          if (serverInspection == null) {
            throw StateError('Inspection no longer exists on the server');
          }
          final baseVersion = (payload['baseVersion'] as num?)?.toInt();
          final canResumeSavedCheckpoint =
              baseVersion != null &&
              serverInspection.version == baseVersion + 1 &&
              queuedInspectionMatchesServer(
                server: serverInspection,
                payload: payload,
              );
          if (baseVersion != null &&
              baseVersion != serverInspection.version &&
              !canResumeSavedCheckpoint) {
            throw StateError(
              'Sync conflict: server version ${serverInspection.version}, '
              'offline version $baseVersion',
            );
          }
          full = serverInspection;

          // The previous attempt committed save (version +1) and stopped
          // before submit/removal. Matching every queued field proves this is
          // our checkpoint, so resume without overwriting concurrent edits.
          if (canResumeSavedCheckpoint) {
            for (final path in payload['mediaToDelete'] as List? ?? const []) {
              try {
                await repository.deleteMedia('$path');
              } catch (_) {
                // Record state is already correct; lifecycle cleanup can retry.
              }
            }
            if (payload['action'] == 'submit' && !full.isSubmitted) {
              try {
                await repository.submit(full);
              } catch (error) {
                if (!ChecklistSubmissionValidation.requiresDraftCorrection(
                  error,
                )) {
                  rethrow;
                }
                // save already committed and matches the encrypted outbox.
                // Keep the server draft, clear the queue, and ask the operator
                // to correct the explicitly reported validation items.
                await OfflineInspectionQueue.instance.remove(entry.key);
                savedDraftCount++;
                draftWarnings.add(
                  ChecklistSubmissionValidation.messageFor(
                    error,
                    widget.language,
                  ),
                );
                continue;
              }
            }
            await OfflineInspectionQueue.instance.remove(entry.key);
            okCount++;
            continue;
          }
        }

        // A previous attempt may have committed submit successfully and lost
        // connectivity before removing the outbox entry. Treat it as done.
        if (payload['action'] == 'submit' && full.isSubmitted) {
          await OfflineInspectionQueue.instance.remove(entry.key);
          okCount++;
          continue;
        }

        final replacements = <String, String>{};
        final mediaRaw = payload['media'] as List? ?? const [];
        for (final raw in mediaRaw) {
          final media = Map<String, dynamic>.from(raw as Map);
          final placeholder = media['placeholder'] as String?;
          final encoded = media['bytesBase64'] as String?;
          final fileName = media['fileName'] as String?;
          final kind = media['kind'] as String?;
          final itemIndex = (media['itemIndex'] as num?)?.toInt();
          if (placeholder == null ||
              encoded == null ||
              fileName == null ||
              !placeholder.startsWith('offline://')) {
            throw const FormatException('Invalid offline media payload');
          }
          final path = await repository.uploadBytes(
            organizationId: site?.organizationId ?? full.organizationId,
            siteId: site?.id ?? full.siteId,
            inspectionId: full.id,
            fileName: fileName,
            bytes: Uint8List.fromList(base64Decode(encoded)),
            contentType:
                (media['contentType'] as String?) ?? 'application/octet-stream',
            evidenceItemId: itemIndex == null || itemIndex == 0
                ? null
                : full.items
                      .where((item) => item.itemIndex == itemIndex)
                      .firstOrNull
                      ?.id,
            evidenceKind: kind == 'signature'
                ? 'signature'
                : kind == 'issue'
                ? 'issue_photo'
                : kind == 'fix'
                ? 'fix_photo'
                : null,
          );
          replacements[placeholder] = path;
        }

        String? replacePendingPath(String? raw) {
          if (raw == null) return null;
          var next = raw;
          for (final replacement in replacements.entries) {
            next = next.replaceAll(replacement.key, replacement.value);
          }
          return next;
        }

        full.inspectorName =
            (payload['inspectorName'] as String?) ?? full.inspectorName;
        full.inspectionTime =
            (payload['inspectionTime'] as String?) ?? full.inspectionTime;
        full.floorLabel = (payload['floorLabel'] as String?) ?? full.floorLabel;
        full.signaturePath = replacePendingPath(
          (payload['signaturePath'] as String?) ?? full.signaturePath,
        );
        final itemsRaw = payload['items'] as List? ?? const [];
        for (final raw in itemsRaw) {
          final map = Map<String, dynamic>.from(raw as Map);
          for (final field in const [
            'image_path',
            'issue_image_path',
            'fix_image_path',
          ]) {
            map[field] = replacePendingPath(map[field] as String?);
          }
          final index = map['item_index'] as int?;
          InspectionItem? match;
          if (index != null) {
            for (final item in full.items) {
              if (item.itemIndex == index) {
                match = item;
                break;
              }
            }
          }
          final queued = InspectionItem.fromJson(map);
          if (match != null) {
            match.response = queued.response;
            match.actionsTaken = queued.actionsTaken;
            match.setPhotoPairs(queued.photoPairs);
          } else {
            full.items.add(queued);
          }
        }
        await repository.saveItems(full);
        for (final path in payload['mediaToDelete'] as List? ?? const []) {
          try {
            await repository.deleteMedia('$path');
          } catch (_) {
            // The record is already detached from this object. Server-side
            // lifecycle cleanup can remove an object that transiently fails.
          }
        }
        if (payload['action'] == 'submit' && !full.isSubmitted) {
          try {
            await repository.submit(full);
          } catch (error) {
            if (!ChecklistSubmissionValidation.requiresDraftCorrection(error)) {
              rethrow;
            }
            await OfflineInspectionQueue.instance.remove(entry.key);
            savedDraftCount++;
            draftWarnings.add(
              ChecklistSubmissionValidation.messageFor(error, widget.language),
            );
            continue;
          }
        }
        await OfflineInspectionQueue.instance.remove(entry.key);
        okCount++;
      } catch (error, stack) {
        await OfflineInspectionQueue.instance.markFailure(entry.key, error);
        await StructuredErrorReporter.capture(
          error,
          stack,
          module: 'entry.offline_sync',
        );
        syncErrors.add('$error');
      }
    }
    if (okCount > 0) {
      await OfflineInspectionQueue.instance.recordSuccessfulSync();
    }
    if (!mounted) return;
    final failedCount = pending.length - okCount - savedDraftCount;
    setState(() {
      if (syncErrors.isNotEmpty) {
        message = widget.language == 'ar'
            ? 'تعذرت المزامنة: ${syncErrors.first}'
            : 'Sync failed: ${syncErrors.first}';
      } else if (draftWarnings.isNotEmpty) {
        message = widget.language == 'ar'
            ? 'حُفظت القائمة كمسودة وتحتاج إلى إكمالها: ${draftWarnings.first}'
            : 'Saved as draft; complete it before submitting: ${draftWarnings.first}';
      } else {
        message = null;
      }
    });
    if (failedCount > 0 || savedDraftCount > 0) {
      await ChecklistFeedback.alert(
        soundEnabled: ref.read(soundEnabledProvider),
        hapticsEnabled: ref.read(hapticsEnabledProvider),
      );
    } else {
      await ChecklistFeedback.success(
        soundEnabled: ref.read(soundEnabledProvider),
        hapticsEnabled: ref.read(hapticsEnabledProvider),
      );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.language == 'ar'
              ? 'تمت مزامنة $okCount عنصر${savedDraftCount > 0 ? '، وحُفظ $savedDraftCount كمسودة تحتاج الإكمال' : ''}${failedCount > 0 ? '، وتعذر $failedCount' : ''}'
              : 'Synced $okCount item(s)${savedDraftCount > 0 ? '; $savedDraftCount saved as incomplete draft' : ''}${failedCount > 0 ? '; $failedCount failed' : ''}',
        ),
      ),
    );
  }

  Future<void> _openSyncStatus() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SyncStatusScreen(
          language: widget.language,
          onRetry: _syncOfflineQueue,
        ),
      ),
    );
    if (mounted) setState(() {});
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
        title: widget.language == 'ar' ? 'الجهات' : 'Organizations',
        actions: [
          if (ref.watch(notificationsEnabledProvider))
            ChecklistNoticeBell(
              notices: _entryNotices,
              onOpen: () => showChecklistNoticesSheet(
                context: context,
                notices: _entryNotices,
                language: widget.language,
                onTap: (inspectionId) async {
                  await ref.read(notificationRepositoryProvider).markAllRead();
                  if (mounted) {
                    setState(() => workflowNotifications = []);
                  }
                  if (OfflineInspectionQueue.instance.pendingCount > 0) {
                    await _syncOfflineQueue();
                  }
                },
              ),
            ),
          IconButton(
            tooltip: widget.language == 'ar' ? 'حالة المزامنة' : 'Sync status',
            onPressed: _openSyncStatus,
            icon: Badge(
              isLabelVisible: OfflineInspectionQueue.instance.pendingCount > 0,
              label: Text('${OfflineInspectionQueue.instance.pendingCount}'),
              child: const Icon(Icons.sync),
            ),
          ),
          IconButton(onPressed: _refreshHome, icon: const Icon(Icons.refresh)),
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
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  (widget.language == 'ar'
                      ? 'اختر الجهة، ثم المنطقة، ثم الموقع.'
                      : 'Select an organization, then a zone, then a site.'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (message != null) ...[
                  const SizedBox(height: 8),
                  Text(message!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 18),
                if (orgSections.isEmpty)
                  ChecklistBrandCard(
                    child: Text(
                      widget.language == 'ar'
                          ? 'لا توجد مواقع مصرّح لك بالإدخال.'
                          : 'No writable sites assigned to your account.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  for (final org in orgSections)
                    ChecklistBrandCard(
                      onTap: () => _openOrg(org),
                      child: Row(
                        children: [
                          ChecklistIconWell(
                            icon: Icons.account_balance_rounded,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  org.organization.nameFor(widget.language),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.language == 'ar'
                                      ? '${org.zones.length} مناطق · ${org.campusCount} مواقع'
                                      : '${org.zones.length} zones · ${org.campusCount} sites',
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
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

class _SyncStatusScreen extends StatefulWidget {
  const _SyncStatusScreen({required this.language, required this.onRetry});

  final String language;
  final Future<void> Function() onRetry;

  @override
  State<_SyncStatusScreen> createState() => _SyncStatusScreenState();
}

class _SyncStatusScreenState extends State<_SyncStatusScreen> {
  DateTime? lastSuccess;
  bool retrying = false;

  bool get ar => widget.language == 'ar';

  @override
  void initState() {
    super.initState();
    _loadLastSuccess();
  }

  Future<void> _loadLastSuccess() async {
    final value = await OfflineInspectionQueue.instance.lastSuccessfulSyncAt();
    if (mounted) setState(() => lastSuccess = value);
  }

  Future<void> _retry() async {
    setState(() => retrying = true);
    await widget.onRetry();
    await _loadLastSuccess();
    if (mounted) setState(() => retrying = false);
  }

  String _formatDate(DateTime? value) {
    if (value == null) return ar ? 'لا توجد مزامنة سابقة' : 'No previous sync';
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final queue = OfflineInspectionQueue.instance;
    final entries = queue.pending();
    return Scaffold(
      appBar: checklistGradientAppBar(
        title: ar ? 'حالة المزامنة' : 'Synchronization status',
        leading: checklistBackButton(context),
      ),
      body: RefreshIndicator(
        onRefresh: _retry,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _SyncMetricCard(
                  icon: Icons.cloud_done_outlined,
                  label: ar ? 'آخر مزامنة ناجحة' : 'Last successful sync',
                  value: _formatDate(lastSuccess),
                  color: const Color(0xFF15803D),
                ),
                _SyncMetricCard(
                  icon: Icons.pending_actions_outlined,
                  label: ar ? 'سجلات معلقة' : 'Pending records',
                  value: '${queue.pendingCount}',
                  color: const Color(0xFFD97706),
                ),
                _SyncMetricCard(
                  icon: Icons.photo_library_outlined,
                  label: ar ? 'صور معلقة' : 'Pending images',
                  value: '${queue.pendingImageCount}',
                  color: const Color(0xFF2563EB),
                ),
                _SyncMetricCard(
                  icon: Icons.sync_problem_outlined,
                  label: ar ? 'فشل المزامنة' : 'Sync failed',
                  value: '${queue.failedCount}',
                  color: const Color(0xFFB91C1C),
                ),
              ],
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: retrying || entries.isEmpty ? null : _retry,
              icon: retrying
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              label: Text(ar ? 'إعادة المحاولة الآن' : 'Retry now'),
            ),
            const SizedBox(height: 18),
            Text(
              ar ? 'تفاصيل السجلات المحلية' : 'Local queue details',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (entries.isEmpty)
              ChecklistBrandCard(
                child: ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text(
                    ar ? 'كل السجلات متزامنة' : 'All records are synchronized',
                  ),
                ),
              )
            else
              for (final entry in entries) _queueTile(entry),
          ],
        ),
      ),
    );
  }

  Widget _queueTile(MapEntry<String, Map<String, dynamic>> entry) {
    final meta = Map<String, dynamic>.from(
      entry.value['_queue'] as Map? ?? const {},
    );
    final status = '${meta['status'] ?? 'pending'}';
    final failed = status == 'failed';
    final building =
        '${(entry.value['site'] as Map?)?['building_code'] ?? entry.value['buildingCode'] ?? entry.key}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ChecklistBrandCard(
        child: ListTile(
          leading: Icon(
            failed ? Icons.error_outline : Icons.schedule_outlined,
            color: failed ? Colors.red : Colors.orange,
          ),
          title: Text(building, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            failed
                ? (ar
                      ? 'يتطلب إعادة المحاولة: ${meta['lastError'] ?? ''}'
                      : 'Retry required: ${meta['lastError'] ?? ''}')
                : (ar ? 'بانتظار المزامنة' : 'Pending sync'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text('${meta['attempts'] ?? 0}×'),
        ),
      ),
    );
  }
}

class _SyncMetricCard extends StatelessWidget {
  const _SyncMetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 250,
    child: ChecklistBrandCard(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(label),
      ),
    ),
  );
}

/// Lists building/area checklists nested under a campus site.

class EntryZonesScreen extends ConsumerWidget {
  const EntryZonesScreen({
    super.key,
    required this.profile,
    required this.section,
    required this.language,
    required this.onLanguageChanged,
  });

  final Profile profile;
  final OrgBrowseSection section;
  final String language;
  final ValueChanged<String> onLanguageChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ar = language == 'ar';
    return Scaffold(
      appBar: AppBar(title: Text(section.organization.nameFor(language))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Text(
            ar ? 'اختر المنطقة' : 'Select a zone',
            style: TextStyle(color: ChecklistChrome.inkMuted),
          ),
          const SizedBox(height: 12),
          for (final zone in section.zones)
            ChecklistBrandCard(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => EntryCampusesScreen(
                      profile: profile,
                      organizationName: section.organization.nameFor(language),
                      zoneSection: zone,
                      language: language,
                      onLanguageChanged: onLanguageChanged,
                    ),
                  ),
                );
              },
              child: Row(
                children: [
                  ChecklistIconWell(icon: Icons.map_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          zone.titleFor(language),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: ChecklistChrome.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          ar
                              ? '${zone.groups.length} مواقع'
                              : '${zone.groups.length} sites',
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

class EntryCampusesScreen extends ConsumerWidget {
  const EntryCampusesScreen({
    super.key,
    required this.profile,
    required this.organizationName,
    required this.zoneSection,
    required this.language,
    required this.onLanguageChanged,
  });

  final Profile profile;
  final String organizationName;
  final ZoneBrowseSection zoneSection;
  final String language;
  final ValueChanged<String> onLanguageChanged;

  void _openChecklist(BuildContext context, ChecklistSite site) {
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
  }

  void _openCampus(BuildContext context, CampusChecklistGroup group) {
    if (group.checklists.length == 1 && group.campus == null) {
      _openChecklist(context, group.checklists.first);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EntryCampusScreen(
          profile: profile,
          group: group,
          language: language,
          onLanguageChanged: onLanguageChanged,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ar = language == 'ar';
    return Scaffold(
      appBar: AppBar(title: Text(zoneSection.titleFor(language))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Text(
            ar ? 'اختر الموقع' : 'Select a site',
            style: TextStyle(color: ChecklistChrome.inkMuted),
          ),
          const SizedBox(height: 4),
          Text(
            organizationName,
            style: TextStyle(color: ChecklistChrome.inkMuted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          for (final group in zoneSection.groups)
            ChecklistBrandCard(
              onTap: () => _openCampus(context, group),
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
                          group.titleFor(language),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: ChecklistChrome.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          ar
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
                  Icon(Icons.chevron_right, color: ChecklistChrome.accent),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

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
        leading: checklistBackButton(context),
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
              borderColor: site.paperTheme.border,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => EntrySiteScreen(
                      profile: profile,
                      site: site,
                      parentCampus: group.campus,
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
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: site.paperTheme.accent,
                      border: Border.all(color: Colors.black12),
                    ),
                  ),
                  const SizedBox(width: 4),
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
    this.parentCampus,
    required this.language,
    required this.onLanguageChanged,
  });

  final Profile profile;
  final ChecklistSite site;
  final ChecklistSite? parentCampus;
  final String language;
  final ValueChanged<String> onLanguageChanged;

  @override
  ConsumerState<EntrySiteScreen> createState() => _EntrySiteScreenState();
}

class _EntrySiteScreenState extends ConsumerState<EntrySiteScreen>
    with WidgetsBindingObserver {
  DateTime date = qatarBusinessNow();
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
  final Map<String, Map<String, dynamic>> _pendingMedia = {};
  final Set<String> _pendingMediaDeletes = {};
  Timer? _autoSaveTimer;
  bool _autoSaving = false;
  bool _allowPop = false;
  String? _reinspectionReason;

  AppLabels get L => AppLabels(language);

  bool _canRemoveEvidenceInEntry(String? path) =>
      path != null && path.startsWith('offline://');

  void _showStoredEvidenceDeleteDenied() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          language == 'ar'
              ? 'الدليل المحفوظ جزء من السجل التاريخي ولا يمكن حذفه من تطبيق الإدخال.'
              : 'Stored evidence is part of the historical record and cannot be deleted in Entry.',
        ),
      ),
    );
  }

  bool _isLocalInspection(Inspection value) => value.id.startsWith('local_');

  String _newLocalId() =>
      'local_${widget.profile.id}_${DateTime.now().microsecondsSinceEpoch}';

  Inspection? _restoreQueuedLocalDraft() {
    final dateIso =
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    final pending = OfflineInspectionQueue.instance.pending().reversed;
    for (final queued in pending) {
      final payload = queued.value;
      if (payload['isLocalDraft'] != true ||
          payload['inspectionDate'] != dateIso) {
        continue;
      }
      final siteRaw = payload['site'];
      if (siteRaw is! Map || siteRaw['id'] != widget.site.id) continue;
      final items = <InspectionItem>[];
      for (final raw in payload['items'] as List? ?? const []) {
        items.add(
          InspectionItem.fromJson(Map<String, dynamic>.from(raw as Map)),
        );
      }
      _pendingMedia.clear();
      for (final raw in payload['media'] as List? ?? const []) {
        final media = Map<String, dynamic>.from(raw as Map);
        final placeholder = media['placeholder'] as String?;
        if (placeholder != null) _pendingMedia[placeholder] = media;
      }
      _pendingMediaDeletes
        ..clear()
        ..addAll([
          for (final path in payload['mediaToDelete'] as List? ?? const [])
            '$path',
        ]);
      final signaturePath = payload['signaturePath'] as String?;
      _reinspectionReason = payload['reinspectionReason'] as String?;
      if (signaturePath != null) {
        final encoded = _pendingMedia[signaturePath]?['bytesBase64'] as String?;
        if (encoded != null) {
          try {
            _signaturePreviewBytes = Uint8List.fromList(base64Decode(encoded));
          } catch (_) {
            _signaturePreviewBytes = null;
          }
        }
      }
      return Inspection(
        id: payload['inspectionId'] as String,
        siteId: widget.site.id,
        buildingCode: widget.site.buildingCode,
        inspectionDate: DateTime.parse(dateIso),
        inspectionTime: (payload['inspectionTime'] as String?) ?? '',
        floorLabel: (payload['floorLabel'] as String?) ?? 'ALL',
        locationLabel: widget.site.location,
        inspectorName: (payload['inspectorName'] as String?) ?? '',
        inspectorUserId: widget.profile.id,
        signaturePath: signaturePath,
        version: (payload['baseVersion'] as num?)?.toInt() ?? 1,
        siteNameEn: widget.site.nameEn,
        siteNameAr: widget.site.nameAr,
        organizationId: widget.site.organizationId,
        formTheme: widget.site.formTheme,
        formThemeAccent: widget.site.formThemeAccent,
        parentSiteId: widget.site.parentSiteId,
        parentFormTheme: widget.parentCampus?.formTheme,
        parentFormThemeAccent: widget.parentCampus?.formThemeAccent,
        resolvedFormTheme: widget.site.effectiveFormTheme,
        resolvedFormThemeAccent: widget.site.effectiveFormThemeAccent,
        formThemeSource: widget.site.formThemeSource,
        items: items,
      );
    }
    return null;
  }

  Inspection _newOfflineDraft() {
    final repo = ref.read(inspectionRepositoryProvider);
    return Inspection(
      id: _newLocalId(),
      siteId: widget.site.id,
      buildingCode: widget.site.buildingCode,
      inspectionDate: date,
      inspectionTime: DateFormat('h:mm a').format(qatarBusinessNow()),
      floorLabel: 'ALL',
      locationLabel: widget.site.location,
      inspectorName: widget.profile.fullName,
      inspectorUserId: widget.profile.id,
      siteNameEn: widget.site.nameEn,
      siteNameAr: widget.site.nameAr,
      organizationId: widget.site.organizationId,
      formTheme: widget.site.formTheme,
      formThemeAccent: widget.site.formThemeAccent,
      parentSiteId: widget.site.parentSiteId,
      parentFormTheme: widget.parentCampus?.formTheme,
      parentFormThemeAccent: widget.parentCampus?.formThemeAccent,
      resolvedFormTheme: widget.site.effectiveFormTheme,
      resolvedFormThemeAccent: widget.site.effectiveFormThemeAccent,
      formThemeSource: widget.site.formThemeSource,
      items: repo.templateItemsFor(widget.site.checklistType, language),
    );
  }

  String _queueMedia({
    required String kind,
    required int itemIndex,
    required String fileName,
    required String contentType,
    required Uint8List bytes,
  }) {
    final placeholder =
        'offline://${DateTime.now().microsecondsSinceEpoch}_${kind}_$itemIndex';
    _pendingMedia[placeholder] = {
      'placeholder': placeholder,
      'kind': kind,
      'itemIndex': itemIndex,
      'fileName': fileName,
      'contentType': contentType,
      'bytesBase64': base64Encode(bytes),
    };
    return placeholder;
  }

  void _removePendingMedia(String path) {
    if (path.startsWith('offline://')) _pendingMedia.remove(path);
  }

  void _queueMediaDeletion(String path) {
    if (path.isEmpty || path.startsWith('offline://')) return;
    _pendingMediaDeletes.add(path);
  }

  Future<void> _deletePendingMedia() async {
    if (_pendingMediaDeletes.isEmpty) return;
    final repository = ref.read(inspectionRepositoryProvider);
    for (final path in _pendingMediaDeletes.toList()) {
      try {
        await repository.deleteMedia(path);
        _pendingMediaDeletes.remove(path);
      } catch (_) {
        // Keep it for the next save/sync attempt.
      }
    }
  }

  String? _replacePendingPath(String? raw, Map<String, String> replacements) {
    if (raw == null) return null;
    var next = raw;
    for (final entry in replacements.entries) {
      next = next.replaceAll(entry.key, entry.value);
    }
    return next;
  }

  Future<void> _uploadPendingMedia(Inspection current) async {
    if (_pendingMedia.isEmpty) return;
    final repo = ref.read(inspectionRepositoryProvider);
    final replacements = <String, String>{};
    for (final entry in _pendingMedia.entries) {
      final media = entry.value;
      final itemIndex = (media['itemIndex'] as num?)?.toInt();
      final kind = media['kind'] as String?;
      final path = await repo.uploadBytes(
        organizationId: widget.site.organizationId,
        siteId: widget.site.id,
        inspectionId: current.id,
        fileName: media['fileName'] as String,
        bytes: Uint8List.fromList(base64Decode(media['bytesBase64'] as String)),
        contentType: media['contentType'] as String,
        evidenceItemId: itemIndex == null || itemIndex == 0
            ? null
            : current.items
                  .where((item) => item.itemIndex == itemIndex)
                  .firstOrNull
                  ?.id,
        evidenceKind: kind == 'signature'
            ? 'signature'
            : kind == 'issue'
            ? 'issue_photo'
            : kind == 'fix'
            ? 'fix_photo'
            : null,
      );
      replacements[entry.key] = path;
    }
    current.signaturePath = _replacePendingPath(
      current.signaturePath,
      replacements,
    );
    for (final item in current.items) {
      item.imagePath = _replacePendingPath(item.imagePath, replacements);
      item.issueImagePath = _replacePendingPath(
        item.issueImagePath,
        replacements,
      );
      item.fixImagePath = _replacePendingPath(item.fixImagePath, replacements);
      item.setPhotoPairs(item.photoPairs);
    }
    _pendingMedia.clear();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    language = widget.language;
    _signature.addListener(_scheduleAutoSave);
    _loadOrCreate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoSaveTimer?.cancel();
    _signature.removeListener(_scheduleAutoSave);
    _signature.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _autoSaveTimer?.cancel();
      unawaited(_autoSaveNow());
    }
  }

  void _scheduleAutoSave() {
    final current = inspection;
    if (current == null || current.isSubmitted || saving) return;
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 900), _autoSaveNow);
  }

  Future<void> _autoSaveNow() async {
    final current = inspection;
    if (current == null || current.isSubmitted || _autoSaving || saving) return;
    _autoSaving = true;
    try {
      if (_signature.isNotEmpty) {
        final raw = await _signature.toPngBytes();
        if (raw != null && raw.isNotEmpty) {
          final previous = current.signaturePath;
          if (previous != null && previous.startsWith('offline://')) {
            _removePendingMedia(previous);
          }
          final bytes = recolorSignatureToBlueInk(Uint8List.fromList(raw));
          current.signaturePath = _queueMedia(
            kind: 'signature',
            itemIndex: 0,
            fileName: 'signature.png',
            contentType: 'image/png',
            bytes: bytes,
          );
          _signature.clear();
          if (mounted) {
            setState(() {
              _signaturePreviewBytes = bytes;
              _signaturePreviewUrl = null;
            });
          }
        }
      }
      await _enqueueOffline(current, action: 'save');
    } finally {
      _autoSaving = false;
    }
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
    final bytes = await ref
        .read(inspectionRepositoryProvider)
        .downloadBytes(path);
    if (!mounted) return;
    if (bytes != null && bytes.isNotEmpty) {
      setState(() {
        _signaturePreviewBytes = recolorSignatureToBlueInk(
          Uint8List.fromList(bytes),
        );
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
    String path;
    if (_isLocalInspection(current) || !await _isOnline()) {
      path = _queueMedia(
        kind: 'signature',
        itemIndex: 0,
        fileName: 'signature.png',
        contentType: 'image/png',
        bytes: bytes,
      );
    } else {
      try {
        path = await ref
            .read(inspectionRepositoryProvider)
            .uploadBytes(
              organizationId: orgId,
              siteId: widget.site.id,
              inspectionId: current.id,
              fileName: 'signature.png',
              bytes: bytes,
              contentType: 'image/png',
              evidenceKind: 'signature',
            );
      } catch (_) {
        path = _queueMedia(
          kind: 'signature',
          itemIndex: 0,
          fileName: 'signature.png',
          contentType: 'image/png',
          bytes: bytes,
        );
      }
    }
    current.signaturePath = path;
    if (mounted) setState(() => _signaturePreviewBytes = bytes);
    return true;
  }

  Future<void> _loadHistory(Inspection current) async {
    final repo = ref.read(inspectionRepositoryProvider);
    // Prefer latest other checklist (incl. same day) so open WOs carry over
    // when starting a second list today; fall back to prior calendar day.
    final prev =
        await repo.getLatestOtherForSite(
          siteId: widget.site.id,
          excludeInspectionId: current.id,
        ) ??
        await repo.getPreviousForSite(
          siteId: widget.site.id,
          beforeDate: current.inspectionDate,
        );
    final lookback = current.items.isEmpty
        ? 14
        : current.items
              .map((e) => e.overdueAfterDays)
              .fold<int>(14, (a, b) => math.max(a, b + 2));
    final history = await repo.listRecentForSite(
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
      if (!await _isOnline()) {
        final local = _restoreQueuedLocalDraft() ?? _newOfflineDraft();
        setState(() {
          inspection = local;
          policy = ChecklistOrgPolicy(
            organizationId: widget.site.organizationId,
          );
          message = language == 'ar'
              ? 'وضع دون اتصال — سيُنشأ الفحص على الخادم عند المزامنة'
              : 'Offline mode — this inspection will be created on sync';
        });
        return;
      }
      final repo = ref.read(inspectionRepositoryProvider);
      var existing = await repo.getForSiteDate(
        siteId: widget.site.id,
        date: date,
      );
      existing ??= await repo.createDraft(
        site: widget.site,
        date: date,
        inspectorName: widget.profile.fullName,
        inspectionTime: DateFormat('h:mm a').format(qatarBusinessNow()),
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
        _reinspectionReason = null;
      });
      await _loadHistory(existing);
      if (!existing.isSubmitted) {
        await _carryForwardOpenProblems(existing);
      }
      await _refreshSignaturePreview();
    } catch (e) {
      setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  /// Keep unfixed issue photos + problem answer on every new list (same day
  /// or later) until the tech attaches a fix photo and closes the WO.
  Future<void> _carryForwardOpenProblems(Inspection current) async {
    final changed = applyOpenProblemCarryForward(
      current: current,
      sourceByIndex: previousByIndex,
    );
    if (!changed) return;
    try {
      await ref.read(inspectionRepositoryProvider).saveItems(current);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        setState(() => message = e.toString());
      }
    }
  }

  Future<void> _startNewChecklistForToday() async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          language == 'ar' ? 'سبب إعادة الفحص' : 'Reinspection reason',
        ),
        content: TextField(
          controller: reasonController,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: language == 'ar'
                ? 'سبب إنشاء قائمة أخرى لنفس اليوم'
                : 'Reason for another checklist today',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(language == 'ar' ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = reasonController.text.trim();
              if (value.isNotEmpty) Navigator.pop(context, value);
            },
            child: Text(language == 'ar' ? 'متابعة' : 'Continue'),
          ),
        ],
      ),
    );
    reasonController.dispose();
    if (reason == null || !mounted) return;
    setState(() {
      loading = true;
      message = null;
      _reinspectionReason = reason;
    });
    try {
      final repo = ref.read(inspectionRepositoryProvider);
      final created = !await _isOnline()
          ? _newOfflineDraft()
          : await repo.createDraft(
              site: widget.site,
              date: date,
              inspectorName: widget.profile.fullName,
              inspectionTime: DateFormat('h:mm a').format(qatarBusinessNow()),
              language: language,
              reinspectionReason: reason,
            );
      if (!mounted) return;
      setState(() => inspection = created);
      if (_isLocalInspection(created)) {
        await _enqueueOffline(created, action: 'save');
      } else {
        await _loadHistory(created);
        await _carryForwardOpenProblems(created);
        await _refreshSignaturePreview();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              language == 'ar'
                  ? 'تم فتح قائمة جديدة لنفس اليوم'
                  : 'Started a new checklist for today',
            ),
          ),
        );
      }
    } catch (e) {
      final raw = e.toString();
      final uniqueHit =
          raw.contains('23505') ||
          raw.contains('unique') ||
          raw.contains('checklist_inspections_unique_site_date');
      if (mounted) {
        setState(() {
          message = uniqueHit
              ? (language == 'ar'
                    ? 'قاعدة البيانات ما زالت تمنع أكثر من قائمة لنفس اليوم. نفّذ ترحيل 011_allow_multiple_inspections_per_day.sql ثم أعد المحاولة.'
                    : 'Database still allows only one checklist per day. Apply migration 011_allow_multiple_inspections_per_day.sql then retry.')
              : raw;
        });
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<bool> _gatePhotos() async {
    final current = inspection;
    final pol =
        policy ??
        ChecklistOrgPolicy(organizationId: widget.site.organizationId);
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
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

  Future<bool> _gateCompletion() async {
    final current = inspection;
    if (current == null) return false;
    final missing = [
      for (final item in current.items)
        if (item.response == null) item.itemIndex,
    ];
    if (missing.isEmpty) return true;
    final value = missing.join(', ');
    final text = language == 'ar'
        ? 'يجب الإجابة عن جميع البنود قبل الإرسال. البنود الناقصة: $value'
        : 'Answer every item before submitting. Missing items: $value';
    if (mounted) {
      setState(() => message = text);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
      await ChecklistFeedback.alert(
        soundEnabled: ref.read(soundEnabledProvider),
        hapticsEnabled: ref.read(hapticsEnabledProvider),
      );
    }
    return false;
  }

  Future<bool> _isOnline() async {
    return ChecklistConnectivity.canReachBackend(
      ref.read(supabaseClientProvider),
    );
  }

  Future<void> _enqueueOffline(
    Inspection current, {
    required String action,
  }) async {
    await OfflineInspectionQueue.instance.enqueue(
      localId: current.id,
      payload: {
        'schemaVersion': 2,
        'action': action,
        'inspectionId': current.id,
        'baseVersion': _isLocalInspection(current) ? null : current.version,
        'isLocalDraft': _isLocalInspection(current),
        'inspectionDate': current.dateIso,
        'language': language,
        'reinspectionReason': _reinspectionReason,
        'site': {
          'id': widget.site.id,
          'organization_id': widget.site.organizationId,
          'zone_id': widget.site.zoneId,
          'parent_site_id': widget.site.parentSiteId,
          'name_en': widget.site.nameEn,
          'name_ar': widget.site.nameAr,
          'building_code': widget.site.buildingCode,
          'pin': widget.site.pin,
          'checklist_type': widget.site.checklistType,
          'location': widget.site.location,
          'is_active': widget.site.isActive,
          'form_theme': widget.site.formTheme,
          'form_theme_accent': widget.site.formThemeAccent,
        },
        'inspectorName': current.inspectorName,
        'inspectionTime': current.inspectionTime,
        'floorLabel': current.floorLabel,
        'signaturePath': current.signaturePath,
        'items': [for (final item in current.items) item.toRpcJson()],
        'media': _pendingMedia.values.toList(),
        'mediaToDelete': _pendingMediaDeletes.toList(),
      },
    );
  }

  Future<void> _save() async {
    final current = inspection;
    if (current == null || current.isSubmitted) return;
    _autoSaveTimer?.cancel();
    setState(() => saving = true);
    try {
      final signed = await _persistSignature();
      if (!signed &&
          (current.signaturePath == null || current.signaturePath!.isEmpty)) {
        // Saving answers without signature is allowed; submit requires it.
      }
      if (_isLocalInspection(current) || !await _isOnline()) {
        await _enqueueOffline(current, action: 'save');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                language == 'ar'
                    ? 'حُفظ محليًا — سيُزامَن عند توفر الشبكة'
                    : 'Saved offline — will sync when online',
              ),
            ),
          );
        }
        return;
      }
      await _uploadPendingMedia(current);
      await ref.read(inspectionRepositoryProvider).saveItems(current);
      await OfflineInspectionQueue.instance.remove(current.id);
      await _deletePendingMedia();
      await _refreshSignaturePreview();
      await ChecklistFeedback.success(
        soundEnabled: ref.read(soundEnabledProvider),
        hapticsEnabled: ref.read(hapticsEnabledProvider),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(L.success)));
      }
    } catch (e, stack) {
      if (ChecklistConnectivity.isTransportFailure(e)) {
        await _enqueueOffline(current, action: 'save');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                language == 'ar'
                    ? 'حُفظ محليًا — سيُزامَن عند توفر الشبكة'
                    : 'Saved offline — will sync when online',
              ),
            ),
          );
        }
        if (mounted) setState(() => message = null);
      } else if (mounted) {
        await StructuredErrorReporter.capture(e, stack, module: 'entry.save');
        setState(() => message = e.toString());
        await ChecklistFeedback.alert(
          soundEnabled: ref.read(soundEnabledProvider),
          hapticsEnabled: ref.read(hapticsEnabledProvider),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _submit() async {
    final current = inspection;
    if (current == null || current.isSubmitted) return;
    if (!await _gateCompletion()) return;
    if (!await _gatePhotos()) return;
    final signedOk = await _persistSignature();
    if (!mounted) return;
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
      if (_isLocalInspection(current) || !await _isOnline()) {
        await _enqueueOffline(current, action: 'submit');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                language == 'ar'
                    ? 'تجهيز الإرسال محليًا — سيُزامَن عند توفر الشبكة'
                    : 'Queued for submit — will sync when online',
              ),
            ),
          );
        }
        return;
      }
      await _uploadPendingMedia(current);
      await ref.read(inspectionRepositoryProvider).saveItems(current);
      await _deletePendingMedia();
      await ref.read(inspectionRepositoryProvider).submit(current);
      final full = await ref
          .read(inspectionRepositoryProvider)
          .getById(current.id);
      setState(() => inspection = full);
      await _refreshSignaturePreview();
      await ChecklistFeedback.success(
        soundEnabled: ref.read(soundEnabledProvider),
        hapticsEnabled: ref.read(hapticsEnabledProvider),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(L.awaitingApproval)));
      }
    } catch (e, stack) {
      if (ChecklistConnectivity.isTransportFailure(e)) {
        await _enqueueOffline(current, action: 'submit');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                language == 'ar'
                    ? 'تجهيز الإرسال محليًا — سيُزامَن عند توفر الشبكة'
                    : 'Queued for submit — will sync when online',
              ),
            ),
          );
        }
        if (mounted) setState(() => message = null);
      } else if (mounted) {
        await StructuredErrorReporter.capture(e, stack, module: 'entry.submit');
        setState(() => message = e.toString());
        await ChecklistFeedback.alert(
          soundEnabled: ref.read(soundEnabledProvider),
          hapticsEnabled: ref.read(hapticsEnabledProvider),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _pickPhoto(
    InspectionItem item, {
    required bool isIssue,
    String? pairId,
  }) async {
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
      final validation = ImageUploadValidation.validate(bytes);
      if (!validation.ok) {
        throw FormatException(validation.messageFor(language));
      }
      final orgId = widget.site.organizationId.isNotEmpty
          ? widget.site.organizationId
          : current.organizationId;
      final sourceLabel = language == 'ar'
          ? (source == ImageSource.camera ? 'الكاميرا' : 'المعرض')
          : (source == ImageSource.camera ? 'Camera' : 'Gallery');
      final photoCtx =
          await InspectionPhotoStampResolver(
            ref.read(supabaseClientProvider),
          ).buildContext(
            site: widget.site,
            language: language,
            buildingCode: current.buildingCode,
            inspectionDateIso: current.dateIso,
            inspectionTime: current.inspectionTime,
            itemIndex: item.itemIndex,
            itemDescription: item.descriptionFor(language),
            inspectorName: current.inspectorName,
            kindLabel: language == 'ar'
                ? (isIssue ? 'مشكلة' : 'إصلاح')
                : (isIssue ? 'Issue' : 'Repair'),
            sourceLabel: sourceLabel,
            organizationIdFallback: orgId,
          );
      final stamped = await InspectionPhotoWatermark().apply(
        imageBytes: bytes,
        context: photoCtx,
        arabic: language == 'ar',
      );
      final kind = isIssue ? 'issue' : 'fix';
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${item.itemIndex}_${kind}_$stamp.jpg';
      String path;
      if (_isLocalInspection(current) || !await _isOnline()) {
        path = _queueMedia(
          kind: kind,
          itemIndex: item.itemIndex,
          fileName: fileName,
          contentType: 'image/jpeg',
          bytes: stamped,
        );
      } else {
        try {
          path = await ref
              .read(inspectionRepositoryProvider)
              .uploadBytes(
                organizationId: orgId,
                siteId: widget.site.id,
                inspectionId: current.id,
                fileName: fileName,
                bytes: stamped,
                evidenceItemId: item.id,
                evidenceKind: '${kind}_photo',
              );
        } catch (_) {
          path = _queueMedia(
            kind: kind,
            itemIndex: item.itemIndex,
            fileName: fileName,
            contentType: 'image/jpeg',
            bytes: stamped,
          );
        }
      }
      setState(() {
        if (isIssue) {
          item.appendIssueImage(path);
        } else {
          item.appendFixImage(path, pairId: pairId);
        }
      });
      if (path.startsWith('offline://')) {
        await _enqueueOffline(current, action: 'save');
      } else {
        await ref.read(inspectionRepositoryProvider).saveItems(current);
      }
    } catch (e, stack) {
      await StructuredErrorReporter.capture(
        e,
        stack,
        module: 'entry.photo_upload',
      );
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

  /// Desktop and web use the browser/system file picker. This avoids camera
  /// capture constraints that are inconsistent across browsers and desktops.
  Future<ImageSource?> _choosePhotoSource() async {
    final desktop =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
    if (kIsWeb || desktop) {
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
    return PopScope<void>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _autoSaveNow();
        if (!mounted) return;
        setState(() => _allowPop = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      },
      child: Scaffold(
        // endDrawer keeps the AppBar leading free for Back (drawer would steal it).
        endDrawer: ChecklistSettingsDrawer(
          profile: widget.profile,
          language: language,
          onLanguageChanged: _setLanguage,
          languages: supportedLanguages,
          appIconAsset: 'assets/branding/app_icon_simple.png',
        ),
        appBar: checklistGradientAppBar(
          title: site.buildingCode,
          leading: checklistBackButton(context),
          actions: [
            Builder(
              builder: (ctx) => IconButton(
                tooltip: language == 'ar' ? 'الإعدادات' : 'Settings',
                onPressed: () => Scaffold.of(ctx).openEndDrawer(),
                icon: const Icon(Icons.settings_outlined),
              ),
            ),
            TextButton(
              onPressed: saving || locked ? null : _save,
              child: Text(
                L.save,
                style: TextStyle(color: ChecklistChrome.onAccent),
              ),
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
                              final now = qatarBusinessNow();
                              final today = DateTime(
                                now.year,
                                now.month,
                                now.day,
                              );
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: date.isAfter(today) ? today : date,
                                firstDate: DateTime(2024),
                                lastDate: today,
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
                      child: Text(
                        message!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  if (inspection?.isReturned == true &&
                      inspection!.workflowNote?.trim().isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: ChecklistBrandCard(
                        borderColor: const Color(0xFFB45309),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.undo_outlined,
                              color: Color(0xFFB45309),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                language == 'ar'
                                    ? 'أُعيدت القائمة للتصحيح: ${inspection!.workflowNote}'
                                    : 'Returned for correction: ${inspection!.workflowNote}',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (locked) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: ChecklistBrandCard(
                        borderColor: ChecklistChrome.accent,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.lock_outline,
                                  color: ChecklistChrome.accent,
                                ),
                                const SizedBox(width: 8),
                                Expanded(child: Text(L.awaitingApproval)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              language == 'ar'
                                  ? 'هذه القائمة مُرسلة. ابدأ قائمة جديدة لنفس اليوم إن احتجت.'
                                  : 'This checklist was sent. Start a new one for today if needed.',
                              style: TextStyle(
                                fontSize: 12,
                                color: ChecklistChrome.inkMuted,
                              ),
                            ),
                            const SizedBox(height: 8),
                            FilledButton.tonal(
                              onPressed: saving
                                  ? null
                                  : _startNewChecklistForToday,
                              child: Text(
                                language == 'ar'
                                    ? 'قائمة جديدة لنفس اليوم'
                                    : 'New checklist for today',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
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
                                  paperTheme: inspection!.paperTheme,
                                  readOnly:
                                      locked ||
                                      !_canRemoveEvidenceInEntry(
                                            inspection!.signaturePath,
                                          ) &&
                                          inspection!.signaturePath != null,
                                  controller: _signature,
                                  previewUrl: _signaturePreviewUrl,
                                  previewBytes: _signaturePreviewBytes,
                                  onClear: () {
                                    final oldPath = inspection!.signaturePath;
                                    if (oldPath != null &&
                                        !_canRemoveEvidenceInEntry(oldPath)) {
                                      _showStoredEvidenceDeleteDenied();
                                      return;
                                    }
                                    _signature.clear();
                                    if (oldPath != null) {
                                      _removePendingMedia(oldPath);
                                      _queueMediaDeletion(oldPath);
                                    }
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
                              final needsFix =
                                  prev != null &&
                                  prev.isProblem &&
                                  item.isIdealAnswer &&
                                  !item.hasFixPhoto;
                              final needsIssue =
                                  item.isProblem && !item.hasIssuePhoto;
                              return _EntryItemCard(
                                key: ValueKey(item.id ?? 'i-${item.itemIndex}'),
                                labels: L,
                                paperTheme: inspection!.paperTheme,
                                language: language,
                                item: item,
                                previous: prev,
                                readOnly: locked,
                                overdue: overdueIndexes.contains(
                                  item.itemIndex,
                                ),
                                needsIssuePhoto: needsIssue,
                                needsFixPhoto: needsFix,
                                onResponse: (v) {
                                  final err = item.trySetResponse(
                                    v,
                                    language: language,
                                  );
                                  if (err != null && mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(err)),
                                    );
                                  }
                                  setState(() {});
                                  _scheduleAutoSave();
                                },
                                onActions: (v) {
                                  setState(() => item.actionsTaken = v);
                                  _scheduleAutoSave();
                                },
                                onPickIssue: ([pairId]) => _pickPhoto(
                                  item,
                                  isIssue: true,
                                  pairId: pairId,
                                ),
                                onPickFix: ([pairId]) => _pickPhoto(
                                  item,
                                  isIssue: false,
                                  pairId: pairId,
                                ),
                                onClearIssue: (path, pairId) async {
                                  if (!_canRemoveEvidenceInEntry(path)) {
                                    _showStoredEvidenceDeleteDenied();
                                    return;
                                  }
                                  _removePendingMedia(path);
                                  _queueMediaDeletion(path);
                                  setState(() {
                                    item.removeIssueImage(path, pairId: pairId);
                                  });
                                  final current = inspection;
                                  if (current != null) {
                                    if (_isLocalInspection(current) ||
                                        !await _isOnline()) {
                                      await _enqueueOffline(
                                        current,
                                        action: 'save',
                                      );
                                    } else {
                                      await ref
                                          .read(inspectionRepositoryProvider)
                                          .saveItems(current);
                                      await _deletePendingMedia();
                                    }
                                  }
                                },
                                onClearFix: (path, pairId) async {
                                  if (!_canRemoveEvidenceInEntry(path)) {
                                    _showStoredEvidenceDeleteDenied();
                                    return;
                                  }
                                  _removePendingMedia(path);
                                  _queueMediaDeletion(path);
                                  setState(() {
                                    item.removeFixImage(path, pairId: pairId);
                                  });
                                  final current = inspection;
                                  if (current != null) {
                                    if (_isLocalInspection(current) ||
                                        !await _isOnline()) {
                                      await _enqueueOffline(
                                        current,
                                        action: 'save',
                                      );
                                    } else {
                                      await ref
                                          .read(inspectionRepositoryProvider)
                                          .saveItems(current);
                                      await _deletePendingMedia();
                                    }
                                  }
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _SignatureCard extends StatelessWidget {
  const _SignatureCard({
    required this.labels,
    required this.paperTheme,
    required this.readOnly,
    required this.controller,
    required this.previewUrl,
    this.previewBytes,
    required this.onClear,
  });

  final AppLabels labels;
  final FormPaperTheme paperTheme;
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
      return Image.memory(
        previewBytes!,
        fit: BoxFit.fill,
        alignment: Alignment.center,
      );
    }
    return Image.network(
      previewUrl!,
      fit: BoxFit.fill,
      alignment: Alignment.center,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!readOnly) {
      return Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 12),
        child: ChecklistSignatureEditor(
          controller: controller,
          title: labels.signature,
          clearLabel: labels.clear,
          onClear: onClear,
          height: 220,
          borderColor: paperTheme.border,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
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
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_hasPreview && readOnly)
            Container(
              height: 180,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: paperTheme.border, width: 1.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: FittedBox(
                fit: BoxFit.fill,
                child: SizedBox(
                  width: 400,
                  height: 180,
                  child: _previewChild(),
                ),
              ),
            )
          else
            Text(
              labels.signature,
              style: TextStyle(color: ChecklistChrome.inkMuted),
            ),
        ],
      ),
    );
  }
}

class _EntryItemCard extends StatelessWidget {
  const _EntryItemCard({
    super.key,
    required this.labels,
    required this.paperTheme,
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
    required this.onClearIssue,
    required this.onClearFix,
  });

  final AppLabels labels;
  final FormPaperTheme paperTheme;
  final String language;
  final InspectionItem item;
  final InspectionItem? previous;
  final bool readOnly;
  final bool overdue;
  final bool needsIssuePhoto;
  final bool needsFixPhoto;
  final ValueChanged<ChecklistResponse?> onResponse;
  final ValueChanged<String> onActions;
  final Future<void> Function([String? pairId]) onPickIssue;
  final Future<void> Function([String? pairId]) onPickFix;
  final void Function(String path, String pairId) onClearIssue;
  final void Function(String path, String pairId) onClearFix;

  bool get _ar => language == 'ar';

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
      border = paperTheme.border;
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
                backgroundColor: paperTheme.accent,
                foregroundColor: paperTheme.accentText,
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
              if (overdue) _chip(labels.overdue, const Color(0xFFB91C1C)),
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
          if (problem || needsIssuePhoto || item.photoPairs.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              _ar ? 'وحدات المشكلة / الإصلاح' : 'Issue / fix units',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
            const SizedBox(height: 6),
            for (var i = 0; i < item.photoPairs.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _EntryPhotoPairRow(
                arabic: _ar,
                unitIndex: i + 1,
                pair: item.photoPairs[i],
                readOnly: readOnly,
                labels: labels,
                canDeleteIssue:
                    item.photoPairs[i].issuePath?.startsWith('offline://') ==
                    true,
                canDeleteFix:
                    item.photoPairs[i].fixPath?.startsWith('offline://') ==
                    true,
                onPickFix: () => onPickFix(item.photoPairs[i].id),
                onClearIssue: () => onClearIssue(
                  item.photoPairs[i].issuePath!,
                  item.photoPairs[i].id,
                ),
                onClearFix: () => onClearFix(
                  item.photoPairs[i].fixPath!,
                  item.photoPairs[i].id,
                ),
              ),
            ],
            if (!readOnly) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => onPickIssue(),
                icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                label: Text(
                  _ar
                      ? 'إضافة وحدة (صورة مشكلة)${needsIssuePhoto && item.photoPairs.isEmpty ? ' *' : ''}'
                      : 'Add unit (issue photo)${needsIssuePhoto && item.photoPairs.isEmpty ? ' *' : ''}',
                ),
              ),
            ],
          ],
          if (prevProblem && needsFixPhoto)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                labels.photoFixMessage,
                style: const TextStyle(fontSize: 12, color: Color(0xFFB45309)),
              ),
            ),
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

class _EntryPhotoPairRow extends StatelessWidget {
  const _EntryPhotoPairRow({
    required this.arabic,
    required this.unitIndex,
    required this.pair,
    required this.readOnly,
    required this.labels,
    required this.canDeleteIssue,
    required this.canDeleteFix,
    required this.onPickFix,
    required this.onClearIssue,
    required this.onClearFix,
  });

  final bool arabic;
  final int unitIndex;
  final InspectionPhotoPair pair;
  final bool readOnly;
  final AppLabels labels;
  final bool canDeleteIssue;
  final bool canDeleteFix;
  final VoidCallback onPickFix;
  final VoidCallback onClearIssue;
  final VoidCallback onClearFix;

  Future<void> _showIssueActions(BuildContext context) async {
    if (readOnly || !pair.hasIssue) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!pair.hasFix)
              ListTile(
                leading: const Icon(Icons.build_circle_outlined),
                title: Text(arabic ? 'إضافة صورة إصلاح' : 'Add fix photo'),
                onTap: () => Navigator.pop(ctx, 'fix'),
              ),
            if (canDeleteIssue)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(arabic ? 'حذف صورة المشكلة' : 'Delete issue photo'),
                onTap: () => Navigator.pop(ctx, 'del'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == 'fix') onPickFix();
    if (action == 'del') onClearIssue();
  }

  @override
  Widget build(BuildContext context) {
    final label = photoPairLabel(unitIndex, arabic: arabic);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFCBD5E1)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Material(
            color: pair.hasIssue ? const Color(0xFFFEE2E2) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap:
                  readOnly || !pair.hasIssue || (pair.hasFix && !canDeleteIssue)
                  ? null
                  : () => _showIssueActions(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.image_outlined,
                      size: 20,
                      color: pair.hasIssue
                          ? const Color(0xFFB91C1C)
                          : Colors.black38,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        pair.hasIssue
                            ? (pair.hasFix && !canDeleteIssue
                                  ? (arabic
                                        ? '${labels.issuePhoto} ✓ — دليل محفوظ ومحمي'
                                        : '${labels.issuePhoto} ✓ — saved and protected')
                                  : canDeleteIssue
                                  ? (arabic
                                        ? '${labels.issuePhoto} ✓ — اضغط للإصلاح أو الحذف'
                                        : '${labels.issuePhoto} ✓ — tap for fix/delete')
                                  : (arabic
                                        ? '${labels.issuePhoto} ✓ — اضغط لإضافة الإصلاح'
                                        : '${labels.issuePhoto} ✓ — tap to add fix'))
                            : labels.issuePhoto,
                        style: TextStyle(
                          fontSize: 12,
                          color: pair.hasIssue
                              ? const Color(0xFFB91C1C)
                              : Colors.black54,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (pair.hasFix) ...[
            const SizedBox(height: 6),
            Material(
              color: const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: readOnly || !canDeleteFix
                    ? null
                    : () async {
                        final action = await showModalBottomSheet<String>(
                          context: context,
                          showDragHandle: true,
                          builder: (ctx) => SafeArea(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.delete_outline),
                                  title: Text(
                                    arabic
                                        ? 'حذف صورة الإصلاح'
                                        : 'Delete fix photo',
                                  ),
                                  onTap: () => Navigator.pop(ctx, 'del'),
                                ),
                                const SizedBox(height: 8),
                              ],
                            ),
                          ),
                        );
                        if (action == 'del') onClearFix();
                      },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.build_circle_outlined,
                        size: 20,
                        color: Color(0xFF15803D),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${labels.repairPhoto} ✓',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF15803D),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
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
