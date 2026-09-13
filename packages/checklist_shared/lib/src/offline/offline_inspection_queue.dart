import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Encrypted local outbox of unsynced checklist inspections.
class OfflineInspectionQueue {
  OfflineInspectionQueue._();
  static final instance = OfflineInspectionQueue._();

  static const _boxName = 'checklist_offline_queue';
  static const _keyName = 'checklist.offline_queue.encryption_key.v1';
  static const _lastSyncKey = 'checklist.offline_queue.last_success.v1';
  static const _hierarchyPrefix = '__hierarchy_cache__:';
  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(
      migrateOnAlgorithmChange: true,
      migrateWithBackup: true,
    ),
    mOptions: MacOsOptions(usesDataProtectionKeychain: true),
  );

  static Future<void> init({String? storagePath}) async {
    if (storagePath == null) {
      await Hive.initFlutter();
    } else {
      // Deterministic isolated storage for regression tests.
      Hive.init(storagePath);
    }
    if (Hive.isBoxOpen(_boxName)) return;

    var encodedKey = await _secure.read(key: _keyName);
    final legacy = <dynamic, String>{};
    if (encodedKey == null) {
      // One-time migration from the old clear-text Hive box.
      if (await Hive.boxExists(_boxName)) {
        final old = await Hive.openBox<String>(_boxName);
        for (final key in old.keys) {
          final value = old.get(key);
          if (value != null) legacy[key] = value;
        }
        await old.close();
        await Hive.deleteBoxFromDisk(_boxName);
      }
      final random = Random.secure();
      final key = List<int>.generate(32, (_) => random.nextInt(256));
      encodedKey = base64UrlEncode(key);
      await _secure.write(key: _keyName, value: encodedKey);
    }

    final key = base64Url.decode(encodedKey);
    if (key.length != 32) {
      throw StateError('Invalid offline queue encryption key');
    }
    final box = await Hive.openBox<String>(
      _boxName,
      encryptionCipher: HiveAesCipher(key),
    );
    if (legacy.isNotEmpty) await box.putAll(legacy);
  }

  bool get isReady => Hive.isBoxOpen(_boxName);

  Box<String> get _box {
    if (!isReady) {
      throw StateError('Offline inspection queue is not available');
    }
    return Hive.box<String>(_boxName);
  }

  Future<void> enqueue({
    required String localId,
    required Map<String, dynamic> payload,
  }) async {
    if (!isReady) {
      throw StateError('Offline inspection queue is not available');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final previous = _decode(_box.get(localId));
    final previousMeta = previous?['_queue'] as Map?;
    await _box.put(
      localId,
      jsonEncode({
        ...payload,
        '_queue': {
          'createdAt': previousMeta?['createdAt'] ?? now,
          'updatedAt': now,
          'attempts': previousMeta?['attempts'] ?? 0,
          'status': 'pending',
          'lastError': null,
          // Every enqueue is a new immutable generation. Sync may only remove
          // the generation it actually processed; a newer user edit must win.
          'generation': _newGeneration(),
        },
      }),
    );
  }

  static String _newGeneration() {
    // Bit shifts of 32 bits wrap in JavaScript. Keep every random bound small
    // so the encrypted browser outbox uses the same safe path as native apps.
    final random = Random.secure();
    return base64UrlEncode(List<int>.generate(16, (_) => random.nextInt(256)));
  }

  /// Runs a full-snapshot save, removing only the outbox generation it covered.
  /// Partial mutations must save their other pending fields before using this.
  /// On failure the snapshot remains available for retry/crash recovery.
  Future<void> saveAndReconcile({
    required String localId,
    required Future<void> Function() save,
    required int Function() editRevision,
    required Future<void> Function() enqueueLatest,
  }) async {
    final generation = generationFor(localId);
    final revision = editRevision();
    await save();
    if (generationFor(localId) != generation) return;
    if (editRevision() != revision) {
      await enqueueLatest();
    } else {
      await removeIfGeneration(localId, generation);
    }
  }

  Future<void> markAttempt(String localId) async {
    if (!isReady) return;
    final payload = _decode(_box.get(localId));
    if (payload == null) return;
    final meta = Map<String, dynamic>.from(
      payload['_queue'] as Map? ?? const {},
    );
    meta['attempts'] = ((meta['attempts'] as num?)?.toInt() ?? 0) + 1;
    meta['status'] = 'syncing';
    meta['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    meta['lastError'] = null;
    payload['_queue'] = meta;
    await _box.put(localId, jsonEncode(payload));
  }

  Future<void> markFailure(String localId, Object error) async {
    if (!isReady) return;
    final payload = _decode(_box.get(localId));
    if (payload == null) return;
    final meta = Map<String, dynamic>.from(
      payload['_queue'] as Map? ?? const {},
    );
    meta['status'] = 'failed';
    meta['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    meta['lastError'] = '$error';
    payload['_queue'] = meta;
    await _box.put(localId, jsonEncode(payload));
  }

  Future<void> markDeferred(String localId) async {
    if (!isReady) return;
    final payload = _decode(_box.get(localId));
    if (payload == null) return;
    final meta = Map<String, dynamic>.from(
      payload['_queue'] as Map? ?? const {},
    );
    meta['status'] = 'pending';
    meta['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    meta['lastError'] = null;
    payload['_queue'] = meta;
    await _box.put(localId, jsonEncode(payload));
  }

  Future<void> cacheHierarchy({
    required String userId,
    required Map<String, dynamic> payload,
  }) {
    if (!isReady) return Future.value();
    return _box.put('$_hierarchyPrefix$userId', jsonEncode(payload));
  }

  Map<String, dynamic>? cachedHierarchy(String userId) =>
      isReady ? _decode(_box.get('$_hierarchyPrefix$userId')) : null;

  Future<void> remove(String localId) {
    if (!isReady) return Future.value();
    return _box.delete(localId);
  }

  /// Returns the immutable generation currently stored for [localId].
  ///
  /// Callers capture this before an authoritative network save and use
  /// [removeIfGeneration] afterwards. A newer edit enqueued while the request
  /// was in flight therefore cannot be removed accidentally.
  String? generationFor(String localId) {
    if (!isReady) return null;
    final payload = _decode(_box.get(localId));
    final meta = payload?['_queue'] as Map?;
    return meta?['generation'] as String?;
  }

  /// Removes [localId] only when it is still the exact queue generation that
  /// the caller processed. If the user saved a newer edit while sync was in
  /// flight, that newer generation remains safely queued.
  Future<bool> removeIfGeneration(
    String localId,
    String? expectedGeneration,
  ) async {
    if (!isReady) return false;
    final current = _decode(_box.get(localId));
    if (current == null) return false;

    final currentMeta = current['_queue'] as Map?;
    final currentGeneration = currentMeta?['generation'] as String?;

    // Legacy entries have no generation. They may be removed only when both
    // sides are legacy; newly enqueued entries always carry a generation.
    if (currentGeneration != expectedGeneration) return false;

    await _box.delete(localId);
    return true;
  }

  /// Applies a queue-state mutation only if no newer enqueue replaced the
  /// generation being synchronized.
  Future<bool> updateStateIfGeneration(
    String localId,
    String? expectedGeneration, {
    required String status,
    Object? error,
  }) async {
    if (!isReady) return false;
    final payload = _decode(_box.get(localId));
    if (payload == null) return false;

    final meta = Map<String, dynamic>.from(
      payload['_queue'] as Map? ?? const {},
    );
    final currentGeneration = meta['generation'] as String?;
    if (currentGeneration != expectedGeneration) return false;

    meta['status'] = status;
    meta['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    meta['lastError'] = error == null ? null : '$error';
    payload['_queue'] = meta;
    await _box.put(localId, jsonEncode(payload));
    return true;
  }

  List<MapEntry<String, Map<String, dynamic>>> pending() {
    if (!isReady) return const [];
    final entries = <MapEntry<String, Map<String, dynamic>>>[];
    for (final key in _box.keys) {
      if (key is String && key.startsWith(_hierarchyPrefix)) continue;
      final value = _decode(_box.get(key));
      if (key is String && value != null) entries.add(MapEntry(key, value));
    }
    entries.sort((a, b) {
      final aMeta = a.value['_queue'] as Map?;
      final bMeta = b.value['_queue'] as Map?;
      return '${aMeta?['createdAt'] ?? ''}'.compareTo(
        '${bMeta?['createdAt'] ?? ''}',
      );
    });
    return entries;
  }

  int get pendingCount => isReady ? pending().length : 0;

  int get failedCount => pending().where((entry) {
    final meta = entry.value['_queue'] as Map?;
    return meta?['status'] == 'failed';
  }).length;

  int get pendingImageCount => pending().fold<int>(0, (total, entry) {
    final media = entry.value['media'];
    return total + (media is List ? media.length : 0);
  });

  Future<void> recordSuccessfulSync() => _secure.write(
    key: _lastSyncKey,
    value: DateTime.now().toUtc().toIso8601String(),
  );

  Future<DateTime?> lastSuccessfulSyncAt() async {
    final raw = await _secure.read(key: _lastSyncKey);
    return raw == null ? null : DateTime.tryParse(raw)?.toLocal();
  }

  Map<String, dynamic>? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }
}
