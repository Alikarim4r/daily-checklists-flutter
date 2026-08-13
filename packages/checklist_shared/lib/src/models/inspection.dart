import 'enums.dart';
import '../theme/form_paper_theme.dart';
import '../utils/photo_pair.dart';
import '../utils/storage_path_list.dart';

Map<String, String> _localizedDescriptionsFromJson(Map<String, dynamic> json) {
  final descriptions = <String, String>{};
  final embedded = json['_localized_descriptions'];
  if (embedded is Map) {
    for (final entry in embedded.entries) {
      final language = '${entry.key}';
      final value = '${entry.value}'.trim();
      if (value.isNotEmpty) descriptions[language] = value;
    }
  }
  for (final language in const ['bn', 'hi', 'ml', 'tl', 'ta']) {
    final value = (json['description_$language'] as String?)?.trim();
    if (value != null && value.isNotEmpty) descriptions[language] = value;
  }
  return descriptions;
}

class InspectionItem {
  InspectionItem({
    this.id,
    required this.itemIndex,
    required this.description,
    this.descriptionAr,
    Map<String, String> localizedDescriptions = const {},
    this.response,
    this.actionsTaken = '',
    this.imagePath,
    this.issueImagePath,
    this.fixImagePath,
    this.defaultAnswer = 'Y',
    this.isCustom = false,
    this.overdueAfterDays = 3,
  }) : localizedDescriptions = Map<String, String>.of(localizedDescriptions);

  final String? id;
  final int itemIndex;
  final String description;
  final String? descriptionAr;
  final Map<String, String> localizedDescriptions;
  ChecklistResponse? response;
  String actionsTaken;
  String? imagePath;
  String? issueImagePath;
  String? fixImagePath;

  /// Expected answer from catalog: Y or N (HTML `default`).
  String defaultAnswer;
  final bool isCustom;

  /// Consecutive problem days before Overdue for this item.
  int overdueAfterDays;

  /// Linked issue↔fix pairs (preferred API).
  List<InspectionPhotoPair> get photoPairs => decodePhotoPairs(
    issueImagePath: issueImagePath,
    fixImagePath: fixImagePath,
    imagePath: imagePath,
  );

  void setPhotoPairs(List<InspectionPhotoPair> pairs) {
    final clean = <InspectionPhotoPair>[];
    for (final p in pairs) {
      if (p.isEmpty) continue;
      clean.add(
        InspectionPhotoPair(
          id: p.id.isEmpty ? newPhotoPairId() : p.id,
          issuePath: p.hasIssue ? storagePathOf(p.issuePath!) : null,
          fixPath: p.hasFix ? storagePathOf(p.fixPath!) : null,
        ),
      );
    }
    issueImagePath = encodePhotoPairsV2(clean);
    fixImagePath = encodeFixPathsMirror(clean);
    String? firstIssue;
    for (final p in clean) {
      if (p.hasIssue) {
        firstIssue = p.issuePath;
        break;
      }
    }
    imagePath = firstIssue;
  }

  List<String> get issueImagePaths => [
    for (final p in photoPairs)
      if (p.hasIssue) p.issuePath!,
  ];

  List<String> get fixImagePaths => [
    for (final p in photoPairs)
      if (p.hasFix) p.fixPath!,
  ];

  /// Stable ordered remark photos — issue then fix within each pair.
  List<({String path, RemarkPhotoKind kind, String pairId})> get remarkPhotos {
    final ordered = <({String path, RemarkPhotoKind kind, String pairId})>[];
    final seen = <String>{};
    for (final pair in photoPairs) {
      if (pair.hasIssue && seen.add(pair.issuePath!)) {
        ordered.add((
          path: pair.issuePath!,
          kind: RemarkPhotoKind.issue,
          pairId: pair.id,
        ));
      }
      if (pair.hasFix && seen.add(pair.fixPath!)) {
        ordered.add((
          path: pair.fixPath!,
          kind: RemarkPhotoKind.fix,
          pairId: pair.id,
        ));
      }
    }
    return ordered;
  }

  /// Creates a new pair with an issue photo. Returns pair id.
  String addPairWithIssue(String path) {
    final raw = storagePathOf(path);
    if (raw.isEmpty) return '';
    final id = newPhotoPairId();
    setPhotoPairs([...photoPairs, InspectionPhotoPair(id: id, issuePath: raw)]);
    return id;
  }

