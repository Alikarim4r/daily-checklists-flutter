import 'dart:convert';

/// Encode/decode one-or-many storage paths in a text column.
List<String> decodeStoragePathList(String? raw) {
  if (raw == null) return const [];
  final s = raw.trim();
  if (s.isEmpty) return const [];
  if (s.startsWith('[')) {
    try {
      final decoded = jsonDecode(s);
      if (decoded is List) {
        return [
          for (final e in decoded)
            '$e'.trim(),
        ].where((e) => e.isNotEmpty).toList();
      }
    } catch (_) {}
  }
  if (s.contains('\n') || s.contains('|')) {
    return s
        .split(RegExp(r'[\n|]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }
  return [s];
}

String? encodeStoragePathList(List<String> paths) {
  final clean = [
    for (final p in paths)
      if (p.trim().isNotEmpty) p.trim(),
  ];
  if (clean.isEmpty) return null;
  if (clean.length == 1) return clean.first;
  return jsonEncode(clean);
}

/// Permanent kind for a remark photo (never inferred only from UI state).
enum RemarkPhotoKind { issue, fix }

const _issueTag = 'issue:';
const _fixTag = 'fix:';

/// Strip `issue:` / `fix:` storage tags for Storage API / display.
String storagePathOf(String pathOrTagged) {
  final p = pathOrTagged.trim();
  if (p.startsWith(_issueTag)) return p.substring(_issueTag.length);
  if (p.startsWith(_fixTag)) return p.substring(_fixTag.length);
  return p;
}

/// Tag a raw storage path so its kind cannot flip later.
String tagStoragePath(String path, RemarkPhotoKind kind) {
  final raw = storagePathOf(path);
  if (raw.isEmpty) return raw;
  return kind == RemarkPhotoKind.fix ? '$_fixTag$raw' : '$_issueTag$raw';
}

RemarkPhotoKind? remarkPhotoKindFromTagged(String path) {
  final p = path.trim();
  if (p.startsWith(_fixTag)) return RemarkPhotoKind.fix;
  if (p.startsWith(_issueTag)) return RemarkPhotoKind.issue;
  return null;
}

/// Infer kind from stamped filename (`…_issue_…` / `…_fix_…`) for legacy rows.
RemarkPhotoKind? remarkPhotoKindFromPath(String path) {
  final tagged = remarkPhotoKindFromTagged(path);
  if (tagged != null) return tagged;
  final name = storagePathOf(path).split('/').last.toLowerCase();
  if (name.contains('_fix_') || name.contains('_fix.')) {
    return RemarkPhotoKind.fix;
  }
  if (name.contains('_issue_') || name.contains('_issue.')) {
    return RemarkPhotoKind.issue;
  }
  return null;
}
