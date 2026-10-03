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
  bool loading = true;
  String? message;
  Timer? _syncRetryTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _syncingQueue = false;

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
    if (!mounted ||
        _syncingQueue ||
        OfflineInspectionQueue.instance.pendingCount == 0) {
      return;
    }
    final client = ref.read(supabaseClientProvider);
    if (!await ChecklistConnectivity.canReachBackend(client)) {
      return;
    }
    if (!mounted) return;
    await _syncOfflineQueue(silentWhenOffline: true);
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
      await OfflineInspectionQueue.instance.cacheHierarchy(
        userId: widget.profile.id,
        payload: {'sections': _encodeOrgSections(sections)},
      );
    } catch (e) {
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
    final cached = OfflineInspectionQueue.instance.cachedHierarchy(
      widget.profile.id,
    );
    final raw = cached?['sections'];
    if (raw is! List) return;
    try {
      orgSections = _decodeOrgSections(raw);
    } catch (_) {
      // Ignore a cache written by an older incompatible application version.
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
    final repository = ref.read(inspectionRepositoryProvider);
    final soundEnabled = ref.read(soundEnabledProvider);
    final hapticsEnabled = ref.read(hapticsEnabledProvider);
    _syncingQueue = true;
    try {
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
          if (ChecklistConnectivity.isTransportFailure(error)) {
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
    final date = DateFormat('yyyy-MM-dd').format(qatarBusinessNow());
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
      body: RefreshIndicator(
        onRefresh: _refreshHome,
        child: CiPageWidth(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
            children: [
              CiWorkHeader(
                title: '${L.welcome}, $name',
                subtitle: ar
                    ? 'عمل اليوم مرتب حسب الجهة والموقع'
                    : "Today's work, organized by organization and site",
                meta: [
                  CiMeta(date, icon: Icons.today_outlined),
                  CiMeta(
                    ar
                        ? '$_checklistCount قائمة'
                        : '$_checklistCount checklists',
                    icon: Icons.fact_check_outlined,
                  ),
                  CiMeta(
                    queue.pendingCount == 0
                        ? (ar ? 'تمت المزامنة' : 'Synced')
                        : (ar
                              ? '${queue.pendingCount} بانتظار المزامنة'
                              : '${queue.pendingCount} awaiting sync'),
                    icon: queue.pendingCount == 0
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_upload_outlined,
                    tone: queue.pendingCount == 0
                        ? CiTone.good
                        : CiTone.warning,
                  ),
                ],
                trailing: IconButton(
                  tooltip: ar ? 'تحديث قائمة العمل' : 'Refresh work queue',
                  onPressed: loading ? null : _refreshHome,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 12),
                CiInlineNotice(
                  message: message!,
                  tone: orgSections.isEmpty ? CiTone.danger : CiTone.warning,
                ),
              ],
              CiSectionLabel(
                title: ar ? 'مسار العمل' : 'Work queue',
                count: orgSections.length,
              ),
              if (loading && orgSections.isEmpty)
                const CiLoadingList(rows: 4)
              else if (orgSections.isEmpty)
                CiEmptyState(
                  title: ar ? 'لا توجد مواقع متاحة' : 'No assigned sites',
                  message: ar
                      ? 'لم تُعيَّن مواقع قابلة للإدخال لهذا الحساب. اطلب من المشرف مراجعة الصلاحيات.'
                      : 'No writable sites are assigned to this account. Ask an administrator to review access.',
                  icon: Icons.location_off_outlined,
                  action: OutlinedButton.icon(
                    onPressed: _refreshHome,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(ar ? 'إعادة المحاولة' : 'Try again'),
                  ),
                )
              else
                CiQueuePanel(
                  children: [
                    for (final org in orgSections)
                      CiQueueRow(
                        title: org.organization.nameFor(widget.language),
                        subtitle: ar
                            ? '${org.campusCount} مواقع متاحة'
                            : '${org.campusCount} available sites',
                        icon: Icons.domain_outlined,
                        meta: [
                          CiMeta(
                            ar
                                ? '${org.zones.length} مناطق'
                                : '${org.zones.length} zones',
                            icon: Icons.map_outlined,
                          ),
                          CiMeta(
                            ar
                                ? '${org.checklistCount} قوائم'
                                : '${org.checklistCount} checklists',
                            icon: Icons.checklist_rounded,
                          ),
                        ],
                        onTap: () => _openOrg(org),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