  /// Sets or replaces the fix photo on an existing pair.
  void setFixForPair(String pairId, String path) {
    final raw = storagePathOf(path);
    if (raw.isEmpty || pairId.isEmpty) return;
    final next = <InspectionPhotoPair>[];
    var found = false;
    for (final p in photoPairs) {
      if (p.id == pairId) {
        found = true;
        next.add(p.copyWith(fixPath: raw));
      } else {
        next.add(p);
      }
    }
    if (!found) {
      next.add(InspectionPhotoPair(id: pairId, fixPath: raw));
    }
    setPhotoPairs(next);
    applyIdealAnswerAfterFix();
  }

  /// Attach fix to [pairId], or first open pair, or a new fix-only pair.
  void appendFixImage(String path, {String? pairId}) {
    final raw = storagePathOf(path);
    if (raw.isEmpty) return;
    if (pairId != null && pairId.isNotEmpty) {
      setFixForPair(pairId, raw);
      return;
    }
    final pairs = [...photoPairs];
    final openIdx = pairs.indexWhere((p) => p.hasIssue && !p.hasFix);
    if (openIdx >= 0) {
      pairs[openIdx] = pairs[openIdx].copyWith(fixPath: raw);
      setPhotoPairs(pairs);
      applyIdealAnswerAfterFix();
      return;
    }
    setPhotoPairs([
      ...pairs,
      InspectionPhotoPair(id: newPhotoPairId(), fixPath: raw),
    ]);
    applyIdealAnswerAfterFix();
  }

  void appendIssueImage(String path) => addPairWithIssue(path);

  void removeIssueImage(String path, {String? pairId}) {
    final raw = storagePathOf(path);
    final next = <InspectionPhotoPair>[];
    for (final p in photoPairs) {
      if (pairId != null && pairId.isNotEmpty && p.id != pairId) {
        next.add(p);
        continue;
      }
      if (p.hasIssue && p.issuePath == raw) {
        final cleared = p.copyWith(clearIssue: true);
        if (!cleared.isEmpty) next.add(cleared);
      } else {
        next.add(p);
      }
    }
    setPhotoPairs(next);
  }

  void removeFixImage(String path, {String? pairId}) {
    final raw = storagePathOf(path);
    final next = <InspectionPhotoPair>[];
    for (final p in photoPairs) {
      if (pairId != null && pairId.isNotEmpty && p.id != pairId) {
        next.add(p);
        continue;
      }
      if (p.hasFix && p.fixPath == raw) {
        final cleared = p.copyWith(clearFix: true);
        if (!cleared.isEmpty) next.add(cleared);
      } else {
        next.add(p);
      }
    }
    setPhotoPairs(next);
    // Deleting the last fix while closed→ideal re-opens the problem answer.
    if (!hasFixPhoto && isIdealAnswer && hasIssuePhoto) {
      final problem = problemResponse;
      if (problem != null) response = problem;
    }
  }

  /// Legacy flat setters — zip into pairs (prefer keeping existing pair ids by index).
  void setIssueImagePaths(List<String> paths) {
    final fixes = fixImagePaths;
    final issues = [
      for (final p in paths)
        if (storagePathOf(p).isNotEmpty) storagePathOf(p),
    ];
    final existing = photoPairs;
    final n = issues.length > fixes.length ? issues.length : fixes.length;
    setPhotoPairs([
      for (var i = 0; i < n; i++)
        InspectionPhotoPair(
          id: i < existing.length ? existing[i].id : newPhotoPairId(),
          issuePath: i < issues.length ? issues[i] : null,
          fixPath: i < fixes.length ? fixes[i] : null,
        ),
    ]);
  }

  void setFixImagePaths(List<String> paths) {
    final issues = issueImagePaths;
    final fixes = [
      for (final p in paths)
        if (storagePathOf(p).isNotEmpty) storagePathOf(p),
    ];
    final existing = photoPairs;
    final n = issues.length > fixes.length ? issues.length : fixes.length;
    setPhotoPairs([
      for (var i = 0; i < n; i++)
        InspectionPhotoPair(
          id: i < existing.length ? existing[i].id : newPhotoPairId(),
          issuePath: i < issues.length ? issues[i] : null,
          fixPath: i < fixes.length ? fixes[i] : null,
        ),
    ]);
  }

  Map<String, String> get descriptions => {
    'en': description,
    if ((descriptionAr ?? '').isNotEmpty) 'ar': descriptionAr!,
    ...localizedDescriptions,
  };

