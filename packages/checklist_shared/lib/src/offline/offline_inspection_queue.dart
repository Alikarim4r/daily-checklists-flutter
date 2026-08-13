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
  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(
      migrateOnAlgorithmChange: true,
      migrateWithBackup: true,
    ),
    mOptions: MacOsOptions(usesDataProtectionKeychain: true),
  );

  static Future<void> init() async {
    await Hive.initFlutter();
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

  Box<String> get _box => Hive.box<String>(_boxName);

  Future<void> enqueue({
    required String localId,
    required Map<String, dynamic> payload,
  }) async {
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
        },
      }),
    );
  }

  Future<void> markAttempt(String localId) async {
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

  Future<void> remove(String localId) => _box.delete(localId);

  List<MapEntry<String, Map<String, dynamic>>> pending() {
    final entries = <MapEntry<String, Map<String, dynamic>>>[];
    for (final key in _box.keys) {
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

  int get pendingCount => _box.length;

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
