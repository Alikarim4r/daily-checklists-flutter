part of '../main.dart';

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
  LocationFilterScope locationScope = const LocationFilterScope([]);
  LocationFilterSelection locationSelection = const LocationFilterSelection();
  final Map<String, Inspection> previewInspections = {};
  DateTime date = qatarBusinessNow();
  bool filtersExpanded = true;
  bool previewLoading = false;
  bool loading = true;
  String? message;
  Timer? _syncRetryTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _syncingQueue = false;
  bool _syncingPpmQueue = false;
  int _previewGeneration = 0;

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
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (_) => _retryQueuedWhenReachable(),
    );
    _syncRetryTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _retryQueuedWhenReachable(),
    );
  }

  Future<void> _initialize() async {
    _restoreCachedSites();
    await _loadSites();
    await _loadWorkflowNotifications();
    await _syncPendingPpm();
    if (!mounted || OfflineInspectionQueue.instance.pendingCount == 0) return;
    // Retry the encrypted outbox immediately after a successful online load.
    await _syncOfflineQueue();
  }

  @override
  void dispose() {
    _syncRetryTimer?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _retryQueuedWhenReachable() async {
    if (!mounted || _syncingQueue) return;
    await _syncPendingPpm();
    if (!mounted || OfflineInspectionQueue.instance.pendingCount == 0) {
      return;
    }
    final client = ref.read(supabaseClientProvider);
    final auth = ref.read(authRepositoryProvider);
    if (!await auth.ensureActiveSession()) return;
    if (!await ChecklistConnectivity.canReachBackend(client)) return;
    if (!mounted) return;
    await _syncOfflineQueue(silentWhenOffline: true);
  }

  Future<void> _syncPendingPpm() async {
    final offline = OfflineInspectionQueue.instance;
    if (!mounted ||
        _syncingPpmQueue ||
        offline.pendingPpmCount(widget.profile.id) == 0) {
      return;
    }
    _syncingPpmQueue = true;
    try {
      final auth = ref.read(authRepositoryProvider);
      if (!await auth.ensureActiveSession()) return;
      if (!await ChecklistConnectivity.canReachBackend(
        ref.read(supabaseClientProvider),
      )) {
        return;
      }
      final ppm = ref.read(fmPpmRepositoryProvider);
      for (final pending in offline.pendingPpm(widget.profile.id)) {
        final payload = pending.value;
        try {
          await ppm.completeJob(
            payload['jobId'] as String,
            notes: payload['notes'] as String,
            readings: Map<String, dynamic>.from(payload['readings'] as Map),
            inspectionId: payload['inspectionId'] as String?,
          );
          await offline.remove(pending.key);
        } catch (e) {
          await offline.markFailure(pending.key, e);
          // Keep the evidence encrypted until a valid authenticated retry.
        }
      }
    } finally {
      _syncingPpmQueue = false;
      if (mounted) setState(() {});
    }
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
    await _syncPendingPpm();
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
        ref
            .read(locationHierarchyRepositoryProvider)
            .listMyChecklistLocationScope(
              requirement: SiteAccessRequirement.write,
            ),
      ]);
      final groups = results[0] as List<CampusChecklistGroup>;
      final orgs = results[1] as List<Organization>;
      final zones = results[2] as List<Zone>;
      final scope = results[3] as LocationFilterScope;
      if (!mounted) return;
      final sections = groupCampusGroupsByOrgThenZone(
        organizations: orgs,
        zones: zones.where((z) => z.isActive).toList(),
        groups: groups,
      );
      setState(() {
        orgSections = sections;
        locationScope = scope;
        locationSelection = scope.normalize(locationSelection);
      });
      await OfflineInspectionQueue.instance.cacheHierarchy(
        userId: widget.profile.id,
        payload: {'sections': _encodeOrgSections(sections)},
      );
      unawaited(_cacheOfflineCatalogs(sections));
      await _refreshPreviews();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        message = orgSections.isEmpty
            ? checkInUserMessage(e, widget.language)
            : (widget.language == 'ar'
                  ? 'يتم عرض آخر هيكل محفوظ حتى عودة الاتصال.'
                  : 'Showing the last saved structure until connectivity returns.');
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _restoreCachedSites() {
    final queue = OfflineInspectionQueue.instance;
    final cached = queue.cachedHierarchy(widget.profile.id);
    final raw = cached?['sections'];
    if (raw is! List) return;
    try {
      final decoded = _decodeOrgSections(raw);
      if (widget.profile.isPlatformOwner ||
          widget.profile.role == UserRole.superAdmin) {
        orgSections = decoded;
        return;
      }
      final grantedIds = queue
          .cachedOfflineSiteAccess()
          .where((access) => access.userId == widget.profile.id)
          .where((access) => access.allows(SiteAccessRequirement.write))
          .map((access) => access.siteId)
          .toSet();
      orgSections = [
        for (final section in decoded)
          if (_filterCachedZones(section.zones, grantedIds)
              case final filteredZones when filteredZones.isNotEmpty)
            OrgBrowseSection(
              organization: section.organization,
              zones: filteredZones,
            ),
      ];
    } catch (_) {
      // Ignore a cache written by an older incompatible application version.
    }
  }

  List<ZoneBrowseSection> _filterCachedZones(
    List<ZoneBrowseSection> zones,
    Set<String> grantedIds,
  ) => [
    for (final zone in zones)
      if (_filterCachedGroups(zone.groups, grantedIds) case final filteredGroups
          when filteredGroups.isNotEmpty)
        ZoneBrowseSection(zone: zone.zone, groups: filteredGroups),
  ];

  List<CampusChecklistGroup> _filterCachedGroups(
    List<CampusChecklistGroup> groups,
    Set<String> grantedIds,
  ) => [
    for (final group in groups)
      if ([
            for (final site in group.checklists)
              if (grantedIds.contains(site.id) ||
                  (group.campus != null &&
                      grantedIds.contains(group.campus!.id)))
                site,
          ]
          case final allowedChecklists when allowedChecklists.isNotEmpty)
        CampusChecklistGroup(
          campus: group.campus,
          checklists: allowedChecklists,
        ),
  ];

  Future<void> _cacheOfflineCatalogs(List<OrgBrowseSection> sections) async {
    final catalog = ref.read(catalogRepositoryProvider);
    final units = <ChecklistSite>[
      for (final section in sections)
        for (final zone in section.zones)
          for (final group in zone.groups) ...group.checklists,
    ];
    for (final site in units) {
      try {
        final items = await catalog.listEffectiveCatalogForSite(
          checklistType: site.checklistType,
          siteId: site.id,
        );
        await OfflineInspectionQueue.instance.cacheCatalog(
          siteId: site.id,
          checklistType: site.checklistType,
          items: _encodeOfflineCatalog(items),
        );
      } catch (_) {
        // One unavailable template must not make the rest of the field pack
        // unavailable. Its last encrypted snapshot, if any, is retained.
      }
    }
  }

  List<(ChecklistSite, ChecklistSite?)> get _allTargets => [
    for (final section in orgSections)
      for (final zone in section.zones)
        for (final group in zone.groups)
          for (final site in group.checklists) (site, group.campus),
  ];

  List<(ChecklistSite, ChecklistSite?)> get _visibleTargets {
    final targets = _allTargets;
    if (locationScope.leaves.isEmpty) return targets;
    final ids = locationScope
        .filteredLeaves(locationSelection)
        .map((leaf) => leaf.legacySiteId)
        .whereType<String>()
        .toSet();
    return [
      for (final target in targets)
        if (ids.contains(target.$1.id)) target,
    ];
  }

  Inspection _previewInspection(
    ChecklistSite site,
    ChecklistSite? campus,
    List<InspectionItem> items,
  ) {
    return Inspection(
      id: 'preview_${site.id}',
      siteId: site.id,
      buildingCode: site.buildingCode,
      inspectionDate: date,
      inspectionTime: '',
      floorLabel: 'ALL',
      locationLabel: site.location,
      inspectorName: widget.profile.fullName,
      inspectorUserId: widget.profile.id,
      siteNameEn: site.nameEn,
      siteNameAr: site.nameAr,
      pin: site.pin,
      organizationId: site.organizationId,
      formTheme: site.formTheme,
      formThemeAccent: site.formThemeAccent,
      parentSiteId: site.parentSiteId,
      parentFormTheme: campus?.formTheme,
      parentFormThemeAccent: campus?.formThemeAccent,
      resolvedFormTheme: site.effectiveFormTheme,
      resolvedFormThemeAccent: site.effectiveFormThemeAccent,
      formThemeSource: site.formThemeSource,
      items: items,
    );
  }

  Future<void> _refreshPreviews() async {
    final generation = ++_previewGeneration;
    final targets = _visibleTargets;
    if (!mounted) return;
    setState(() => previewLoading = true);
    final catalog = ref.read(catalogRepositoryProvider);
    final next = <String, Inspection>{};
    for (final target in targets) {
      final site = target.$1;
      var items = <InspectionItem>[];
      try {
        final rows = await catalog.listEffectiveCatalogForSite(
          checklistType: site.checklistType,
          siteId: site.id,
        );
        items = [
          for (final row in rows)
            InspectionItem(
              itemIndex: row.itemIndex,
              description: row.descriptionEn,
              descriptionAr: row.descriptionAr,
              localizedDescriptions: row.localizedDescriptions,
              defaultAnswer: row.defaultAnswer,
              isCustom: row.isCustom,
              overdueAfterDays: row.overdueAfterDays,
            ),
        ];
      } catch (_) {
        items = _decodeOfflineCatalog(
          OfflineInspectionQueue.instance.cachedCatalog(site.id),
          widget.language,
        );
      }
      if (!mounted || generation != _previewGeneration) return;
      next[site.id] = _previewInspection(site, target.$2, items);
    }
    if (!mounted || generation != _previewGeneration) return;
    setState(() {
      previewInspections
        ..clear()
        ..addAll(next);
      previewLoading = false;
    });
  }

  void _applyLocationSelection(LocationFilterSelection selection) {
    setState(() {
      locationSelection = locationScope.normalize(selection);
    });
    unawaited(_refreshPreviews());
  }

  Future<void> _pickDate() async {
    final now = qatarBusinessNow();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: date.isAfter(today) ? today : date,
      firstDate: DateTime(2024),
      lastDate: today,
    );
    if (picked == null || !mounted) return;
    setState(() => date = DateTime(picked.year, picked.month, picked.day));
    await _refreshPreviews();
  }

  Future<void> _shiftDate(int days) async {
    final now = qatarBusinessNow();
    final today = DateTime(now.year, now.month, now.day);
    final candidate = DateTime(date.year, date.month, date.day + days);
    if (candidate.isAfter(today)) return;
    setState(() => date = candidate);
    await _refreshPreviews();
  }

  bool get _canMoveDateForward {
    final now = qatarBusinessNow();
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(date.year, date.month, date.day).isBefore(today);
  }

  Future<void> _openTarget(ChecklistSite site, ChecklistSite? campus) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EntrySiteScreen(
          profile: widget.profile,
          site: site,
          parentCampus: campus,
          initialDate: date,
          language: widget.language,
          onLanguageChanged: widget.onLanguageChanged,
        ),
      ),
    );
    if (mounted) await _refreshHome();
  }

  // ignore: unused_element
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

  Future<void> _syncOfflineQueue({bool silentWhenOffline = false}) async {
    if (_syncingQueue) return;
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
    // ConsumerState.ref cannot be used after disposal. Resolve every provider
    // before the first network await so a navigation/lifecycle change during a
    // long sync cannot turn a recoverable queue operation into a widget error.
    final client = ref.read(supabaseClientProvider);
    final authRepository = ref.read(authRepositoryProvider);
    final repository = ref.read(inspectionRepositoryProvider);
    final soundEnabled = ref.read(soundEnabledProvider);
    final hapticsEnabled = ref.read(hapticsEnabledProvider);
    _syncingQueue = true;
    try {
      final sessionReady = await authRepository.ensureActiveSession();
      if (!sessionReady) {
        if (!silentWhenOffline && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                widget.language == 'ar'
                    ? 'العمل محفوظ محليًا. ستبدأ المزامنة تلقائيًا بعد استعادة الجلسة.'
                    : 'Work is saved locally. Sync will resume automatically when the session is restored.',
              ),
            ),
          );
        }
        return;
      }
      final reachable = await ChecklistConnectivity.canReachBackend(client);
      if (!reachable) {
        if (!silentWhenOffline && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                widget.language == 'ar'
                    ? 'لا يمكن الوصول إلى الخادم الآن؛ ستبقى العناصر محفوظة.'
                    : 'The server is unreachable; queued items remain safely stored.',
              ),
            ),
          );
        }
        return;
      }
      var okCount = 0;
      var savedDraftCount = 0;
      var finalizedCount = 0;
      var failedCount = 0;
      var deferredCount = 0;
      final syncErrors = <String>[];
      final draftWarnings = <String>[];
      for (final entry in pending) {
        try {
          await OfflineInspectionQueue.instance.markAttempt(entry.key);
          final payload = entry.value;
          final id = payload['inspectionId'] as String;
          final sitePayload = payload['site'];
          final site = sitePayload is Map
              ? ChecklistSite.fromJson(Map<String, dynamic>.from(sitePayload))
              : null;
          final isLocalDraft = payload['isLocalDraft'] == true;
          late Inspection full;
          if (isLocalDraft) {
            if (site == null) {
              throw const FormatException(
                'Offline draft is missing its site snapshot',
              );
            }
            final inspectionDate = DateTime.parse(
              payload['inspectionDate'] as String,
            );
            try {
              full = await repository.createDraft(
                site: site,
                date: inspectionDate,
                inspectorName: (payload['inspectorName'] as String?) ?? '',
                inspectionTime: (payload['inspectionTime'] as String?) ?? '',
                floorLabel: (payload['floorLabel'] as String?) ?? 'ALL',
                language: (payload['language'] as String?) ?? widget.language,
                clientReference: id,
                reinspectionReason: payload['reinspectionReason'] as String?,
              );
            } catch (error) {
              final text = '$error'.toLowerCase();
              final duplicatePeriod =
                  text.contains('reinspection reason is required') ||
                  text.contains('another checklist in this period') ||
                  text.contains('duplicate key') ||
                  text.contains('23505');
              if (!duplicatePeriod) rethrow;
              final existing = await repository.getForSiteDate(
                siteId: site.id,
                date: inspectionDate,
              );
              // Reconcile only with this technician's editable draft. Never
              // overwrite another person's or a finalized inspection.
              if (existing == null ||
                  existing.isSubmitted ||
                  existing.inspectorUserId != widget.profile.id) {
                rethrow;
              }
              full = existing;
            }
          } else {
            final serverInspection = await repository.getById(id);
            if (serverInspection == null) {
              throw StateError('Inspection no longer exists on the server');
            }
            final resolution = resolveOfflineSync(
              server: serverInspection,
              payload: payload,
            );
            if (resolution == OfflineSyncResolution.discardFinalizedSnapshot) {
              // Submit/approval already won on the server. This is the common
              // crash-recovery case: the network dropped before the local
              // outbox entry could be removed. Never overwrite a final record.
              await OfflineInspectionQueue.instance.remove(entry.key);
              finalizedCount++;
              continue;
            }
            if (resolution == OfflineSyncResolution.conflict) {
              final baseVersion = (payload['baseVersion'] as num?)?.toInt();
              throw StateError(
                'Sync conflict: server version ${serverInspection.version}, '
                'offline version ${baseVersion ?? 'unknown'}',
              );
            }
            full = serverInspection;

            // The previous attempt committed save (version +1) and stopped
            // before submit/removal. Matching every queued field proves this is
            // our checkpoint, so resume without overwriting concurrent edits.
            if (resolution == OfflineSyncResolution.resumeSavedCheckpoint) {
              for (final path
                  in payload['mediaToDelete'] as List? ?? const []) {
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
                  (media['contentType'] as String?) ??
                  'application/octet-stream',
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
          full.floorLabel =
              (payload['floorLabel'] as String?) ?? full.floorLabel;
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
              if (!ChecklistSubmissionValidation.requiresDraftCorrection(
                error,
              )) {
                rethrow;
              }
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
        } catch (error, stack) {
          final authRecoverable = ChecklistConnectivity.isAuthRecoveryFailure(
            error,
          );
          if (ChecklistConnectivity.isTransportFailure(error) ||
              authRecoverable) {
            await OfflineInspectionQueue.instance.markDeferred(entry.key);
            deferredCount++;
            break;
          } else {
            await OfflineInspectionQueue.instance.markFailure(entry.key, error);
            await StructuredErrorReporter.capture(
              error,
              stack,
              module: 'entry.offline_sync',
            );
            syncErrors.add('$error');
            failedCount++;
          }
        }
      }
      if (okCount > 0 || finalizedCount > 0) {
        await OfflineInspectionQueue.instance.recordSuccessfulSync();
      }
      if (!mounted) return;
      setState(() {
        if (syncErrors.isNotEmpty) {
          message = widget.language == 'ar'
              ? 'تعذرت مزامنة بعض الأعمال. افتح حالة المزامنة لإعادة المحاولة.'
              : 'Some work could not sync. Open sync status to retry.';
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
          soundEnabled: soundEnabled,
          hapticsEnabled: hapticsEnabled,
        );
      } else if (deferredCount == 0) {
        await ChecklistFeedback.success(
          soundEnabled: soundEnabled,
          hapticsEnabled: hapticsEnabled,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.language == 'ar'
                ? 'تمت مزامنة $okCount عنصر${finalizedCount > 0 ? '، وتنظيف $finalizedCount عملية مكتملة قديمة' : ''}${savedDraftCount > 0 ? '، وحُفظ $savedDraftCount كمسودة تحتاج الإكمال' : ''}${failedCount > 0 ? '، وتعذر $failedCount' : ''}${deferredCount > 0 ? '، والباقي محفوظ حتى عودة الاتصال' : ''}'
                : 'Synced $okCount item(s)${finalizedCount > 0 ? '; cleared $finalizedCount stale finalized operation(s)' : ''}${savedDraftCount > 0 ? '; $savedDraftCount saved as incomplete draft' : ''}${failedCount > 0 ? '; $failedCount failed' : ''}${deferredCount > 0 ? '; remaining work is safely queued until online' : ''}',
          ),
        ),
      );
    } finally {
      _syncingQueue = false;
    }
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
    final ar = widget.language == 'ar';
    final queue = OfflineInspectionQueue.instance;
    final targets = _visibleTargets;
    return Scaffold(
      drawer: ChecklistSettingsDrawer(
        profile: widget.profile,
        language: widget.language,
        onLanguageChanged: widget.onLanguageChanged,
        languages: supportedLanguages,
        appIconAsset: 'assets/branding/app_icon_simple.png',
        allowAccountDeletion: true,
      ),
      appBar: AppBar(
        title: const Text(checkInName),
        actions: [
          IconButton(
            tooltip: ar ? 'أعمال الصيانة الوقائية PPM' : 'PPM work orders',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PpmJobsScreen(
                  profile: widget.profile,
                  language: widget.language,
                ),
              ),
            ),
            icon: Badge(
              isLabelVisible: queue.pendingPpmCount(widget.profile.id) > 0,
              label: Text('${queue.pendingPpmCount(widget.profile.id)}'),
              child: const Icon(Icons.handyman_outlined),
            ),
          ),
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
            tooltip: ar ? 'حالة المزامنة' : 'Sync status',
            onPressed: _openSyncStatus,
            icon: Badge(
              isLabelVisible: queue.pendingCount > 0,
              label: Text('${queue.pendingCount}'),
              child: const Icon(Icons.sync_rounded),
            ),
          ),
          Builder(
            builder: (ctx) => IconButton(
              tooltip: ar ? 'الإعدادات' : 'Settings',
              onPressed: () => Scaffold.of(ctx).openDrawer(),
              icon: const Icon(Icons.settings_outlined),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChecklistLocationFilterPanel(
            scope: locationScope,
            selection: locationSelection,
            onSelectionChanged: _applyLocationSelection,
            date: date,
            onPreviousDate: loading ? null : () => _shiftDate(-1),
            onNextDate: loading || !_canMoveDateForward
                ? null
                : () => _shiftDate(1),
            onPickDate: _pickDate,
            expanded: filtersExpanded,
            onExpandedChanged: (value) =>
                setState(() => filtersExpanded = value),
            language: widget.language,
            loading: loading || previewLoading,
            maxContentWidth: 960,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
            child: CiPageWidth(
              maxWidth: 960,
              child: CiWorkHeader(
                title: ar ? 'قوائم الإدخال' : 'Entry checklists',
                subtitle: name,
                meta: [
                  CiMeta(
                    targets.length.toString() +
                        (ar ? ' قائمة متاحة' : ' available checklists'),
                    icon: Icons.fact_check_outlined,
                  ),
                  CiMeta(
                    queue.pendingCount == 0
                        ? (ar ? 'تمت المزامنة' : 'Synced')
                        : queue.pendingCount.toString() +
                              (ar ? ' بانتظار المزامنة' : ' awaiting sync'),
                    icon: queue.pendingCount == 0
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_upload_outlined,
                    tone: queue.pendingCount == 0
                        ? CiTone.good
                        : CiTone.warning,
                  ),
                ],
                trailing: IconButton(
                  tooltip: ar ? 'تحديث' : 'Refresh',
                  onPressed: loading ? null : _refreshHome,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ),
            ),
          ),
          if (message != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: CiPageWidth(
                maxWidth: 960,
                child: CiInlineNotice(
                  message: message!,
                  tone: orgSections.isEmpty ? CiTone.danger : CiTone.warning,
                ),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshHome,
              child: targets.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 36),
                      children: [
                        CiPageWidth(
                          maxWidth: 960,
                          child: CiEmptyState(
                            title: ar
                                ? 'لا توجد قوائم متاحة'
                                : 'No available checklists',
                            message: ar
                                ? 'لا توجد قوائم ضمن الصلاحيات والفلاتر الحالية.'
                                : 'No checklists match the current access scope and filters.',
                            icon: Icons.location_off_outlined,
                            action: OutlinedButton.icon(
                              onPressed: _refreshHome,
                              icon: const Icon(Icons.refresh_rounded),
                              label: Text(ar ? 'إعادة المحاولة' : 'Try again'),
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(8, 2, 8, 40),
                      itemCount: targets.length,
                      itemBuilder: (context, index) {
                        final target = targets[index];
                        final site = target.$1;
                        final campus = target.$2;
                        final preview = previewInspections[site.id];
                        return Padding(
                          key: ValueKey('entry-paper-${site.id}'),
                          padding: const EdgeInsets.only(bottom: 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 794,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                site.nameFor(widget.language),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleSmall
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                              ),
                                              Text(
                                                site.checklistType,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodySmall,
                                              ),
                                            ],
                                          ),
                                        ),
                                        FilledButton.tonalIcon(
                                          onPressed: () =>
                                              _openTarget(site, campus),
                                          icon: const Icon(
                                            Icons.edit_note_rounded,
                                            size: 18,
                                          ),
                                          label: Text(
                                            ar ? 'فتح للإدخال' : 'Open',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              if (preview == null)
                                const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              else
                                InkWell(
                                  onTap: () => _openTarget(site, campus),
                                  child: A4PaperSheet(
                                    scrollable: false,
                                    child: ChecklistFormLayout(
                                      inspection: preview,
                                      language: widget.language,
                                      forceTableLayout: true,
                                      readOnly: true,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
