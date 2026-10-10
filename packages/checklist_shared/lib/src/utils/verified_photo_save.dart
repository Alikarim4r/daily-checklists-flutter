import '../models/inspection.dart';
import 'storage_path_list.dart';

/// Confirms the complete upload -> inspection RPC -> authoritative read path.
/// A cloud object or evidence row alone does NOT mean the photo was saved on
/// the checklist. Never claim success without checking the inspection row.
class VerifiedPhotoSave {
  const VerifiedPhotoSave._();

  static bool isLinked(Inspection latest, String path) {
    final normalized = storagePathOf(path);
    if (normalized.isEmpty) return false;
    return latest.items.any(
      (item) => item.remarkPhotos.any(
        (photo) => storagePathOf(photo.path) == normalized,
      ),
    );
  }

  /// Handles lost API responses: saving may commit even if the client request
  /// times out. Read the server before reporting an error or retrying a save.
  /// No blind retry of stale-version RPCs (optimistic concurrency protection).
  static Future<Inspection> saveAndConfirm({
    required Inspection local,
    required String photoPath,
    required Future<void> Function(Inspection) save,
    required Future<Inspection?> Function(String) reload,
  }) async {
    Object? saveError;
    StackTrace? saveStack;
    try {
      await save(local);
    } catch (error, stack) {
      saveError = error;
      saveStack = stack;
    }
    Inspection? authoritative;
    try {
      authoritative = await reload(local.id);
    } catch (_) {
      // Preserve the original error if save failed, or signal uncertainty.
    }
    if (authoritative != null && isLinked(authoritative, photoPath)) {
      local.version = authoritative.version;
      return authoritative;
    }
    if (saveError != null) {
      Error.throwWithStackTrace(saveError, saveStack!);
    }
    throw StateError(
      'Photo was uploaded, but its attachment could not be confirmed on the '
      'saved inspection. Keep the form open and retry Save.',
    );
  }
}