  String descriptionFor(String language) =>
      descriptions[language] ?? description;

  /// Catalog healthy/default answer (Y/N).
  ChecklistResponse? get idealResponse =>
      ChecklistResponse.fromDb(defaultAnswer);

  /// Opposite of [idealResponse] (the problem option for this item).
  ChecklistResponse? get problemResponse {
    final ideal = idealResponse;
    if (ideal == ChecklistResponse.yes) return ChecklistResponse.no;
    if (ideal == ChecklistResponse.no) return ChecklistResponse.yes;
    return null;
  }

  /// After a repair photo is attached, force the healthy/default answer.
  void applyIdealAnswerAfterFix() {
    final ideal = idealResponse;
    if (ideal == null || ideal == ChecklistResponse.na) return;
    response = ideal;
  }

  /// Applies a Yes/No/NA change with photo gates based on this item's ideal.
  ///
  /// Closing a problem (problem → ideal) requires a linked fix photo.
  /// Returns an error message when blocked; `null` when applied.
  String? trySetResponse(ChecklistResponse? next, {required String language}) {
    final closingProblem =
        isProblem &&
        next != null &&
        next != ChecklistResponse.na &&
        next.shortCode == defaultAnswer.toUpperCase();
    if (closingProblem && !hasFixPhoto) {
      return language == 'ar'
          ? 'لإغلاق المشكلة وتحويل الجواب للحالة السليمة يجب رفع صورة إصلاح أولاً (مرتبطة بصورة المشكلة).'
          : 'To close the problem and select the healthy answer, attach a fix photo first (linked to the issue photo).';
    }
    response = next;
    return null;
  }

  /// Same rule as HTML `isProblemResponse`: opposite of default (not NA).
  bool get isProblem {
    final r = response;
    if (r == null || r == ChecklistResponse.na) return false;
    return r.shortCode != defaultAnswer.toUpperCase();
  }

  /// Answered and matches catalog ideal (closes a prior problem when fixing).
  bool get isIdealAnswer {
    final r = response;
    if (r == null || r == ChecklistResponse.na) return false;
    return r.shortCode == defaultAnswer.toUpperCase();
  }

  bool get hasIssuePhoto => issueImagePaths.isNotEmpty;

  bool get hasFixPhoto => fixImagePaths.isNotEmpty;

  /// HTML `getCheckColor` for a specific column value.
  ColorCode checkColorFor(ChecklistResponse column) {
    if (response != column) return ColorCode.empty;
    if (column == ChecklistResponse.na) return ColorCode.na;
    if (column.shortCode == defaultAnswer.toUpperCase()) {
      return ColorCode.ok;
    }
    return ColorCode.problem;
  }

  factory InspectionItem.fromJson(Map<String, dynamic> json) {
    final rawDefault = (json['default_answer'] ?? 'Y') as String;
    final defaultAnswer =
        ChecklistResponse.fromDb(rawDefault)?.shortCode ??
        rawDefault.toUpperCase();
    final item = InspectionItem(
      id: json['id'] as String?,
      itemIndex: json['item_index'] as int,
      description: (json['description'] ?? '') as String,
      descriptionAr: json['description_ar'] as String?,
      localizedDescriptions: _localizedDescriptionsFromJson(json),
      response: ChecklistResponse.fromDb(json['response'] as String?),
      actionsTaken: (json['actions_taken'] ?? '') as String,
      imagePath: json['image_path'] as String?,
      issueImagePath: json['issue_image_path'] as String?,
      fixImagePath: json['fix_image_path'] as String?,
      defaultAnswer: defaultAnswer,
      isCustom: json['is_custom'] as bool? ?? false,
      overdueAfterDays: (json['overdue_after_days'] as num?)?.toInt() ?? 3,
    );
    // Normalize to v2 pairs on load so subsequent saves keep pairing.
    item.setPhotoPairs(item.photoPairs);
    return item;
  }

  Map<String, dynamic> toInsertJson(String inspectionId) => {
    'inspection_id': inspectionId,
    'item_index': itemIndex,
    'description': description,
    if (descriptionAr != null) 'description_ar': descriptionAr,
    for (final language in const ['bn', 'hi', 'ml', 'tl', 'ta'])
      'description_$language': localizedDescriptions[language],
    'response': response?.dbValue,
    'actions_taken': actionsTaken,
    'image_path': _firstIssueRawPath,
    'issue_image_path': issueImagePath,
    'fix_image_path': fixImagePath,
    'default_answer': defaultAnswer,
    'is_custom': isCustom,
    'overdue_after_days': overdueAfterDays,
  };

