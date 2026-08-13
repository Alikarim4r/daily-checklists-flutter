import 'dart:convert';
import 'dart:math' as math;

import 'storage_path_list.dart';

/// One issue↔fix evidence pair for a checklist item (e.g. one AC unit).
class InspectionPhotoPair {
  InspectionPhotoPair({required this.id, this.issuePath, this.fixPath});

  final String id;
  String? issuePath;
  String? fixPath;

  bool get hasIssue => (issuePath ?? '').trim().isNotEmpty;

  bool get hasFix => (fixPath ?? '').trim().isNotEmpty;

  bool get isEmpty => !hasIssue && !hasFix;

  InspectionPhotoPair copyWith({
    String? id,
    String? issuePath,
    String? fixPath,
    bool clearIssue = false,
    bool clearFix = false,
  }) {
    return InspectionPhotoPair(
      id: id ?? this.id,
      issuePath: clearIssue ? null : (issuePath ?? this.issuePath),
      fixPath: clearFix ? null : (fixPath ?? this.fixPath),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    if (hasIssue) 'issue': issuePath!.trim(),
    if (hasFix) 'fix': fixPath!.trim(),
  };

  factory InspectionPhotoPair.fromJson(Map<String, dynamic> json) {
    return InspectionPhotoPair(
      id: '${json['id'] ?? newPhotoPairId()}',
      issuePath: _cleanPath(json['issue']),
      fixPath: _cleanPath(json['fix']),
    );
  }
}

String? _cleanPath(dynamic raw) {
  if (raw == null) return null;
  final p = storagePathOf('$raw'.trim());
  return p.isEmpty ? null : p;
}

String newPhotoPairId() {
  final r = math.Random();
  return 'p_${DateTime.now().microsecondsSinceEpoch}_${r.nextInt(1 << 32)}';
}

/// Encode pairs as JSON v2 for [issue_image_path].
String? encodePhotoPairsV2(List<InspectionPhotoPair> pairs) {
  final clean = [
    for (final p in pairs)
      if (!p.isEmpty) p,
  ];
  if (clean.isEmpty) return null;
  return jsonEncode({
    'v': 2,
    'pairs': [for (final p in clean) p.toJson()],
  });
}

/// Tagged fix list mirrored into [fix_image_path] for legacy readers.
String? encodeFixPathsMirror(List<InspectionPhotoPair> pairs) {
  return encodeStoragePathList([
    for (final p in pairs)
      if (p.hasFix) tagStoragePath(p.fixPath!, RemarkPhotoKind.fix),
  ]);
}

bool isPhotoPairsV2Payload(String? raw) {
  final s = raw?.trim() ?? '';
  if (!s.startsWith('{')) return false;
  try {
    final decoded = jsonDecode(s);
    return decoded is Map && decoded['v'] == 2 && decoded['pairs'] is List;
  } catch (_) {
    return false;
  }
}

/// Decode v2 JSON or zip legacy issue/fix columns by index.
List<InspectionPhotoPair> decodePhotoPairs({
  String? issueImagePath,
  String? fixImagePath,
  String? imagePath,
}) {
  final issueRaw = issueImagePath ?? imagePath;
  if (isPhotoPairsV2Payload(issueRaw)) {
    final map = jsonDecode(issueRaw!.trim()) as Map<String, dynamic>;
    final list = map['pairs'] as List;
    return [
      for (final e in list)
        if (e is Map)
          InspectionPhotoPair.fromJson(Map<String, dynamic>.from(e)),
    ].where((p) => !p.isEmpty).toList();
  }

  final issues = <String>[];
  for (final p in decodeStoragePathList(issueRaw)) {
    if (remarkPhotoKindFromTagged(p) == RemarkPhotoKind.fix) continue;
    final path = storagePathOf(p);
    if (path.isNotEmpty) issues.add(path);
  }
  final fixes = <String>[];
  for (final p in decodeStoragePathList(fixImagePath)) {
    if (remarkPhotoKindFromTagged(p) == RemarkPhotoKind.issue) continue;
    final path = storagePathOf(p);
    if (path.isNotEmpty) fixes.add(path);
  }

  final n = math.max(issues.length, fixes.length);
  if (n == 0) return const [];
  return [
    for (var i = 0; i < n; i++)
      InspectionPhotoPair(
        id: newPhotoPairId(),
        issuePath: i < issues.length ? issues[i] : null,
        fixPath: i < fixes.length ? fixes[i] : null,
      ),
  ];
}

/// Auto label: وحدة 1 / Unit 1 (1-based).
String photoPairLabel(int index1Based, {required bool arabic}) =>
    arabic ? 'وحدة $index1Based' : 'Unit $index1Based';
