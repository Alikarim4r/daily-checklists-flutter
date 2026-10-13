import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/profile.dart';

/// Encrypted local outbox of unsynced checklist inspections.
class OfflineInspectionQueue {
  OfflineInspectionQueue._();
  static final instance = OfflineInspectionQueue._();

  static const _boxName = 'checklist_offline_queue';
  static const _keyName = 'checklist.offline_queue.encryption_key.v1';
  static const _lastSyncKey = 'checklist.offline_queue.last_success.v1';
  static const _hierarchyPrefix = '__hierarchy_cache__:';
  static const _offlineProfileKey = '__offline_profile__';
  static const _catalogPrefix = '__catalog_cache__:';
  static const _ppmCachePrefix = '__ppm_cache__:';
  static const _ppmOutboxPrefix = '__ppm_outbox__:';
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

  bool get isReady => Hive.isBoxOpen(_boxName);

  Box<String> get _box => Hive.box<String>(_boxName);

  Future<void> cacheOfflineProfile(
    Profile profile, {
    List<UserSiteAccess> siteAccess = const [],
  }) async {
    if (!isReady) return;
    await _box.put(
      _offlineProfileKey,
      jsonEncode({
        'id': profile.id,
        'full_name': profile.fullName,
        'email': profile.email,
        'role': profile.role.dbValue,
        'is_active': profile.isActive,
        'approval_status': profile.approvalStatus.dbValue,
        'is_platform_owner': profile.isPlatformOwner,
        'home_organization_id': profile.homeOrganizationId,
        'site_access': [
          for (final access in siteAccess)
            {
              'id': access.id,
              'user_id': access.userId,
              'site_id': access.siteId,
              'role': access.role.dbValue,
              'can_read': access.canRead,
              'can_write': access.canWrite,
              'can_manage': access.canManage,
              'valid_from': access.validFrom?.toUtc().toIso8601String(),
              'valid_until': access.validUntil?.toUtc().toIso8601String(),
            },
        ],
      }),
    );
  }

  Profile? cachedOfflineProfile() {
    if (!isReady) return null;
    final value = _decode(_box.get(_offlineProfileKey));
    if (value == null) return null;
    try {
      return Profile.fromJson(value);
    } catch (_) {
      return null;
    }
  }

  List<UserSiteAccess> cachedOfflineSiteAccess() {
    if (!isReady) return const [];
    final value = _decode(_box.get(_offlineProfileKey));
    final raw = value?['site_access'];
    if (raw is! List) return const [];
    try {
      return [
        for (final row in raw)
          UserSiteAccess.fromJson(Map<String, dynamic>.from(row as Map)),
      ];
    } catch (_) {
      return const [];
    }
  }

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

  Future<void> markDeferred(String localId) async {
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
  }) => _box.put('$_hierarchyPrefix$userId', jsonEncode(payload));

  Map<String, dynamic>? cachedHierarchy(String userId) =>
      _decode(_box.get('$_hierarchyPrefix$userId'));

  Future<void> cacheCatalog({
    required String siteId,
    required String checklistType,
    required List<Map<String, dynamic>> items,
  }) async {
    if (!isReady) return;
    await _box.put(
      '$_catalogPrefix$siteId',
      jsonEncode({
        'siteId': siteId,
        'checklistType': checklistType,
        'cachedAt': DateTime.now().toUtc().toIso8601String(),
        'items': items,
      }),
    );
  }

  Map<String, dynamic>? cachedCatalog(String siteId) {
    if (!isReady) return null;
    return _decode(_box.get('$_catalogPrefix$siteId'));
  }

  /// PPM entries share the existing AES-256 encrypted Hive box but never
  /// enter the inspection synchronization path.
  Future<void> cachePpmJobs({
    required String userId,
    required List<Map<String, dynamic>> jobs,
    required List<Map<String, dynamic>> assets,
    required List<Map<String, dynamic>> plans,
  }) async {
    if (!isReady) return;
    await _box.put(
      '$_ppmCachePrefix$userId',
      jsonEncode({
        'jobs': jobs,
        'assets': assets,
        'plans': plans,
        'cachedAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  Map<String, dynamic>? cachedPpmJobs(String userId) {
    if (!isReady) return null;
    return _decode(_box.get('$_ppmCachePrefix$userId'));
  }

  Future<void> enqueuePpmCompletion({
    required String userId,
    required String jobId,
    required String notes,
    required Map<String, dynamic> readings,
    String? inspectionId,
  }) async {
    if (!isReady) throw StateError('Offline encryption not available');
    if (notes.trim().length < 5) {
      throw ArgumentError('PPM work details required');
    }
    await _box.put(
      '$_ppmOutboxPrefix$userId:$jobId',
      jsonEncode({
        'userId': userId,
        'jobId': jobId,
        'notes': notes.trim(),
        'readings': readings,
        'inspectionId': inspectionId,
        'queuedAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  List<MapEntry<String, Map<String, dynamic>>> pendingPpm(String userId) {
    if (!isReady) return const [];
    final prefix = '$_ppmOutboxPrefix$userId:';
    return [
      for (final key in _box.keys)
        if (key is String && key.startsWith(prefix))
          if (_decode(_box.get(key)) case final Map<String, dynamic> data)
            MapEntry(key, data),
    ];
  }

  int pendingPpmCount(String userId) => pendingPpm(userId).length;

  Future<void> removePpmIfQueued(String userId, String jobId) async {
    if (!isReady) return;
    await _box.delete('$_ppmOutboxPrefix$userId:$jobId');
  }

  Future<void> remove(String localId) => _box.delete(localId);

  List<MapEntry<String, Map<String, dynamic>>> pending() {
    final entries = <MapEntry<String, Map<String, dynamic>>>[];
    for (final key in _box.keys) {
      if (key is String &&
          (key.startsWith(_hierarchyPrefix) ||
              key.startsWith(_catalogPrefix) ||
              key.startsWith(_ppmCachePrefix) ||
              key.startsWith(_ppmOutboxPrefix) ||
              key == _offlineProfileKey)) {
        continue;
      }
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

  int get pendingCount => pending().length;

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

  /// Removes every user-bound local draft/cache after account deletion while
  /// keeping the encrypted Hive box open for a future sign-in.
  Future<void> purgeUserData() async {
    if (Hive.isBoxOpen(_boxName)) {
      await _box.clear();
    }
    await _secure.delete(key: _lastSyncKey);
  }

  Future<void> purgeUserDataIfReady() async {
    if (!isReady) return;
    await purgeUserData();
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
