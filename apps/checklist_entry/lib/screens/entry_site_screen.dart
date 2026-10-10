part of '../main.dart';

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
              : 'Stored evidence is part of the historical record and cannot be deleted in CheckIn.',
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
    } catch (error) {
      // Timer and app-lifecycle autosaves must never raise unhandled futures.
      if (mounted) {
        setState(() => message = checkInUserMessage(error, language));
      }
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
    if (current.signaturePath != null && current.signaturePath!.isNotEmpty) {
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
      } catch (error) {
        if (!ChecklistConnectivity.isTransportFailure(error)) rethrow;
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
    if (mounted) {
      setState(() => _signaturePreviewBytes = bytes);
      _signature.clear();
    }
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
        if (!mounted) return;
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
      if (!mounted) return;
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
      if (!mounted) return;
      final orgId = widget.site.organizationId.isNotEmpty
          ? widget.site.organizationId
          : existing.organizationId;
      ChecklistOrgPolicy? pol;
      if (orgId.isNotEmpty) {
        pol = await ref.read(policyRepositoryProvider).getOrCreate(orgId);
      }
      if (!mounted) return;
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
      if (mounted) setState(() => message = checkInUserMessage(e, language));
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
        setState(() => message = checkInUserMessage(e, language));
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
      if (mounted) {
        setState(() => message = checkInUserMessage(e, language));
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
        setState(() => message = checkInUserMessage(e, language));
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
        setState(() => message = checkInUserMessage(e, language));
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
        } catch (error) {
          if (!ChecklistConnectivity.isTransportFailure(error)) rethrow;
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
      setState(() => message = checkInUserMessage(e, language));
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

  Future<({Uint8List? bytes, String? url})> _loadEvidencePhoto(
    String path,
  ) async {
    if (path.startsWith('offline://')) {
      final encoded = _pendingMedia[path]?['bytesBase64'] as String?;
      if (encoded == null || encoded.isEmpty) {
        return (bytes: null, url: null);
      }
      return (bytes: Uint8List.fromList(base64Decode(encoded)), url: null);
    }
    final repository = ref.read(inspectionRepositoryProvider);
    final bytes = await repository.downloadBytes(path, forceRefresh: true);
    if (bytes != null && bytes.isNotEmpty) {
      return (bytes: bytes, url: null);
    }
    return (bytes: null, url: await repository.signedUrl(path));
  }

  Future<void> _openEvidencePhoto(String path) async {
    if (!mounted || path.trim().isEmpty) return;
    final photoFuture = _loadEvidencePhoto(path);
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.black87,
        insetPadding: const EdgeInsets.all(16),
        child: FutureBuilder<({Uint8List? bytes, String? url})>(
          future: photoFuture,
          builder: (context, snapshot) {
            Widget content;
            if (snapshot.connectionState != ConnectionState.done) {
              content = const Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError ||
                (snapshot.data?.bytes == null &&
                    (snapshot.data?.url ?? '').isEmpty)) {
              content = Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    language == 'ar'
                        ? 'تعذّر فتح الصورة. تحقق من الاتصال ثم أعد المحاولة.'
                        : 'Could not open the photo. Check the connection and retry.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              );
            } else {
              final data = snapshot.data!;
              final image = data.bytes != null
                  ? Image.memory(data.bytes!, fit: BoxFit.contain)
                  : Image.network(
                      data.url!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => Center(
                        child: Text(
                          language == 'ar'
                              ? 'تعذّر تحميل الصورة'
                              : 'Could not load photo',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    );
              content = InteractiveViewer(
                minScale: 0.5,
                maxScale: 5,
                child: Center(child: image),
              );
            }
            return ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: 280,
                minHeight: 280,
                maxWidth: 900,
                maxHeight: 700,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  content,
                  PositionedDirectional(
                    top: 4,
                    end: 4,
                    child: IconButton.filledTonal(
                      tooltip: language == 'ar' ? 'إغلاق' : 'Close',
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
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
    final items = inspection?.items ?? const <InspectionItem>[];
    final answeredCount = items.where((item) => item.response != null).length;
    final problemCount = items.where((item) => item.isProblem).length;
    final missingEvidenceCount = items.where((item) {
      final previous = previousByIndex[item.itemIndex];
      final needsIssue = item.isProblem && !item.hasIssuePhoto;
      final needsFix =
          previous != null &&
          previous.isProblem &&
          item.isIdealAnswer &&
          !item.hasFixPhoto;
      return needsIssue || needsFix;
    }).length;
    final progress = items.isEmpty ? 0.0 : answeredCount / items.length;
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
        resizeToAvoidBottomInset: true,
        // endDrawer keeps the AppBar leading free for Back (drawer would steal it).
        endDrawer: ChecklistSettingsDrawer(
          profile: widget.profile,
          language: language,
          onLanguageChanged: _setLanguage,
          languages: supportedLanguages,
          appIconAsset: 'assets/branding/app_icon_simple.png',
          allowAccountDeletion: true,
        ),
        appBar: AppBar(
          title: Text(site.buildingCode),
          actions: [
            Builder(
              builder: (ctx) => IconButton(
                tooltip: language == 'ar' ? 'الإعدادات' : 'Settings',
                onPressed: () => Scaffold.of(ctx).openEndDrawer(),
                icon: const Icon(Icons.settings_outlined),
              ),
            ),
          ],
        ),
        bottomNavigationBar: loading || inspection == null || locked
            ? null
            : CiBottomActions(
                primaryLabel: language == 'ar'
                    ? 'إرسال للمراجعة'
                    : 'Submit for review',
                onPrimary: _submit,
                secondaryLabel: L.save,
                onSecondary: _save,
                busy: saving,
              ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: CiPageWidth(
                      maxWidth: 920,
                      child: CiWorkHeader(
                        title: site.nameFor(language),
                        subtitle:
                            '${site.buildingCode} — ${site.checklistType}',
                        progress: progress,
                        progressLabel: language == 'ar'
                            ? '$answeredCount من ${items.length} مكتمل'
                            : '$answeredCount of ${items.length} complete',
                        meta: [
                          CiMeta(
                            DateFormat('yyyy-MM-dd').format(date),
                            icon: Icons.today_outlined,
                          ),
                          CiMeta(
                            language == 'ar'
                                ? '$problemCount مشكلات'
                                : '$problemCount issues',
                            icon: Icons.report_problem_outlined,
                            tone: problemCount == 0
                                ? CiTone.good
                                : CiTone.danger,
                          ),
                          CiMeta(
                            language == 'ar'
                                ? '$missingEvidenceCount أدلة مطلوبة'
                                : '$missingEvidenceCount evidence needed',
                            icon: Icons.add_a_photo_outlined,
                            tone: missingEvidenceCount == 0
                                ? CiTone.good
                                : CiTone.warning,
                          ),
                        ],
                        trailing: IconButton(
                          tooltip: language == 'ar'
                              ? 'تغيير تاريخ الفحص'
                              : 'Change inspection date',
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
                            if (picked == null || !context.mounted) return;
                            setState(() => date = picked);
                            await _loadOrCreate();
                          },
                          icon: const Icon(Icons.calendar_month_outlined),
                        ),
                      ),
                    ),
                  ),
                  if (message != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: CiPageWidth(
                        maxWidth: 920,
                        child: CiInlineNotice(
                          message: message!,
                          tone: CiTone.danger,
                        ),
                      ),
                    ),
                  if (inspection?.isReturned == true &&
                      inspection!.workflowNote?.trim().isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: CiPageWidth(
                        maxWidth: 920,
                        child: CiInlineNotice(
                          title: language == 'ar'
                              ? 'مطلوب تصحيح'
                              : 'Correction requested',
                          message: inspection!.workflowNote!,
                          tone: CiTone.warning,
                          icon: Icons.undo_outlined,
                        ),
                      ),
                    ),
                  if (locked) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: CiPageWidth(
                        maxWidth: 920,
                        child: CiPanel(
                          tone: CiTone.accent,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              CiStatusPill(
                                label: L.awaitingApproval,
                                tone: CiTone.accent,
                                icon: Icons.lock_outline_rounded,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                language == 'ar'
                                    ? 'أُرسلت هذه القائمة للمراجعة ولا يمكن تعديلها.'
                                    : 'This checklist was submitted for review and is now read-only.',
                              ),
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
                                onPressed: saving
                                    ? null
                                    : _startNewChecklistForToday,
                                icon: const Icon(Icons.add_rounded),
                                label: Text(
                                  language == 'ar'
                                      ? 'قائمة جديدة لنفس اليوم'
                                      : 'New checklist for today',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  Expanded(
                    child: inspection == null
                        ? const SizedBox.shrink()
                        : CiPageWidth(
                            maxWidth: 920,
                            child: ListView.builder(
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
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
                                  key: ValueKey(
                                    item.id ?? 'i-${item.itemIndex}',
                                  ),
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
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
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
                                  onOpenPhoto: _openEvidencePhoto,
                                  onClearIssue: (path, pairId) async {
                                    if (!_canRemoveEvidenceInEntry(path)) {
                                      _showStoredEvidenceDeleteDenied();
                                      return;
                                    }
                                    _removePendingMedia(path);
                                    _queueMediaDeletion(path);
                                    setState(() {
                                      item.removeIssueImage(
                                        path,
                                        pairId: pairId,
                                      );
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
                                    final current = inspection;
                                    if (current == null) return;
                                    final pendingPath =
                                        _canRemoveEvidenceInEntry(path);
                                    if (!pendingPath && !await _isOnline()) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              language == 'ar'
                                                  ? 'إزالة صورة إصلاح محفوظة تتطلب اتصالاً بالخادم.'
                                                  : 'Removing a stored fix photo requires a server connection.',
                                            ),
                                          ),
                                        );
                                      }
                                      return;
                                    }
                                    final pendingMedia = pendingPath
                                        ? _pendingMedia[path]
                                        : null;
                                    if (pendingPath) _removePendingMedia(path);
                                    setState(() {
                                      item.removeFixImage(path, pairId: pairId);
                                    });
                                    try {
                                      final repository = ref.read(
                                        inspectionRepositoryProvider,
                                      );
                                      if (pendingPath) {
                                        if (_isLocalInspection(current) ||
                                            !await _isOnline()) {
                                          await _enqueueOffline(
                                            current,
                                            action: 'save',
                                          );
                                        } else {
                                          await repository.saveItems(current);
                                        }
                                      } else {
                                        await repository.detachFixPhoto(
                                          inspection: current,
                                          item: item,
                                          storagePath: path,
                                        );
                                      }
                                    } catch (error, stack) {
                                      // Restore the visible relationship if the
                                      // controlled server edit cannot complete.
                                      if (mounted) {
                                        setState(() {
                                          if (pendingMedia != null) {
                                            _pendingMedia[path] = pendingMedia;
                                          }
                                          item.setFixForPair(pairId, path);
                                        });
                                      }
                                      await StructuredErrorReporter.capture(
                                        error,
                                        stack,
                                        module: 'entry.fix_photo_remove',
                                      );
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              language == 'ar'
                                                  ? 'تعذّرت إزالة صورة الإصلاح. تحقق من الاتصال وأعد المحاولة.'
                                                  : 'Could not remove the fix photo. Check the connection and retry.',
                                            ),
                                          ),
                                        );
                                      }
                                    }
                                  },
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}
