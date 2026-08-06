import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

/// Local queue of unsynced checklist inspections (Entry offline support).
class OfflineInspectionQueue {
  OfflineInspectionQueue._();
  static final instance = OfflineInspectionQueue._();

  static const _boxName = 'checklist_offline_queue';

  static Future<void> init() async {
    await Hive.initFlutter();
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox<String>(_boxName);
    }
  }

  Box<String> get _box => Hive.box<String>(_boxName);

  Future<void> enqueue({
    required String localId,
    required Map<String, dynamic> payload,
  }) async {
    await _box.put(localId, jsonEncode(payload));
  }

  Future<void> remove(String localId) async {
    await _box.delete(localId);
  }

  List<MapEntry<String, Map<String, dynamic>>> pending() {
    return [
      for (final key in _box.keys)
        MapEntry(
          key as String,
          Map<String, dynamic>.from(
            jsonDecode(_box.get(key)!) as Map,
          ),
        ),
    ];
  }

  int get pendingCount => _box.length;
}
