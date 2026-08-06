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

/// Infer photo kind from stamped filename (`…_issue_…` / `…_fix_…`).
enum RemarkPhotoKind { issue, fix }

RemarkPhotoKind? remarkPhotoKindFromPath(String path) {
  final name = path.split('/').last.toLowerCase();
  if (name.contains('_fix_') || name.contains('_fix.')) {
    return RemarkPhotoKind.fix;
  }
  if (name.contains('_issue_') || name.contains('_issue.')) {
    return RemarkPhotoKind.issue;
  }
  return null;
}
