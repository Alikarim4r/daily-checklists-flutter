import '../models/enums.dart';
import '../models/inspection.dart';

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
