import '../models/catalog.dart';
import '../models/inspection.dart';

/// Result of validating problem photos against org policy.
class PhotoPolicyResult {
  const PhotoPolicyResult({
    required this.ok,
    required this.missingItemIndexes,
    required this.severity,
    this.messageAr = '',
    this.messageEn = '',
  });

  final bool ok;
  final List<int> missingItemIndexes;
  final PolicySeverity severity;
  final String messageAr;
  final String messageEn;

  bool get blocksSubmit => !ok && severity == PolicySeverity.critical;

  bool get shouldWarn =>
      !ok &&
      (severity == PolicySeverity.warning || severity == PolicySeverity.info);

  String messageFor(String language) =>
      language == 'ar' ? messageAr : messageEn;
}

/// Items with a problem but no issue photo.
List<InspectionItem> itemsMissingProblemPhoto(Inspection inspection) {
  return inspection.items
      .where((i) => i.isProblem && !i.hasIssuePhoto)
      .toList();
}

/// Previous day was a problem; today answered ideal (repair) without fix photo.
List<InspectionItem> itemsMissingFixPhoto({
  required Inspection inspection,
  required Map<int, InspectionItem> previousByIndex,
}) {
  return inspection.items.where((item) {
    final prev = previousByIndex[item.itemIndex];
    if (prev == null || !prev.isProblem) return false;
    // Closing the work order: previous problem → current ideal answer.
    if (!item.isIdealAnswer) return false;
    // Prefer pair-complete: every issue unit on this item should have a fix,
    // or at least one fix photo when migrating legacy/incomplete pairs.
    if (item.photoPairs.isNotEmpty) {
      final open = item.photoPairs.where((p) => p.hasIssue && !p.hasFix);
      if (open.isNotEmpty) return true;
      return !item.hasFixPhoto;
    }
    return !item.hasFixPhoto;
  }).toList();
}

/// Problem item that still has issue units without a linked fix photo.
List<InspectionItem> itemsWithUnpairedFixPhotos(Inspection inspection) {
  return inspection.items.where((item) {
    if (!item.isProblem) return false;
    return item.photoPairs.any((p) => p.hasIssue && !p.hasFix);
  }).toList();
}

PhotoPolicyResult validateProblemPhotos({
  required Inspection inspection,
  required ChecklistOrgPolicy policy,
}) {
  if (!policy.photoRequiredOnProblem) {
    return PhotoPolicyResult(
      ok: true,
      missingItemIndexes: const [],
      severity: policy.missingPhotoSeverity,
    );
  }
  final missing = itemsMissingProblemPhoto(inspection);
  if (missing.isEmpty) {
    return PhotoPolicyResult(
      ok: true,
      missingItemIndexes: const [],
      severity: policy.missingPhotoSeverity,
    );
  }
  final indexes = missing.map((e) => e.itemIndex).toList();
  final list = indexes.join(', ');
  return PhotoPolicyResult(
    ok: false,
    missingItemIndexes: indexes,
    severity: policy.missingPhotoSeverity,
    messageAr: 'بنود بمشكلة بدون صورة: $list. أضف صورة المشكلة قبل الإرسال.',
    messageEn:
        'Problem items without photo: $list. Attach an issue photo before submit.',
  );
}

/// Full Entry submit checks: issue photos + fix photos to close prior WOs.
class EntryPhotoGateResult {
  const EntryPhotoGateResult({
    required this.ok,
    this.missingIssueIndexes = const [],
    this.missingFixIndexes = const [],
    this.messageAr = '',
    this.messageEn = '',
    this.severity = PolicySeverity.critical,
  });

  final bool ok;
  final List<int> missingIssueIndexes;
  final List<int> missingFixIndexes;
  final String messageAr;
  final String messageEn;
  final PolicySeverity severity;

  bool get blocksSubmit => !ok;

  String messageFor(String language) =>
      language == 'ar' ? messageAr : messageEn;
}

EntryPhotoGateResult validateEntryPhotos({
  required Inspection inspection,
  required ChecklistOrgPolicy policy,
  required Map<int, InspectionItem> previousByIndex,
}) {
  final issueMissing = policy.photoRequiredOnProblem
      ? itemsMissingProblemPhoto(inspection)
      : <InspectionItem>[];
  final fixMissing = itemsMissingFixPhoto(
    inspection: inspection,
    previousByIndex: previousByIndex,
  );

  if (issueMissing.isEmpty && fixMissing.isEmpty) {
    return const EntryPhotoGateResult(ok: true);
  }

  final issueIdx = issueMissing.map((e) => e.itemIndex).toList();
  final fixIdx = fixMissing.map((e) => e.itemIndex).toList();
  final partsAr = <String>[];
  final partsEn = <String>[];
  if (issueIdx.isNotEmpty) {
    partsAr.add('صورة مشكلة ناقصة للبنود: ${issueIdx.join(', ')}');
    partsEn.add('Missing problem photo for items: ${issueIdx.join(', ')}');
  }
  if (fixIdx.isNotEmpty) {
    partsAr.add(
      'صورة إصلاح مطلوبة لإغلاق أمر العمل للبنود: ${fixIdx.join(', ')}',
    );
    partsEn.add(
      'Repair photo required to close work order for items: ${fixIdx.join(', ')}',
    );
  }
  return EntryPhotoGateResult(
    ok: false,
    missingIssueIndexes: issueIdx,
    missingFixIndexes: fixIdx,
    messageAr: partsAr.join('\n'),
    messageEn: partsEn.join('\n'),
    severity: policy.photoRequiredOnProblem
        ? policy.missingPhotoSeverity
        : PolicySeverity.critical,
  );
}

bool isItemOverdue({
  required int itemIndex,
  required DateTime asOfDate,
  required int overdueDays,
  required Map<String, Map<int, bool>> problemByDateIso,
}) {
  if (overdueDays <= 0) return false;
  var streak = 0;
  for (var i = 0; i < overdueDays; i++) {
    final d = asOfDate.subtract(Duration(days: i));
    final iso =
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final dayMap = problemByDateIso[iso];
    if (dayMap == null || dayMap[itemIndex] != true) {
      return false;
    }
    streak++;
  }
  return streak >= overdueDays;
}

Map<String, Map<int, bool>> buildProblemHistory({
  required List<Inspection> history,
  Inspection? current,
}) {
  final map = <String, Map<int, bool>>{};
  void absorb(Inspection insp) {
    final day = map.putIfAbsent(insp.dateIso, () => <int, bool>{});
    for (final item in insp.items) {
      // Same calendar day with multiple checklists: problem if ANY list
      // still flags the item (keeps open WOs from earlier lists counted).
      day[item.itemIndex] = (day[item.itemIndex] == true) || item.isProblem;
    }
  }

  for (final insp in history) {
    absorb(insp);
  }
  if (current != null) {
    absorb(current);
  }
  return map;
}

Set<int> overdueItemIndexes({
  required Inspection inspection,
  required Map<String, Map<int, bool>> problemByDateIso,
  int defaultOverdueDays = 3,
}) {
  final out = <int>{};
  for (final item in inspection.items) {
    if (!item.isProblem) continue;
    final days = item.overdueAfterDays > 0
        ? item.overdueAfterDays
        : defaultOverdueDays;
    if (days <= 0) continue;
    if (isItemOverdue(
      itemIndex: item.itemIndex,
      asOfDate: inspection.inspectionDate,
      overdueDays: days,
      problemByDateIso: problemByDateIso,
    )) {
      out.add(item.itemIndex);
    }
  }
  return out;
}