  Map<String, dynamic> toUpdateJson() => {
    'response': response?.dbValue,
    'actions_taken': actionsTaken,
    'image_path': _firstIssueRawPath,
    'issue_image_path': issueImagePath,
    'fix_image_path': fixImagePath,
    'default_answer': defaultAnswer,
    'overdue_after_days': overdueAfterDays,
  };

  Map<String, dynamic> toRpcJson() => {
    if (id != null) 'id': id,
    'item_index': itemIndex,
    'description': description,
    'description_ar': descriptionAr,
    '_localized_descriptions': localizedDescriptions,
    'response': response?.dbValue,
    'actions_taken': actionsTaken,
    'image_path': _firstIssueRawPath,
    'issue_image_path': issueImagePath,
    'fix_image_path': fixImagePath,
    'default_answer': defaultAnswer,
    'is_custom': isCustom,
    'overdue_after_days': overdueAfterDays,
  };

  String? get _firstIssueRawPath {
    for (final p in photoPairs) {
      if (p.hasIssue) return p.issuePath;
    }
    return null;
  }
}

enum ColorCode { empty, ok, problem, na }

class Inspection {
  Inspection({
    required this.id,
    required this.siteId,
    required this.buildingCode,
    required this.inspectionDate,
    this.inspectionTime = '',
    this.floorLabel = 'ALL',
    this.locationLabel = 'MOEHE Permanent Headquarters',
    this.inspectorName = '',
    this.inspectorUserId,
    this.signaturePath,
    this.status = InspectionStatus.draft,
    this.reviewStatus = ReviewStatus.draft,
    this.submittedAt,
    this.submittedBy,
    this.approvedAt,
    this.approvedBy,
    this.workflowNote,
    this.workflowChangedAt,
    this.workflowChangedBy,
    this.createdAt,
    this.updatedAt,
    this.version = 1,
    this.referenceNo = '',
    this.templateId,
    this.templateCodeSnapshot,
    this.templateVersionSnapshot,
    this.templateNameEnSnapshot,
    this.templateNameArSnapshot,
    List<InspectionItem>? items,
    this.siteNameEn = '',
    this.siteNameAr = '',
    this.pin = '',
    this.organizationId = '',
    this.formTheme = 'classic_gold',
    this.formThemeAccent,
    this.parentSiteId,
    this.parentFormTheme,
    this.parentFormThemeAccent,
    this.resolvedFormTheme,
    this.resolvedFormThemeAccent,
    this.formThemeSource,
  }) : items = items ?? [];

  final String id;
  final String siteId;
  final String buildingCode;
  final DateTime inspectionDate;
  String inspectionTime;
  String floorLabel;
  String locationLabel;
  String inspectorName;
  final String? inspectorUserId;
  String? signaturePath;
  InspectionStatus status;
  ReviewStatus reviewStatus;
  final DateTime? submittedAt;
  final String? submittedBy;
  final DateTime? approvedAt;
  final String? approvedBy;
  final String? workflowNote;
  final DateTime? workflowChangedAt;
  final String? workflowChangedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  int version;
  final String referenceNo;
  final String? templateId;
  final String? templateCodeSnapshot;
  final int? templateVersionSnapshot;
  final String? templateNameEnSnapshot;
  final String? templateNameArSnapshot;
  final List<InspectionItem> items;
  final String siteNameEn;
  final String siteNameAr;
  final String pin;
  final String organizationId;
  final String formTheme;
  final String? formThemeAccent;
  final String? parentSiteId;
  final String? parentFormTheme;
  final String? parentFormThemeAccent;
  final String? resolvedFormTheme;
  final String? resolvedFormThemeAccent;
  final String? formThemeSource;

  /// Effective paper/list theme, including campus inheritance.
  FormPaperTheme get paperTheme => FormPaperTheme.resolve(
    themeDb: resolvedFormTheme ?? formTheme,
    accentHex: resolvedFormThemeAccent ?? formThemeAccent,
    parentThemeDb: parentFormTheme,
    parentAccentHex: parentFormThemeAccent,
  );

  bool get isSubmitted => status == InspectionStatus.submitted;
  bool get isApproved => reviewStatus == ReviewStatus.approved;
  bool get awaitingReview => reviewStatus == ReviewStatus.submitted;
  bool get isReturned => reviewStatus == ReviewStatus.returned;
  bool get isTerminal => reviewStatus.isTerminal;

