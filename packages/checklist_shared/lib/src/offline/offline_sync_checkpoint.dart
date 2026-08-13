import '../models/enums.dart';
import '../models/inspection.dart';

/// Safe outcome for reconciling one encrypted outbox snapshot with the
/// authoritative inspection currently stored on the server.
enum OfflineSyncResolution {
  /// Server version still matches the snapshot; apply the queued changes.
  applyQueuedChanges,

  /// A previous attempt saved these exact values but stopped before clearing
  /// the outbox (or before completing submit). Resume from that checkpoint.
  resumeSavedCheckpoint,

  /// The inspection has already been submitted/approved. A lingering local
  /// autosave or submit entry is obsolete and must not overwrite final data.
  discardFinalizedSnapshot,

  /// Both sides changed and there is no proof that the queued snapshot is the
  /// source of the server update. Keep the entry for explicit review.
  conflict,
}

OfflineSyncResolution resolveOfflineSync({
  required Inspection server,
  required Map<String, dynamic> payload,
}) {
  if (server.isSubmitted || server.isApproved) {
    return OfflineSyncResolution.discardFinalizedSnapshot;
  }

  final baseVersion = (payload['baseVersion'] as num?)?.toInt();
  if (baseVersion == null || baseVersion == server.version) {
    return OfflineSyncResolution.applyQueuedChanges;
  }

  // Workflow transitions can increase the version more than once after a
  // successful save. Exact field equality is stronger evidence than assuming
  // that the checkpoint must be exactly baseVersion + 1.
  if (server.version > baseVersion &&
      queuedInspectionMatchesServer(server: server, payload: payload)) {
    return OfflineSyncResolution.resumeSavedCheckpoint;
  }

  return OfflineSyncResolution.conflict;
}

/// Confirms that an optimistic-lock version bump came from a previous outbox
/// attempt which saved successfully but stopped before the final submit.
bool queuedInspectionMatchesServer({
  required Inspection server,
  required Map<String, dynamic> payload,
}) {
  bool sameHeader(String key, String actual) {
    final queued = payload[key];
    return queued == null || '$queued' == actual;
  }

  bool sameStoredPath(Object? queuedValue, String? actual) {
    final queued = queuedValue?.toString() ?? '';
    final stored = actual ?? '';
    if (queued.isEmpty) return stored.isEmpty;
    if (queued.contains('offline://')) {
      return stored.isNotEmpty && !stored.contains('offline://');
    }
    return queued == stored;
  }

  if (!sameHeader('inspectorName', server.inspectorName) ||
      !sameHeader('inspectionTime', server.inspectionTime) ||
      !sameHeader('floorLabel', server.floorLabel) ||
      !sameStoredPath(payload['signaturePath'], server.signaturePath)) {
    return false;
  }

  final queuedItems = payload['items'];
  if (queuedItems is! List || queuedItems.length != server.items.length) {
    return false;
  }
  final serverByIndex = {for (final item in server.items) item.itemIndex: item};
  for (final raw in queuedItems) {
    if (raw is! Map) return false;
    final item = Map<String, dynamic>.from(raw);
    final index = (item['item_index'] as num?)?.toInt();
    final stored = serverByIndex[index];
    if (index == null || stored == null) return false;
    if (ChecklistResponse.fromDb(item['response'] as String?) !=
            stored.response ||
        '${item['actions_taken'] ?? ''}' != stored.actionsTaken ||
        !sameStoredPath(item['image_path'], stored.imagePath) ||
        !sameStoredPath(item['issue_image_path'], stored.issueImagePath) ||
        !sameStoredPath(item['fix_image_path'], stored.fixImagePath)) {
      return false;
    }
  }
  return true;
}
