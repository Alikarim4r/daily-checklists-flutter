import 'enums.dart';
import '../utils/storage_path_list.dart';

class InspectionItem {
  InspectionItem({
    this.id,
    required this.itemIndex,
    required this.description,
    this.descriptionAr,
    this.response,
    this.actionsTaken = '',
    this.imagePath,
    this.issueImagePath,
    this.fixImagePath,
    this.defaultAnswer = 'Y',
    this.isCustom = false,
    this.overdueAfterDays = 3,
  });

  final String? id;
  final int itemIndex;
  final String description;
  final String? descriptionAr;
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

  List<String> get issueImagePaths =>
      decodeStoragePathList(issueImagePath ?? imagePath);

  List<String> get fixImagePaths => decodeStoragePathList(fixImagePath);

  /// Stable ordered remark photos with a permanent kind per path.
  /// Filename stamp wins; otherwise the DB column the path lives in.
  List<({String path, RemarkPhotoKind kind})> get remarkPhotos {
    final ordered = <String>[];
    final seen = <String>{};
    for (final p in [...issueImagePaths, ...fixImagePaths]) {
      if (p.isEmpty || !seen.add(p)) continue;
      ordered.add(p);
    }
    final issueSet = issueImagePaths.toSet();
    final fixSet = fixImagePaths.toSet();
    return [
      for (final p in ordered)
        (
          path: p,
          kind: remarkPhotoKindFromPath(p) ??
              (fixSet.contains(p) && !issueSet.contains(p)
                  ? RemarkPhotoKind.fix
                  : issueSet.contains(p) && !fixSet.contains(p)
                      ? RemarkPhotoKind.issue
                      : fixSet.contains(p)
                          ? RemarkPhotoKind.fix
                          : RemarkPhotoKind.issue),
        ),
    ];
  }

  void setIssueImagePaths(List<String> paths) {
    issueImagePath = encodeStoragePathList(paths);
    imagePath = paths.isEmpty ? null : paths.first;
  }

  void setFixImagePaths(List<String> paths) {
    fixImagePath = encodeStoragePathList(paths);
  }

  /// Keep columns aligned with each path's permanent kind.
  void _commitPhotoBuckets(
    Iterable<({String path, RemarkPhotoKind kind})> photos,
  ) {
    final issues = <String>[];
    final fixes = <String>[];
    final seen = <String>{};
    for (final photo in photos) {
      if (photo.path.isEmpty || !seen.add(photo.path)) continue;
      if (photo.kind == RemarkPhotoKind.fix) {
        fixes.add(photo.path);
      } else {
        issues.add(photo.path);
      }
    }
    setIssueImagePaths(issues);
    setFixImagePaths(fixes);
  }

  void appendIssueImage(String path) {
    if (path.trim().isEmpty) return;
    final next = [
      for (final p in remarkPhotos)
        if (p.path != path) p,
      (path: path, kind: RemarkPhotoKind.issue),
    ];
    _commitPhotoBuckets(next);
  }

  void appendFixImage(String path) {
    if (path.trim().isEmpty) return;
    final next = [
      for (final p in remarkPhotos)
        if (p.path != path) p,
      (path: path, kind: RemarkPhotoKind.fix),
    ];
    _commitPhotoBuckets(next);
  }

  void removeIssueImage(String path) {
    _commitPhotoBuckets([
      for (final p in remarkPhotos)
        if (p.path != path) p,
    ]);
  }

  void removeFixImage(String path) {
    _commitPhotoBuckets([
      for (final p in remarkPhotos)
        if (p.path != path) p,
    ]);
  }

  String descriptionFor(String language) =>
      language == 'ar' && (descriptionAr ?? '').isNotEmpty
          ? descriptionAr!
          : description;

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
        ChecklistResponse.fromDb(rawDefault)?.shortCode ?? rawDefault.toUpperCase();
    final issuePaths = decodeStoragePathList(
      json['issue_image_path'] as String? ?? json['image_path'] as String?,
    );
    final fixPaths =
        decodeStoragePathList(json['fix_image_path'] as String?);
    final item = InspectionItem(
      id: json['id'] as String?,
      itemIndex: json['item_index'] as int,
      description: (json['description'] ?? '') as String,
      descriptionAr: json['description_ar'] as String?,
      response: ChecklistResponse.fromDb(json['response'] as String?),
      actionsTaken: (json['actions_taken'] ?? '') as String,
      imagePath: issuePaths.isEmpty ? null : issuePaths.first,
      issueImagePath: encodeStoragePathList(issuePaths),
      fixImagePath: encodeStoragePathList(fixPaths),
      defaultAnswer: defaultAnswer,
      isCustom: json['is_custom'] as bool? ?? false,
      overdueAfterDays: (json['overdue_after_days'] as num?)?.toInt() ?? 3,
    );
    // Re-bucket so filename stamps win and a path never flips kind later.
    item._commitPhotoBuckets(item.remarkPhotos);
    return item;
  }

  Map<String, dynamic> toInsertJson(String inspectionId) => {
        'inspection_id': inspectionId,
        'item_index': itemIndex,
        'description': description,
        if (descriptionAr != null) 'description_ar': descriptionAr,
        'response': response?.dbValue,
        'actions_taken': actionsTaken,
        'image_path': issueImagePaths.isEmpty ? null : issueImagePaths.first,
        'issue_image_path': encodeStoragePathList(issueImagePaths),
        'fix_image_path': encodeStoragePathList(fixImagePaths),
        'default_answer': defaultAnswer,
        'is_custom': isCustom,
        'overdue_after_days': overdueAfterDays,
      };

  Map<String, dynamic> toUpdateJson() => {
        'response': response?.dbValue,
        'actions_taken': actionsTaken,
        'image_path': issueImagePaths.isEmpty ? null : issueImagePaths.first,
        'issue_image_path': encodeStoragePathList(issueImagePaths),
        'fix_image_path': encodeStoragePathList(fixImagePaths),
        'default_answer': defaultAnswer,
        'overdue_after_days': overdueAfterDays,
      };
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
    this.createdAt,
    this.updatedAt,
    List<InspectionItem>? items,
    this.siteNameEn = '',
    this.siteNameAr = '',
    this.pin = '',
    this.organizationId = '',
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
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<InspectionItem> items;
  final String siteNameEn;
  final String siteNameAr;
  final String pin;
  final String organizationId;

  bool get isSubmitted => status == InspectionStatus.submitted;
  bool get isApproved => reviewStatus == ReviewStatus.approved;
  bool get awaitingReview => reviewStatus == ReviewStatus.submitted;

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
      reviewStatus:
          ReviewStatus.fromDb(json['review_status'] as String? ?? 'draft'),
      submittedAt: json['submitted_at'] != null
          ? DateTime.tryParse(json['submitted_at'] as String)
          : null,
      submittedBy: json['submitted_by'] as String?,
      approvedAt: json['approved_at'] != null
          ? DateTime.tryParse(json['approved_at'] as String)
          : null,
      approvedBy: json['approved_by'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
      items: items,
      siteNameEn: (site?['name_en'] ?? '') as String,
      siteNameAr: (site?['name_ar'] ?? '') as String,
      pin: (site?['pin'] ?? '') as String,
      organizationId: (site?['organization_id'] ??
              json['organization_id'] ??
              '') as String,
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