  String get dateIso =>
      '${inspectionDate.year.toString().padLeft(4, '0')}-'
      '${inspectionDate.month.toString().padLeft(2, '0')}-'
      '${inspectionDate.day.toString().padLeft(2, '0')}';

  String get bldgNo {
    final m = RegExp(r'(\d+)').firstMatch(buildingCode);
    return m?.group(1) ?? buildingCode;
  }

  factory Inspection.fromJson(
    Map<String, dynamic> json, {
    List<InspectionItem>? items,
  }) {
    final site = json['sites'] as Map<String, dynamic>?;
    return Inspection(
      id: json['id'] as String,
      siteId: json['site_id'] as String,
      buildingCode: (json['building_code'] ?? '') as String,
      inspectionDate: DateTime.parse(json['inspection_date'] as String),
      inspectionTime: (json['inspection_time'] ?? '') as String,
      floorLabel: (json['floor_label'] ?? 'ALL') as String,
      locationLabel:
          (json['location_label'] ?? 'MOEHE Permanent Headquarters') as String,
      inspectorName: (json['inspector_name'] ?? '') as String,
      inspectorUserId: json['inspector_user_id'] as String?,
      signaturePath: json['signature_path'] as String?,
      status: InspectionStatus.fromDb((json['status'] ?? 'draft') as String),
      reviewStatus: ReviewStatus.fromDb(
        json['review_status'] as String? ?? 'draft',
      ),
      submittedAt: json['submitted_at'] != null
          ? DateTime.tryParse(json['submitted_at'] as String)
          : null,
      submittedBy: json['submitted_by'] as String?,
      approvedAt: json['approved_at'] != null
          ? DateTime.tryParse(json['approved_at'] as String)
          : null,
      approvedBy: json['approved_by'] as String?,
      workflowNote: json['workflow_note'] as String?,
      workflowChangedAt: json['workflow_changed_at'] != null
          ? DateTime.tryParse(json['workflow_changed_at'] as String)
          : null,
      workflowChangedBy: json['workflow_changed_by'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
      version: (json['version'] as num?)?.toInt() ?? 1,
      referenceNo: (json['reference_no'] ?? '') as String,
      templateId: json['template_id'] as String?,
      templateCodeSnapshot: json['template_code_snapshot'] as String?,
      templateVersionSnapshot: (json['template_version_snapshot'] as num?)
          ?.toInt(),
      templateNameEnSnapshot: json['template_name_en_snapshot'] as String?,
      templateNameArSnapshot: json['template_name_ar_snapshot'] as String?,
      items: items,
      siteNameEn: (site?['name_en'] ?? '') as String,
      siteNameAr: (site?['name_ar'] ?? '') as String,
      pin: (site?['pin'] ?? '') as String,
      organizationId:
          (site?['organization_id'] ?? json['organization_id'] ?? '') as String,
      formTheme: (site?['form_theme'] as String?) ?? 'classic_gold',
      formThemeAccent: site?['form_theme_accent'] as String?,
      parentSiteId: site?['parent_site_id'] as String?,
      parentFormTheme: json['_parent_form_theme'] as String?,
      parentFormThemeAccent: json['_parent_form_theme_accent'] as String?,
      resolvedFormTheme: json['_resolved_form_theme'] as String?,
      resolvedFormThemeAccent: json['_resolved_form_theme_accent'] as String?,
      formThemeSource: json['_form_theme_source'] as String?,
    );
  }
}

class ChecklistCorrection {
  const ChecklistCorrection({
    required this.id,
    required this.inspectionId,
    this.itemId,
    required this.fieldName,
    this.oldValue,
    this.newValue,
    this.reason = '',
    required this.correctedBy,
    required this.createdAt,
  });

  final String id;
  final String inspectionId;
  final String? itemId;
  final String fieldName;
  final String? oldValue;
  final String? newValue;
  final String reason;
  final String correctedBy;
  final DateTime createdAt;

  factory ChecklistCorrection.fromJson(Map<String, dynamic> json) {
    return ChecklistCorrection(
      id: json['id'] as String,
      inspectionId: json['inspection_id'] as String,
      itemId: json['item_id'] as String?,
      fieldName: (json['field_name'] ?? '') as String,
      oldValue: json['old_value'] as String?,
      newValue: json['new_value'] as String?,
      reason: (json['reason'] ?? '') as String,
      correctedBy: json['corrected_by'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
